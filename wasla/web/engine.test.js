/*
 * اختبار محرك الويب في Node (بلا متصفح) — يؤكد تطابق السلوك مع نواة بايثون:
 * تحويل ناجح، كشف التفرع داخل/عبر الدفعات، التجميد، وميزان مزدوج القيد = صفر.
 * Run: node wasla/web/engine.test.js
 */
const W = require("./wasla-engine.js");

let passed = 0, failed = 0;
function check(name, cond) {
  if (cond) { passed++; console.log("  ✓ " + name); }
  else { failed++; console.log("  ✗ " + name); }
}

async function fundedWallet(engine, balance, dailyCap) {
  const keys = await W.DeviceKeys.generate();
  const acct = await engine.registerDevice(keys.publicKeyHex, dailyCap || 500000);
  if (balance) engine.cashIn(keys.deviceId, balance, "dep");
  const w = new W.OfflineWallet(keys, { offlineBalance: balance, dailyCap: dailyCap || 500000, chainAnchor: acct.chainAnchor });
  return w;
}

(async () => {
  console.log("happy path — offline transfers settle, ledger balances");
  {
    const e = new W.SettlementEngine();
    const alice = await fundedWallet(e, 100000);
    const bob = await fundedWallet(e, 20000);
    const merchant = await fundedWallet(e, 0);
    const now = 1_700_000_000;
    const t1 = await alice.send(bob.deviceId, 30000, now);
    await bob.receive(t1, now);
    const t2 = await alice.send(merchant.deviceId, 10000, now + 60);
    await merchant.receive(t2, now + 60);
    const t3 = await bob.send(merchant.deviceId, 5000, now + 120);
    await merchant.receive(t3, now + 120);
    const batch = [].concat(alice.tokensForSettlement(), bob.tokensForSettlement(), merchant.tokensForSettlement());
    const r = await e.settleBatch(batch, now + 3600);
    check("3 tokens settled", r.settled.length === 3);
    check("no fraud", r.fraud_alerts.length === 0);
    check("alice = 60000", e.balance(alice.deviceId) === 60000);
    check("bob = 45000", e.balance(bob.deviceId) === 45000);
    check("merchant = 15000", e.balance(merchant.deviceId) === 15000);
    check("trial balance = 0", e.trialBalance() === 0);
  }

  console.log("fork within one batch — earliest settles, attacker frozen");
  {
    const e = new W.SettlementEngine();
    const attacker = await fundedWallet(e, 50000);
    const va = await fundedWallet(e, 0);
    const vb = await fundedWallet(e, 0);
    const now = 1_700_000_000;
    const legit = await attacker.send(va.deviceId, 30000, now);
    const forged = await W.createToken(attacker.keys, vb.deviceId, 30000, legit.seq, legit.prev_hash, now + 5, W.MAX_TOKEN_TTL);
    const r = await e.settleBatch([legit, forged], now + 100);
    check("one settled", r.settled.length === 1 && r.settled[0].token_id === legit.token_id);
    const ds = r.rejected.find((x) => x[1] === "DOUBLE_SPEND");
    check("forged rejected as DOUBLE_SPEND", !!ds && ds[0].token_id === forged.token_id);
    check("attacker frozen", e.accounts[attacker.deviceId].frozen === true);
    check("victim_b not credited", e.balance(vb.deviceId) === 0);
    check("trial balance = 0", e.trialBalance() === 0);
  }

  console.log("fork across separate batches — detected + frozen (the critical case)");
  {
    const e = new W.SettlementEngine();
    const attacker = await fundedWallet(e, 50000);
    const va = await fundedWallet(e, 0);
    const vb = await fundedWallet(e, 0);
    const now = 1_700_000_000;
    const legit = await attacker.send(va.deviceId, 30000, now);
    const forged = await W.createToken(attacker.keys, vb.deviceId, 30000, legit.seq, legit.prev_hash, now + 5, W.MAX_TOKEN_TTL);
    const r1 = await e.settleBatch([legit], now + 100);
    check("first branch settles, no freeze yet", r1.settled.length === 1 && r1.fraud_alerts.length === 0);
    const r2 = await e.settleBatch([forged], now + 200);
    check("second branch rejected DOUBLE_SPEND", r2.settled.length === 0 && r2.rejected[0][1] === "DOUBLE_SPEND");
    check("attacker now frozen", e.accounts[attacker.deviceId].frozen === true);
    check("victim_b not credited", e.balance(vb.deviceId) === 0);
  }

  console.log("replay — same token settles once");
  {
    const e = new W.SettlementEngine();
    const s = await fundedWallet(e, 50000);
    const r = await fundedWallet(e, 0);
    const now = 1_700_000_000;
    const tok = await s.send(r.deviceId, 20000, now);
    const rep = await e.settleBatch([tok, tok], now + 100);
    check("settled once", rep.settled.length === 1);
    check("duplicate rejected", rep.rejected.some((x) => x[1] === "DUPLICATE"));
    check("recipient = 20000 (not doubled)", e.balance(r.deviceId) === 20000);
  }

  console.log("tamper — inflated amount fails signature");
  {
    const e = new W.SettlementEngine();
    const s = await fundedWallet(e, 50000);
    const r = await fundedWallet(e, 0);
    const now = 1_700_000_000;
    const tok = await s.send(r.deviceId, 1000, now);
    const inflated = Object.assign({}, tok, { amount: 99000 });
    const rep = await e.settleBatch([inflated], now + 10);
    check("tampered rejected", rep.settled.length === 0 && rep.rejected[0][1] === "BAD_SIGNATURE");
    check("recipient not credited", e.balance(r.deviceId) === 0);
  }

  console.log("QR transport codec — round-trip + fork survives transport");
  {
    const GENESIS = "0".repeat(64);
    const sk = await W.DeviceKeys.generate();
    const wallet = new W.OfflineWallet(sk, { offlineBalance: 150000, dailyCap: 500000, chainAnchor: GENESIS });
    const r1 = (await W.DeviceKeys.generate()).deviceId;
    const r2 = (await W.DeviceKeys.generate()).deviceId;

    const legit = await wallet.send(r1, 35000, 1700000000);
    const qr = W.encodeTokenQR(legit);
    check("transfer QR is compact (<300 chars)", qr.startsWith("WSLTX:") && qr.length < 300);
    const back = await W.decodeTokenQR(qr);
    const cj = W.canonicalJson;
    const pay = (t) => ({ token_id: t.token_id, sender_id: t.sender_id, sender_pubkey: t.sender_pubkey, recipient_id: t.recipient_id, amount: t.amount, currency: t.currency, seq: t.seq, prev_hash: t.prev_hash, issued_at: t.issued_at, expires_at: t.expires_at, signature: t.signature });
    check("QR round-trip preserves every field", cj(pay(back)) === cj(pay(legit)));
    check("ID QR round-trip", W.decodeIdQR(W.encodeIdQR(r1)) === r1);

    // fork to a second recipient, both pushed through the codec, settled
    const forged = await W.createToken(sk, r2, 35000, legit.seq, legit.prev_hash, 1700000001, W.MAX_TOKEN_TTL);
    const t1 = await W.decodeTokenQR(W.encodeTokenQR(legit));
    const t2 = await W.decodeTokenQR(W.encodeTokenQR(forged));
    const e = new W.SettlementEngine();
    const acct = await e.registerDevice(sk.publicKeyHex, 100000000);
    acct.chainAnchor = GENESIS;
    e.cashIn(acct.deviceId, 100000000, "fund");
    const rep = await e.settleBatch([t1, t2], 1700003600);
    check("after QR transport: one settles", rep.settled.length === 1);
    check("after QR transport: fork caught", rep.rejected.some((x) => x[1] === "DOUBLE_SPEND"));
    check("after QR transport: sender frozen", e.accounts[acct.deviceId].frozen === true);
    check("after QR transport: ledger balances", e.trialBalance() === 0);
  }

  console.log("\n" + (failed === 0 ? "ALL PASSED" : failed + " FAILED") + " — " + passed + " checks");
  process.exit(failed === 0 ? 0 : 1);
})();
