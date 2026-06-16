/* متحكّم الديمو التفاعلي — Interactive demo controller */
(function () {
  "use strict";
  const W = window.WaslaEngine;
  const I = window.WaslaI18n;
  const DAILY_CAP = 500000; // 5,000 جنيه
  const ORDER = ["mother", "grocer", "brother", "fraudster"];
  const EMOJI = { mother: "🧕", grocer: "🏪", brother: "📱", fraudster: "🦹" };

  const state = {
    lang: "ar",
    engine: null,
    wallets: {},        // metaKey -> OfflineWallet
    byId: {},           // deviceId -> metaKey
    now: 0,
    step: 0,
    networkUp: true,
    log: [],            // { key, params }
    lastToken: null,
  };

  const $ = (id) => document.getElementById(id);
  const t = (k, p) => I.t(state.lang, k, p);

  function fmtMoney(p) {
    return (p / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) +
      " " + t("currency");
  }
  function resolve(v) {
    if (v && typeof v === "object") {
      if ("dev" in v) return t("dev_" + v.dev);
      if ("money" in v) return fmtMoney(v.money);
      if ("ch" in v) return t("ch_" + v.ch);
      if ("reason" in v) return I.reason(state.lang, v.reason);
    }
    return String(v);
  }

  function logMsg(key, params) {
    state.log.push({ key, params: params || {} });
    renderLog();
  }

  // ---------- العرض / rendering ----------
  function renderStatic() {
    document.documentElement.lang = state.lang;
    document.documentElement.dir = I.strings[state.lang].dir;
    document.querySelectorAll("[data-i18n]").forEach((el) => {
      el.textContent = t(el.getAttribute("data-i18n"));
    });
    $("langBtn").textContent = t("switch_to");
    renderNet();
    renderDevices();
    renderLog();
    renderBank();
    renderToken();
  }

  function renderNet() {
    const el = $("netStatus");
    el.textContent = state.networkUp ? t("net_online") : t("net_offline");
    el.className = "net " + (state.networkUp ? "net-up" : "net-down");
  }

  function renderDevices() {
    const box = $("devices");
    box.innerHTML = "";
    for (const key of ORDER) {
      const w = state.wallets[key];
      const acct = w ? (state.engine && state.engine.accounts[w.deviceId]) : null;
      const offline = w ? w.offlineBalance : 0;
      const settled = w && state.engine ? state.engine.balance(w.deviceId) : 0;
      const spent = w ? Object.values(w.spentByDay).reduce((a, b) => a + b, 0) : 0;
      const frozen = acct && acct.frozen;
      const card = document.createElement("div");
      card.className = "card" + (frozen ? " frozen" : "") + (key === "fraudster" ? " fraud" : "");
      card.innerHTML =
        '<div class="card-head"><span class="emoji">' + EMOJI[key] + "</span>" +
        '<span class="card-name">' + t("dev_" + key) + "</span>" +
        (frozen ? '<span class="badge">' + t("badge_frozen") + "</span>" : "") + "</div>" +
        '<div class="card-id">' + (w ? w.deviceId : "—") + "</div>" +
        '<div class="row"><span>' + t("f_offline") + '</span><b>' + fmtMoney(offline) + "</b></div>" +
        '<div class="row"><span>' + t("f_settled") + '</span><b>' + fmtMoney(settled) + "</b></div>" +
        '<div class="row muted"><span>' + t("f_spent") + '</span><span>' + fmtMoney(spent) + "</span></div>";
      box.appendChild(card);
    }
  }

  function renderLog() {
    const box = $("log");
    box.innerHTML = "";
    for (const e of state.log) {
      const resolved = {};
      for (const k in e.params) resolved[k] = resolve(e.params[k]);
      const line = document.createElement("div");
      line.className = "log-line";
      line.textContent = I.t(state.lang, e.key, resolved);
      box.appendChild(line);
    }
    box.scrollTop = box.scrollHeight;
  }

  function renderBank() {
    const e = state.engine;
    const trial = e ? e.trialBalance() : 0;
    const settled = e ? e.settledTokenIds.size : 0;
    const postings = e ? e.postings.length : 0;
    const frozen = e ? Object.values(e.accounts).filter((a) => a.frozen).map((a) => a.deviceId) : [];
    const balanced = trial === 0;
    $("bank").innerHTML =
      (settled === 0 && postings <= 4
        ? '<div class="muted">' + t("bank_empty") + "</div>"
        : "") +
      '<div class="row"><span>' + t("bank_postings") + '</span><b>' + postings + "</b></div>" +
      '<div class="row"><span>' + t("bank_settled") + '</span><b>' + settled + "</b></div>" +
      '<div class="row trial ' + (balanced ? "ok" : "bad") + '"><span>' + t("bank_trial") +
        '</span><b>' + trial + " · " + t(balanced ? "bank_balanced" : "bank_unbalanced") + "</b></div>" +
      (frozen.length
        ? '<div class="row bad"><span>' + t("bank_frozen") + "</span><b>" + frozen.join(", ") + "</b></div>"
        : "");
  }

  function renderToken() {
    const box = $("tokenCard");
    if (!state.lastToken) { box.style.display = "none"; return; }
    const tk = state.lastToken;
    box.style.display = "block";
    box.innerHTML =
      '<div class="tok-head">' + t("show_token") + "</div>" +
      '<div class="tok-row"><span>token_id</span><code>' + tk.token_id.slice(0, 12) + "…</code></div>" +
      '<div class="tok-row"><span>' + t("tok_seq") + '</span><code>' + tk.seq + "</code></div>" +
      '<div class="tok-row"><span>' + t("tok_prev") + '</span><code>' + tk.prev_hash.slice(0, 16) + "…</code></div>" +
      '<div class="tok-row"><span>' + t("tok_sig") + '</span><code>' + tk.signature.slice(0, 24) + "…</code></div>";
  }

  // ---------- منطق الخطوات / steps ----------
  function setBusy(busy) {
    document.querySelectorAll("button.step").forEach((b) => (b.disabled = true));
    if (busy) return;
    const map = ["btnSetup", "btnDown", "btnQR", "btnSMS", "btnAttack", "btnSettle"];
    if (state.step >= 1 && state.step <= 6) $(map[state.step - 1]).disabled = false;
  }

  async function reset() {
    setBusy(true);
    state.engine = new W.SettlementEngine();
    state.wallets = {};
    state.byId = {};
    state.log = [];
    state.lastToken = null;
    state.networkUp = true;
    state.now = Math.floor(Date.now() / 1000);
    for (const key of ORDER) {
      const keys = await W.DeviceKeys.generate();
      state.wallets[key] = new W.OfflineWallet(keys, { dailyCap: DAILY_CAP });
      state.byId[keys.deviceId] = key;
    }
    state.step = 1;
    renderStatic();
    setBusy(false);
  }

  async function step1Setup() {
    const deposits = { mother: 150000, grocer: 0, brother: 0, fraudster: 50000 };
    for (const key of ORDER) {
      const w = state.wallets[key];
      const acct = await state.engine.registerDevice(w.keys.publicKeyHex, DAILY_CAP);
      const dep = deposits[key];
      if (dep) state.engine.cashIn(w.deviceId, dep, "deposit-" + key);
      w.applySettlement(dep, acct.chainAnchor);
      logMsg("m_registered", { name: { dev: key }, id: w.deviceId, amount: { money: dep } });
    }
    state.step = 2;
  }

  function step2Down() {
    state.networkUp = false;
    logMsg("m_down", {});
    state.step = 3;
  }

  async function step3QR() {
    const m = state.wallets.mother, g = state.wallets.grocer;
    const tok = await m.send(g.deviceId, 35000, state.now);
    await g.receive(tok, state.now);
    state.lastToken = tok;
    logMsg("m_transfer", { from: { dev: "mother" }, to: { dev: "grocer" }, amount: { money: 35000 }, ch: { ch: "qr" } });
    state.step = 4;
  }

  async function step4SMS() {
    const m = state.wallets.mother, b = state.wallets.brother;
    const tok = await m.send(b.deviceId, 20000, state.now + 60);
    await b.receive(tok, state.now + 60);
    logMsg("m_transfer", { from: { dev: "mother" }, to: { dev: "brother" }, amount: { money: 20000 }, ch: { ch: "sms" } });
    state.step = 5;
  }

  async function step5Attack() {
    const f = state.wallets.fraudster, g = state.wallets.grocer, b = state.wallets.brother;
    const branch1 = await f.send(g.deviceId, 40000, state.now);
    await g.receive(branch1, state.now);
    // فرع ثانٍ مصنوع يدوياً بنفس النقطة (تطبيق معدَّل) — يتجاوز المحفظة
    const branch2 = await W.createToken(f.keys, b.deviceId, 40000, branch1.seq, branch1.prev_hash, state.now + 1, W.MAX_TOKEN_TTL);
    await b.receive(branch2, state.now + 1);
    logMsg("m_attack", { name: { dev: "fraudster" }, amount: { money: 40000 } });
    state.step = 6;
  }

  async function step6Settle() {
    const now2 = state.now + 3600;
    let batch = [];
    for (const key of ORDER) batch = batch.concat(state.wallets[key].tokensForSettlement());
    const uploaded = new Set(batch.map((x) => x.token_id)).size;
    const report = await state.engine.settleBatch(batch, now2);
    state.networkUp = true;

    logMsg("m_back", { n: uploaded });
    const settledAmt = report.settled.reduce((a, x) => a + x.amount, 0);
    logMsg("m_settled", { n: report.settled.length, amount: { money: settledAmt } });
    for (const [tok, reason] of report.rejected) {
      if (reason === "DUPLICATE") continue;
      logMsg("m_rejected", { id: tok.token_id.slice(0, 8), reason: { reason: reason } });
    }
    for (const sid of report.fraud_alerts) {
      logMsg("m_frozen", { name: { dev: state.byId[sid] }, id: sid });
    }
    for (const key of ORDER) {
      const w = state.wallets[key];
      const anchor = report.new_anchors[w.deviceId] || (state.engine.accounts[w.deviceId] || {}).chainAnchor;
      w.applySettlement(state.engine.balance(w.deviceId), anchor);
    }
    const trial = state.engine.trialBalance();
    logMsg("m_recon", {
      p: state.engine.postings.length,
      s: state.engine.settledTokenIds.size,
      t: trial,
      state: t(trial === 0 ? "bank_balanced" : "bank_unbalanced"),
    });
    state.step = 7;
  }

  function wrap(fn) {
    return async () => {
      setBusy(true);
      try {
        await fn();
      } catch (e) {
        logMsg("m_rejected", { id: "—", reason: String(e.message || e) });
      }
      renderStatic();
      setBusy(false);
    };
  }

  function init() {
    $("btnSetup").onclick = wrap(step1Setup);
    $("btnDown").onclick = wrap(step2Down);
    $("btnQR").onclick = wrap(step3QR);
    $("btnSMS").onclick = wrap(step4SMS);
    $("btnAttack").onclick = wrap(step5Attack);
    $("btnSettle").onclick = wrap(step6Settle);
    $("btnReset").onclick = wrap(reset);
    $("langBtn").onclick = () => {
      state.lang = state.lang === "ar" ? "en" : "ar";
      renderStatic();
    };
    reset();
  }

  if (!(window.crypto && window.crypto.subtle &&
        window.crypto.subtle.generateKey)) {
    document.addEventListener("DOMContentLoaded", () => {
      document.body.innerHTML =
        '<div style="padding:2rem;font-family:sans-serif">هذا المتصفح لا يدعم Ed25519 في Web Crypto. ' +
        "جرّب Chrome/Edge/Safari حديثاً.<br>This browser lacks Ed25519 in Web Crypto — try a recent Chrome/Edge/Safari.</div>";
    });
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
