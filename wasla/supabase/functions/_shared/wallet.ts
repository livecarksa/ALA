// مشترك دوال التسوية: لقطة المحفظة ومرساة حقبة جديدة.
// وحدة نقية بلا Deno.serve — تُستورد من register وsettle معاً.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { sha256Hex } from "../settle/verify.ts";

export const defaultReservePiasters = 500000; // 5,000 جنيه — رصيد ديمو
export const defaultDailyCapPiasters = 500000;

/// مرساة عشوائية لحقبة جديدة — عشوائية الخادم لا العميل.
export async function freshAnchor(
  deviceId: string,
  label: string | number,
): Promise<string> {
  const entropy = crypto.randomUUID();
  return await sha256Hex(
    new TextEncoder().encode(`anchor:${deviceId}:${label}:${entropy}`),
  );
}

/// أرقام محفظة جهاز: رصيد الدفتر + الحجز المفتوح.
export async function walletSnapshot(
  db: SupabaseClient,
  deviceId: string,
): Promise<Record<string, unknown>> {
  const { data: account } = await db
    .from("accounts")
    .select("balance, frozen")
    .eq("device_id", deviceId)
    .single();
  const { data: reservation } = await db
    .from("reservations")
    .select("epoch, remaining, daily_cap, chain_anchor")
    .eq("device_id", deviceId)
    .eq("status", "open")
    .maybeSingle();
  return {
    balance: account?.balance ?? 0,
    frozen: account?.frozen ?? false,
    epoch: reservation?.epoch ?? 0,
    remaining: reservation?.remaining ?? 0,
    daily_cap: reservation?.daily_cap ?? defaultDailyCapPiasters,
    chain_anchor: reservation?.chain_anchor ?? "",
  };
}
