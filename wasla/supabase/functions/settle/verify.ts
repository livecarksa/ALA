// التحقق التشفيري لتوكن وصلة داخل بيئة Deno (Edge Function).
//
// يطابق حرفياً التسلسل القانوني في wasla_core (Dart) وبرهان المفهوم
// (Python): JSON بمفاتيح مرتّبة بلا مسافات، توقيع Ed25519 عبر WebCrypto.
// إصدار البروتوكول ثابت هنا؛ أي تغيير يرفعه مع اختبار توافق خلفي.

export const tokenProtocolVersion = 1;
export const maxTokenTtlSeconds = 72 * 3600;
export const clockSkewToleranceSeconds = 2 * 3600;

export interface WaslaToken {
  token_id: string;
  sender_id: string;
  sender_pubkey: string;
  recipient_id: string;
  amount: number;
  currency: string;
  seq: number;
  prev_hash: string;
  issued_at: number;
  expires_at: number;
  signature: string;
}

const enc = new TextEncoder();

function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || !/^[0-9a-f]*$/.test(hex)) {
    throw new Error("hex غير صالح");
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return bytesToHex(new Uint8Array(digest));
}

// التسلسل القانوني: مفاتيح مرتّبة أبجدياً بلا مسافات (مطابق لـ Dart/Python).
export function canonicalPayload(t: WaslaToken): string {
  return "{" +
    `"amount":${t.amount},` +
    `"currency":${JSON.stringify(t.currency)},` +
    `"expires_at":${t.expires_at},` +
    `"issued_at":${t.issued_at},` +
    `"prev_hash":${JSON.stringify(t.prev_hash)},` +
    `"recipient_id":${JSON.stringify(t.recipient_id)},` +
    `"sender_id":${JSON.stringify(t.sender_id)},` +
    `"sender_pubkey":${JSON.stringify(t.sender_pubkey)},` +
    `"seq":${t.seq},` +
    `"token_id":${JSON.stringify(t.token_id)}` +
    "}";
}

// hash التوكن: يشمل التوقيع (signature يقع أبجدياً بين seq و token_id).
export async function tokenHash(t: WaslaToken): Promise<string> {
  const canonical = "{" +
    `"amount":${t.amount},` +
    `"currency":${JSON.stringify(t.currency)},` +
    `"expires_at":${t.expires_at},` +
    `"issued_at":${t.issued_at},` +
    `"prev_hash":${JSON.stringify(t.prev_hash)},` +
    `"recipient_id":${JSON.stringify(t.recipient_id)},` +
    `"sender_id":${JSON.stringify(t.sender_id)},` +
    `"sender_pubkey":${JSON.stringify(t.sender_pubkey)},` +
    `"seq":${t.seq},` +
    `"signature":${JSON.stringify(t.signature)},` +
    `"token_id":${JSON.stringify(t.token_id)}` +
    "}";
  return await sha256Hex(enc.encode(canonical));
}

export async function deviceIdFromPubkey(pubkeyHex: string): Promise<string> {
  return (await sha256Hex(hexToBytes(pubkeyHex))).slice(0, 16);
}

// اليوم UTC (YYYY-MM-DD) بيوم الإصدار — لعدّاد السقف.
export function issuedDay(t: WaslaToken): string {
  return new Date(t.issued_at * 1000).toISOString().slice(0, 10);
}

export type VerifyResult =
  | { ok: true }
  | { ok: false; reason: "bad_signature" | "expired" | "future_dated" | "bad_ttl" | "malformed" };

// تحقق تشفيري وزمني كامل — لا يمسّ حالة القاعدة (نقي).
export async function verifyToken(t: WaslaToken, now: number): Promise<VerifyResult> {
  if (!Number.isInteger(t.amount) || t.amount <= 0 || !/^[A-Z]{3}$/.test(t.currency)) {
    return { ok: false, reason: "malformed" };
  }
  let derived: string;
  try {
    derived = await deviceIdFromPubkey(t.sender_pubkey);
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (derived !== t.sender_id) return { ok: false, reason: "bad_signature" };

  let valid = false;
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      hexToBytes(t.sender_pubkey),
      { name: "Ed25519" },
      false,
      ["verify"],
    );
    valid = await crypto.subtle.verify(
      { name: "Ed25519" },
      key,
      hexToBytes(t.signature),
      enc.encode(canonicalPayload(t)),
    );
  } catch {
    return { ok: false, reason: "malformed" };
  }
  if (!valid) return { ok: false, reason: "bad_signature" };

  if (now > t.expires_at) return { ok: false, reason: "expired" };
  if (t.issued_at > now + clockSkewToleranceSeconds) return { ok: false, reason: "future_dated" };
  if (t.expires_at - t.issued_at > maxTokenTtlSeconds) return { ok: false, reason: "bad_ttl" };
  return { ok: true };
}
