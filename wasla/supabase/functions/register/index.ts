// تسجيل جهاز لدى طبقة التسوية (Supabase Edge Function / Deno).
//
// عقد الـPoC: العميل يقدّم مفتاحه العام، والخادم يشتق المعرّف بنفسه
// ويرفض أي معرّف لا يطابق (الهوية من المفتاح دائماً — لا تُصدَّق من
// العميل). ينشأ الحساب إن لم يوجد، ويُفتح حجز أوف لاين بحقبة 0 إن لم
// يوجد حجز مفتوح، ثم تعاد أرقام المحفظة كاملة.
//
// في الإنتاج يحل محل هذا ربط KYC بنكك — البنية نفسها تبقى.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  defaultDailyCapPiasters,
  defaultReservePiasters,
  freshAnchor,
  walletSnapshot,
} from "../_shared/wallet.ts";
import { deviceIdFromPubkey } from "../settle/verify.ts";

interface RegisterRequest {
  device_id: string;
  pubkey: string;
  reserve?: number;
  daily_cap?: number;
}

export async function handleRegister(
  db: SupabaseClient,
  request: RegisterRequest,
): Promise<Record<string, unknown>> {
  if (!/^[0-9a-f]{64}$/.test(request.pubkey ?? "")) {
    throw new Error("مفتاح عام غير صالح");
  }
  const derived = await deviceIdFromPubkey(request.pubkey);
  if (derived !== request.device_id) {
    throw new Error("المعرّف لا يطابق المفتاح العام");
  }

  const { data: existing } = await db
    .from("accounts")
    .select("pubkey")
    .eq("device_id", derived)
    .maybeSingle();
  if (existing == null) {
    const { error } = await db.from("accounts").insert({
      device_id: derived,
      pubkey: request.pubkey,
      balance: 0,
    });
    if (error) throw new Error(`تعذر إنشاء الحساب: ${error.message}`);
  } else if (existing.pubkey !== request.pubkey) {
    throw new Error("الجهاز مسجّل بمفتاح مختلف — يلزم استرداد عبر البنك");
  }

  const { data: open } = await db
    .from("reservations")
    .select("id")
    .eq("device_id", derived)
    .eq("status", "open")
    .maybeSingle();
  if (open == null) {
    const reserve = request.reserve ?? defaultReservePiasters;
    const { error } = await db.from("reservations").insert({
      device_id: derived,
      epoch: 0,
      reserved: reserve,
      remaining: reserve,
      daily_cap: request.daily_cap ?? defaultDailyCapPiasters,
      chain_anchor: await freshAnchor(derived, 0),
    });
    if (error) throw new Error(`تعذر فتح الحجز: ${error.message}`);
  }

  return { wallet: await walletSnapshot(db, derived) };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST فقط" }), { status: 405 });
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  try {
    const body = (await req.json()) as RegisterRequest;
    const result = await handleRegister(db, body);
    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e instanceof Error ? e.message : e) }),
      { status: 400 },
    );
  }
});
