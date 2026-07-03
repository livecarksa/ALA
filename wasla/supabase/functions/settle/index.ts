// دالة settle الطرفية (Supabase Edge Function / Deno).
//
// تستقبل دفعة توكنات مرفوعة عند عودة الاتصال، تتحقق منها تشفيرياً
// وزمنياً (verify.ts)، ترتّب سلسلة كل مرسل من مرساة حجزه المفتوح، ثم
// تستدعي settle_accept لكل توكن **بالترتيب** — فتتكفل القاعدة بالذرّية
// وidempotency وكشف الإنفاق المزدوج والاتصال والسقف والرصيد.
//
// التقسيم مقصود: التوقيع Ed25519 يحتاج WebCrypto (تعذّر في SQL)، والحركة
// المالية الحرجة تبقى في معاملة قاعدة واحدة لكل توكن.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  issuedDay,
  tokenHash,
  verifyToken,
  type WaslaToken,
} from "./verify.ts";

interface SettleRequest {
  batch: WaslaToken[];
  now?: number;
}

interface TokenResult {
  token_id: string;
  status: string; // settled | duplicate | double_spend | daily_cap | ...
}

interface SettleResponse {
  settled: number;
  rejected: TokenResult[];
  frozen: string[];
  results: TokenResult[];
}

// ترتيب سلسلة مرسل من المرساة: أب قبل ابن، الأسبق إصداراً أولاً عند التساوي.
async function orderChain(
  tokens: WaslaToken[],
  anchor: string,
): Promise<WaslaToken[]> {
  const byPrev = new Map<string, WaslaToken[]>();
  for (const t of tokens) {
    (byPrev.get(t.prev_hash) ?? byPrev.set(t.prev_hash, []).get(t.prev_hash)!).push(t);
  }
  const hashOf = new Map<string, string>();
  for (const t of tokens) hashOf.set(t.token_id, await tokenHash(t));

  const ordered: WaslaToken[] = [];
  const seen = new Set<string>();
  let head = anchor;
  // السير الخطي على الفرع القانوني؛ ما لا يتصل يُلحق آخراً ليرفضه القاعدة.
  while (byPrev.has(head)) {
    const next = [...byPrev.get(head)!].sort((a, b) =>
      a.issued_at - b.issued_at || a.token_id.localeCompare(b.token_id)
    );
    const canonical = next[0];
    if (seen.has(canonical.token_id)) break;
    for (const t of next) {
      if (!seen.has(t.token_id)) {
        ordered.push(t);
        seen.add(t.token_id);
      }
    }
    head = hashOf.get(canonical.token_id)!;
  }
  for (const t of tokens) {
    if (!seen.has(t.token_id)) ordered.push(t); // سلاسل مبتورة/مفبركة.
  }
  return ordered;
}

export async function handleSettle(
  db: SupabaseClient,
  request: SettleRequest,
): Promise<SettleResponse> {
  const now = request.now ?? Math.floor(Date.now() / 1000);
  const results: TokenResult[] = [];
  const frozen = new Set<string>();

  // تجميع حسب المرسل.
  const bySender = new Map<string, WaslaToken[]>();
  for (const t of request.batch) {
    (bySender.get(t.sender_id) ?? bySender.set(t.sender_id, []).get(t.sender_id)!).push(t);
  }

  for (const [senderId, tokens] of bySender) {
    const { data: reservation } = await db
      .from("reservations")
      .select("chain_anchor")
      .eq("device_id", senderId)
      .eq("status", "open")
      .maybeSingle();
    const anchor = reservation?.chain_anchor ?? "";
    const ordered = anchor ? await orderChain(tokens, anchor) : tokens;

    for (const token of ordered) {
      // 1) تحقق تشفيري/زمني نقي.
      const verified = await verifyToken(token, now);
      if (!verified.ok) {
        results.push({ token_id: token.token_id, status: verified.reason });
        continue;
      }
      // 2) قبول ذرّي في القاعدة.
      const { data, error } = await db.rpc("settle_accept", {
        p_token_id: token.token_id,
        p_sender_id: token.sender_id,
        p_recipient_id: token.recipient_id,
        p_amount: token.amount,
        p_currency: token.currency,
        p_seq: token.seq,
        p_prev_hash: token.prev_hash,
        p_token_hash: await tokenHash(token),
        p_issued_day: issuedDay(token),
      });
      const status = error ? `error:${error.code ?? "unknown"}` : String(data);
      results.push({ token_id: token.token_id, status });
      if (status === "double_spend") frozen.add(senderId);
    }
  }

  const rejected = results.filter((r) => r.status !== "settled" && r.status !== "duplicate");
  return {
    settled: results.filter((r) => r.status === "settled").length,
    rejected,
    frozen: [...frozen],
    results,
  };
}

// نقطة الدخول الطرفية.
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST فقط" }), { status: 405 });
  }
  let body: SettleRequest;
  try {
    body = await req.json();
    if (!Array.isArray(body.batch)) throw new Error("batch مطلوبة");
  } catch (e) {
    return new Response(JSON.stringify({ error: `طلب غير صالح: ${e}` }), { status: 400 });
  }
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, // دور الخدمة يتجاوز RLS للتسوية.
  );
  try {
    const response = await handleSettle(db, body);
    return new Response(JSON.stringify(response), {
      headers: { "Content-Type": "application/json; charset=utf-8" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `خطأ داخلي: ${e}` }), { status: 500 });
  }
});
