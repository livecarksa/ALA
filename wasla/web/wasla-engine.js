/*
 * محرك وصلة — منفذ JavaScript للمتصفح (Wasla engine — browser port)
 *
 * يطابق منطق token_engine + settlement في بايثون: توقيع Ed25519، سلسلة
 * توقيعات متتابعة، كشف الإنفاق المزدوج (داخل الدفعة وعبرها)، تجميد المحتال،
 * ودفتر مزدوج القيد. التشفير عبر Web Crypto API (Ed25519 + SHA-256) — بلا
 * أي تبعية خارجية، فيعمل كما هو على Netlify وفي Node للاختبار.
 *
 * Mirrors the Python token_engine + settlement core: Ed25519 signing, a
 * sequential signature chain, double-spend (fork) detection across batches,
 * fraud freeze, and a double-entry ledger. Pure Web Crypto, zero deps.
 */
(function (global) {
  "use strict";

  const subtle =
    global.crypto && global.crypto.subtle
      ? global.crypto.subtle
      : require("crypto").webcrypto.subtle;
  const getRandomUUID = () =>
    (global.crypto && global.crypto.randomUUID
      ? global.crypto
      : require("crypto").webcrypto
    ).randomUUID();

  const enc = new TextEncoder();
  const DAY = 86400;
  const MAX_TOKEN_TTL = 72 * 3600;
  const CLOCK_SKEW = 2 * 3600;
  const AGENT_CASH = "AGENT_CASH";

  const FATAL = new Set([
    "BAD_SIGNATURE", "KEY_MISMATCH", "BAD_SEQUENCE", "DAILY_CAP",
    "INSUFFICIENT_FUNDS", "FUTURE_DATED", "BAD_TTL",
  ]);

  // ---------- أدوات تشفير عامة ----------
  function toHex(buf) {
    return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  function fromHex(hex) {
    const a = new Uint8Array(hex.length / 2);
    for (let i = 0; i < a.length; i++) a[i] = parseInt(hex.substr(i * 2, 2), 16);
    return a;
  }
  async function sha256hex(bytes) {
    return toHex(await subtle.digest("SHA-256", bytes));
  }
  // تسلسل حتمي: مفاتيح مرتّبة بلا مسافات — التوقيع والتحقق يتفقان دائماً
  function canonicalJson(obj) {
    if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
    if (Array.isArray(obj)) return "[" + obj.map(canonicalJson).join(",") + "]";
    const keys = Object.keys(obj).sort();
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalJson(obj[k])).join(",") + "}";
  }
  function utcDay(ts) {
    return new Date(ts * 1000).toISOString().slice(0, 10);
  }

  // ---------- مفاتيح الجهاز ----------
  class DeviceKeys {
    constructor(priv, pub, pubHex, deviceId) {
      this.privateKey = priv;
      this.publicKey = pub;
      this.publicKeyHex = pubHex;
      this.deviceId = deviceId;
    }
    static async generate() {
      const kp = await subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
      const raw = new Uint8Array(await subtle.exportKey("raw", kp.publicKey));
      const pubHex = toHex(raw);
      const deviceId = (await sha256hex(raw)).slice(0, 16);
      return new DeviceKeys(kp.privateKey, kp.publicKey, pubHex, deviceId);
    }
    async sign(msgBytes) {
      return toHex(await subtle.sign({ name: "Ed25519" }, this.privateKey, msgBytes));
    }
  }

  async function verifySig(pubHex, sigHex, msgBytes) {
    const pk = await subtle.importKey("raw", fromHex(pubHex), { name: "Ed25519" }, true, ["verify"]);
    return subtle.verify({ name: "Ed25519" }, pk, fromHex(sigHex), msgBytes);
  }

  // ---------- التوكن الموقّع ----------
  function payloadOf(t) {
    return {
      token_id: t.token_id, sender_id: t.sender_id, sender_pubkey: t.sender_pubkey,
      recipient_id: t.recipient_id, amount: t.amount, currency: t.currency,
      seq: t.seq, prev_hash: t.prev_hash, issued_at: t.issued_at, expires_at: t.expires_at,
    };
  }
  async function createToken(keys, recipientId, amount, seq, prevHash, issuedAt, ttl, currency) {
    if (!Number.isInteger(amount) || amount <= 0) throw new Error("amount must be a positive integer");
    const p = {
      token_id: getRandomUUID().replace(/-/g, ""), sender_id: keys.deviceId,
      sender_pubkey: keys.publicKeyHex, recipient_id: recipientId, amount: amount,
      currency: currency || "SDG", seq: seq, prev_hash: prevHash,
      issued_at: issuedAt, expires_at: issuedAt + ttl,
    };
    const signature = await keys.sign(enc.encode(canonicalJson(p)));
    return Object.assign({ signature }, p);
  }
  async function tokenHash(t) {
    return sha256hex(enc.encode(canonicalJson(Object.assign(payloadOf(t), { signature: t.signature }))));
  }
  async function verifyToken(t, now) {
    if ((await sha256hex(fromHex(t.sender_pubkey))).slice(0, 16) !== t.sender_id)
      throw new Error("sender id does not match key");
    if (!Number.isInteger(t.amount) || t.amount <= 0) throw new Error("bad amount");
    if (!(await verifySig(t.sender_pubkey, t.signature, enc.encode(canonicalJson(payloadOf(t))))))
      throw new Error("bad signature");
    if (now != null && now > t.expires_at) throw new Error("expired");
  }

  // ---------- ترميز مضغوط للنقل بـ QR / compact QR transport codec ----------
  // 187 بايت ثابتة → ~250 حرف Base64، فيتسع في رمز QR صغير قابل للمسح بسهولة.
  const TX_PREFIX = "WSLTX:";
  const ID_PREFIX = "WSLID:";
  const WIRE_SIZE = 187;

  function bytesToB64(bytes) {
    let s = "";
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s);
  }
  function b64ToBytes(b64) {
    const s = atob(b64);
    const a = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return a;
  }
  function putHex(arr, offset, hex, nbytes) {
    const b = fromHex(hex);
    if (b.length !== nbytes) throw new Error("hex field wrong length");
    arr.set(b, offset);
    return offset + nbytes;
  }

  function encodeTokenQR(t) {
    const buf = new Uint8Array(WIRE_SIZE);
    const dv = new DataView(buf.buffer);
    let o = 0;
    buf.set(enc.encode("WSL"), o); o += 3;
    buf[o++] = 1; // version
    o = putHex(buf, o, t.token_id, 16);
    o = putHex(buf, o, t.sender_pubkey, 32);
    o = putHex(buf, o, t.recipient_id, 8);
    dv.setBigUint64(o, BigInt(t.amount)); o += 8;
    buf.set(enc.encode((t.currency + "   ").slice(0, 3)), o); o += 3;
    dv.setUint32(o, t.seq); o += 4;
    o = putHex(buf, o, t.prev_hash, 32);
    dv.setBigUint64(o, BigInt(t.issued_at)); o += 8;
    dv.setBigUint64(o, BigInt(t.expires_at)); o += 8;
    o = putHex(buf, o, t.signature, 64);
    return TX_PREFIX + bytesToB64(buf);
  }

  async function decodeTokenQR(payload) {
    payload = (payload || "").trim();
    if (!payload.startsWith(TX_PREFIX)) throw new Error("not a Wasla transfer QR");
    const buf = b64ToBytes(payload.slice(TX_PREFIX.length));
    if (buf.length !== WIRE_SIZE) throw new Error("bad transfer payload size");
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    const dec = new TextDecoder();
    if (dec.decode(buf.slice(0, 3)) !== "WSL" || buf[3] !== 1) throw new Error("unknown header");
    let o = 4;
    const hex = (n) => { const h = toHex(buf.slice(o, o + n)); o += n; return h; };
    const token_id = hex(16);
    const sender_pubkey = hex(32);
    const recipient_id = hex(8);
    const amount = Number(dv.getBigUint64(o)); o += 8;
    const currency = dec.decode(buf.slice(o, o + 3)).trim(); o += 3;
    const seq = dv.getUint32(o); o += 4;
    const prev_hash = hex(32);
    const issued_at = Number(dv.getBigUint64(o)); o += 8;
    const expires_at = Number(dv.getBigUint64(o)); o += 8;
    const signature = hex(64);
    const sender_id = (await sha256hex(fromHex(sender_pubkey))).slice(0, 16);
    return { token_id, sender_id, sender_pubkey, recipient_id, amount, currency, seq, prev_hash, issued_at, expires_at, signature };
  }

  function encodeIdQR(deviceId) { return ID_PREFIX + deviceId; }
  function decodeIdQR(payload) {
    payload = (payload || "").trim();
    if (!payload.startsWith(ID_PREFIX)) throw new Error("not a Wasla ID QR");
    const id = payload.slice(ID_PREFIX.length);
    if (!/^[0-9a-f]{16}$/.test(id)) throw new Error("bad device id");
    return id;
  }


  // ---------- المحفظة الأوف لاين ----------
  class OfflineWallet {
    constructor(keys, opts) {
      opts = opts || {};
      this.keys = keys;
      this.offlineBalance = opts.offlineBalance || 0;
      this.dailyCap = opts.dailyCap || 500000;
      this.tokenTtl = opts.tokenTtl || MAX_TOKEN_TTL;
      this.chainHead = opts.chainAnchor || "";
      this.nextSeq = 0;
      this.sent = [];
      this.received = [];
      this.spentByDay = {};
    }
    get deviceId() { return this.keys.deviceId; }
    spentToday(now) { return this.spentByDay[utcDay(now)] || 0; }
    async send(recipientId, amount, now) {
      const day = utcDay(now);
      if (amount > this.offlineBalance) throw new Error("INSUFFICIENT_OFFLINE");
      if ((this.spentByDay[day] || 0) + amount > this.dailyCap) throw new Error("DAILY_CAP");
      const token = await createToken(this.keys, recipientId, amount, this.nextSeq, this.chainHead, now, this.tokenTtl);
      this.chainHead = await tokenHash(token);
      this.nextSeq += 1;
      this.offlineBalance -= amount;
      this.spentByDay[day] = (this.spentByDay[day] || 0) + amount;
      this.sent.push(token);
      return token;
    }
    async receive(token, now) {
      await verifyToken(token, now);
      if (token.recipient_id !== this.deviceId) throw new Error("token addressed to another device");
      if (this.received.some((t) => t.token_id === token.token_id)) return;
      this.received.push(token);
    }
    tokensForSettlement() { return this.sent.concat(this.received); }
    applySettlement(newBalance, newAnchor) {
      this.offlineBalance = newBalance;
      this.chainHead = newAnchor;
      this.nextSeq = 0;
      this.sent = [];
      this.received = [];
    }
  }

  // ---------- محرك التسوية ----------
  class SettlementEngine {
    constructor() {
      this.balances = {};
      this.postings = [];
      this.accounts = {};
      this.settledTokenIds = new Set();
      this.spentByDay = {};   // "device|day" -> piasters
      this.spentPrev = {};    // "sender|prev_hash" -> token_id
    }
    _post(debit, credit, amount, ref, memo) {
      if (amount <= 0) throw new Error("non-positive posting");
      this.balances[debit] = (this.balances[debit] || 0) - amount;
      this.balances[credit] = (this.balances[credit] || 0) + amount;
      this.postings.push({ id: this.postings.length + 1, debit, credit, amount, ref, memo: memo || "" });
    }
    balance(id) { return this.balances[id] || 0; }
    trialBalance() { return Object.values(this.balances).reduce((a, b) => a + b, 0); }

    async registerDevice(pubkeyHex, dailyCap) {
      const deviceId = (await sha256hex(fromHex(pubkeyHex))).slice(0, 16);
      const anchor = await sha256hex(enc.encode("anchor:" + deviceId + ":" + Object.keys(this.accounts).length));
      const account = { deviceId, pubkey: pubkeyHex, dailyCap, chainAnchor: anchor, frozen: false };
      this.accounts[deviceId] = account;
      this.balances[deviceId] = this.balances[deviceId] || 0;
      return account;
    }
    cashIn(deviceId, amount, ref) {
      this._post(AGENT_CASH, deviceId, amount, ref || "agent-deposit", "إيداع وكيل / agent deposit");
    }

    async settleBatch(rawTokens, now) {
      const report = { settled: [], rejected: [], fraud_alerts: [], new_anchors: {}, malformed: [] };
      const tokens = [];
      const seen = new Set();
      for (const t of rawTokens) {
        if (!t || typeof t !== "object" || !t.token_id) { report.malformed.push(t); continue; }
        if (seen.has(t.token_id) || this.settledTokenIds.has(t.token_id)) {
          report.rejected.push([t, "DUPLICATE"]); continue;
        }
        seen.add(t.token_id);
        tokens.push(t);
      }
      const hashOf = new Map();
      for (const t of tokens) hashOf.set(t.token_id, await tokenHash(t));

      const bySender = new Map();
      for (const t of tokens) {
        if (!bySender.has(t.sender_id)) bySender.set(t.sender_id, []);
        bySender.get(t.sender_id).push(t);
      }
      for (const [sid, chain] of bySender) await this._settleSenderChain(sid, chain, now, report, hashOf);
      return report;
    }

    async _settleSenderChain(senderId, tokens, now, report, hashOf) {
      const account = this.accounts[senderId];
      if (!account) { tokens.forEach((t) => report.rejected.push([t, "UNREGISTERED_SENDER"])); return; }
      if (account.frozen) { tokens.forEach((t) => report.rejected.push([t, "ACCOUNT_FROZEN"])); return; }

      const byPrev = new Map();
      for (const t of tokens) {
        if (!byPrev.has(t.prev_hash)) byPrev.set(t.prev_hash, []);
        byPrev.get(t.prev_hash).push(t);
      }
      const rejectSubtree = (root, reason, processed) => {
        const stack = [root];
        while (stack.length) {
          const tok = stack.pop();
          if (processed.has(tok.token_id)) continue;
          processed.add(tok.token_id);
          report.rejected.push([tok, reason]);
          (byPrev.get(hashOf.get(tok.token_id)) || []).forEach((c) => stack.push(c));
        }
      };

      let head = account.chainAnchor;
      let lastSettledHead = account.chainAnchor;
      let expectedSeq = 0;
      let doubleSpend = false;
      const processed = new Set();

      while (byPrev.has(head)) {
        const candidates = byPrev.get(head).slice().sort(
          (a, b) => a.issued_at - b.issued_at || (a.token_id < b.token_id ? -1 : 1)
        );
        const canonical = candidates[0];
        if (candidates.length > 1) {
          doubleSpend = true;
          for (let i = 1; i < candidates.length; i++) rejectSubtree(candidates[i], "DOUBLE_SPEND", processed);
        }
        processed.add(canonical.token_id);
        const reason = await this._validate(canonical, account, expectedSeq, now);
        if (reason === null) {
          this._postSettlement(canonical);
          report.settled.push(canonical);
          lastSettledHead = hashOf.get(canonical.token_id);
          head = hashOf.get(canonical.token_id);
          expectedSeq = canonical.seq + 1;
        } else if (reason === "EXPIRED") {
          report.rejected.push([canonical, reason]);
          head = hashOf.get(canonical.token_id);
          expectedSeq = canonical.seq + 1;
        } else {
          report.rejected.push([canonical, reason]);
          (byPrev.get(hashOf.get(canonical.token_id)) || []).forEach((c) =>
            rejectSubtree(c, "SUPERSEDED", processed)
          );
          break;
        }
      }

      for (const t of tokens) {
        if (processed.has(t.token_id)) continue;
        const prior = this.spentPrev[senderId + "|" + t.prev_hash];
        if (prior != null && prior !== t.token_id) {
          doubleSpend = true;
          report.rejected.push([t, "DOUBLE_SPEND"]); // تفرع عبر دفعتين
        } else {
          report.rejected.push([t, "CHAIN_BROKEN"]);
        }
      }

      if (doubleSpend) { account.frozen = true; report.fraud_alerts.push(senderId); }
      if (lastSettledHead !== account.chainAnchor) {
        account.chainAnchor = await sha256hex(
          enc.encode("anchor:" + senderId + ":" + lastSettledHead + ":" + now)
        );
      }
      report.new_anchors[senderId] = account.chainAnchor;
    }

    async _validate(token, account, expectedSeq, now) {
      if (token.sender_pubkey !== account.pubkey) return "KEY_MISMATCH";
      try {
        await verifyToken(token, null);
      } catch (e) {
        return e.message === "expired" ? "EXPIRED" : "BAD_SIGNATURE";
      }
      if (now > token.expires_at) return "EXPIRED";
      if (token.issued_at > now + CLOCK_SKEW) return "FUTURE_DATED";
      if (token.expires_at - token.issued_at > MAX_TOKEN_TTL) return "BAD_TTL";
      if (token.seq !== expectedSeq) return "BAD_SEQUENCE";
      const dayKey = account.deviceId + "|" + utcDay(token.issued_at);
      if ((this.spentByDay[dayKey] || 0) + token.amount > account.dailyCap) return "DAILY_CAP";
      if (token.amount > this.balance(account.deviceId)) return "INSUFFICIENT_FUNDS";
      return null;
    }

    _postSettlement(token) {
      this._post(token.sender_id, token.recipient_id, token.amount, token.token_id,
        "تسوية توكن أوف لاين / offline token settlement");
      this.settledTokenIds.add(token.token_id);
      const dayKey = token.sender_id + "|" + utcDay(token.issued_at);
      this.spentByDay[dayKey] = (this.spentByDay[dayKey] || 0) + token.amount;
      this.spentPrev[token.sender_id + "|" + token.prev_hash] = token.token_id;
    }
  }

  const api = {
    DeviceKeys, OfflineWallet, SettlementEngine,
    createToken, verifyToken, tokenHash, canonicalJson, sha256hex,
    encodeTokenQR, decodeTokenQR, encodeIdQR, decodeIdQR,
    toHex, fromHex, TX_PREFIX, ID_PREFIX,
    AGENT_CASH, MAX_TOKEN_TTL, DAY,
  };
  global.WaslaEngine = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
