/* متحكّم الديمو متعدد الأجهزة — Multi-device demo controller */
(function () {
  "use strict";
  const W = window.WaslaEngine;
  const I = window.WaslaI18n;
  const QR = window.WaslaQR;

  const DEFAULT_BALANCE = 150000; // 1,500 جنيه
  const DEFAULT_CAP = 500000;
  const BIG_CAP = 100000000;
  const GENESIS = "0".repeat(64); // مرساة بدء مشتركة بطول hash (64 hex)
  const $ = (id) => document.getElementById(id);
  const now = () => Math.floor(Date.now() / 1000);

  const S = {
    lang: "ar",
    role: null,
    sender: null,     // { wallet, lastPoint }
    receiver: null,   // { keys, received: [] , showIdx }
    settlement: null, // { pending: Map }
    scanTarget: null,
    scanner: null,
  };

  const t = (k, p) => I.t(S.lang, k, p);
  function fmtMoney(p) {
    return (p / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " " + t("currency");
  }
  function shortId(id) { return (id || "").slice(0, 8); }
  function parseAmount(v) {
    const n = Math.round(parseFloat(String(v).replace(/[^\d.]/g, "")) * 100);
    if (!Number.isInteger(n) || n <= 0) throw new Error("bad amount");
    return n;
  }

  // ---------- اللغة والعرض الثابت ----------
  function applyStatic() {
    document.documentElement.lang = S.lang;
    document.documentElement.dir = I.strings[S.lang]._dir;
    document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.getAttribute("data-i18n")); });
    document.querySelectorAll("[data-ph]").forEach((el) => { el.placeholder = t(el.getAttribute("data-ph")); });
    document.querySelectorAll(".lang-opt").forEach((b) => {
      b.classList.toggle("active", b.dataset.lang === S.lang);
    });
  }

  function showRole(role) {
    S.role = role;
    $("roleSelect").style.display = role ? "none" : "block";
    for (const r of ["sender", "receiver", "settlement"])
      $("panel-" + r).style.display = role === r ? "block" : "none";
  }

  // ---------- المُرسِل ----------
  async function initSender() {
    const keys = await W.DeviceKeys.generate();
    S.sender = {
      wallet: new W.OfflineWallet(keys, { offlineBalance: DEFAULT_BALANCE, dailyCap: DEFAULT_CAP, chainAnchor: GENESIS }),
      lastPoint: null,
    };
    renderSender();
  }
  function renderSender() {
    $("senderBalance").textContent = fmtMoney(S.sender.wallet.offlineBalance);
    $("fraudBtn").disabled = !S.sender.lastPoint;
  }
  async function makeTransfer(fraud) {
    const recp = $("recpId").value.trim().toLowerCase();
    if (!/^[0-9a-f]{16}$/.test(recp)) { toast(t("need_recipient")); return; }
    let amount;
    try { amount = parseAmount($("amount").value); } catch (e) { toast(t("bad_payload")); return; }
    let tok;
    if (fraud) {
      const lp = S.sender.lastPoint;
      tok = await W.createToken(S.sender.wallet.keys, recp, amount, lp.seq, lp.prev_hash, now() + 1, W.MAX_TOKEN_TTL);
    } else {
      try {
        tok = await S.sender.wallet.send(recp, amount, now());
      } catch (e) { toast(t("bad_payload") + " (" + e.message + ")"); return; }
      S.sender.lastPoint = { seq: tok.seq, prev_hash: tok.prev_hash };
    }
    const payload = W.encodeTokenQR(tok);
    QR.renderQR($("senderQR"), payload);
    $("senderQRwrap").style.display = "block";
    $("senderTokInfo").innerHTML =
      "<b>" + t("tok_for") + "</b> " + shortId(tok.recipient_id) +
      " · <b>" + t("tok_seq") + "</b> " + tok.seq +
      " · <b>" + t("tok_sig") + "</b> <code>" + tok.signature.slice(0, 16) + "…</code>" +
      (fraud ? ' · <span class="warn">🦹</span>' : "");
    $("senderCopy").dataset.code = payload;
    renderSender();
  }

  // ---------- المُستلِم ----------
  async function initReceiver() {
    const keys = await W.DeviceKeys.generate();
    S.receiver = { keys, received: [], showIdx: 0 };
    QR.renderQR($("myIdQR"), W.encodeIdQR(keys.deviceId));
    $("myIdText").textContent = keys.deviceId;
    $("myIdCopy").dataset.code = keys.deviceId;
    renderReceiver();
  }
  function renderReceiver() {
    const list = $("receivedList");
    list.innerHTML = "";
    let total = 0;
    for (const tk of S.receiver.received) {
      total += tk.amount;
      const li = document.createElement("div");
      li.className = "rcv-row";
      li.textContent = fmtMoney(tk.amount) + " — " + shortId(tk.sender_id);
      list.appendChild(li);
    }
    $("receivedTotal").textContent = fmtMoney(total);
    $("showSettleBtn").disabled = S.receiver.received.length === 0;
  }
  async function onReceiveScan(text) {
    let tok;
    try { tok = await W.decodeTokenQR(text); } catch (e) { toast(t("bad_payload")); return; }
    try { await W.verifyToken(tok, now()); } catch (e) {
      toast(t("rejected_row", { id: shortId(tok.token_id), reason: I.reason(S.lang, "BAD_SIGNATURE") }));
      return;
    }
    if (tok.recipient_id !== S.receiver.keys.deviceId) { toast(t("recipient_mismatch")); return; }
    if (S.receiver.received.some((x) => x.token_id === tok.token_id)) { toast(t("already_have")); return; }
    S.receiver.received.push(tok);
    setStatus("receiverStatus", t("verified_ok", { amount: fmtMoney(tok.amount), id: shortId(tok.sender_id) }), "ok");
    renderReceiver();
  }
  function showForSettlement() {
    const arr = S.receiver.received;
    if (!arr.length) return;
    S.receiver.showIdx = S.receiver.showIdx % arr.length;
    const tk = arr[S.receiver.showIdx];
    QR.renderQR($("receiverShowQR"), W.encodeTokenQR(tk));
    $("receiverShowInfo").textContent = (S.receiver.showIdx + 1) + " / " + arr.length + " · " + fmtMoney(tk.amount);
    $("receiverShowWrap").style.display = "block";
  }

  // ---------- محطة التسوية ----------
  function initSettlement() {
    S.settlement = { pending: new Map() };
    renderSettlement();
  }
  function renderSettlement() {
    $("pendingCount").textContent = t("pending_count", { n: S.settlement.pending.size });
    $("settleBtn").disabled = S.settlement.pending.size === 0;
  }
  async function onTokenScan(text) {
    let tok;
    try { tok = await W.decodeTokenQR(text); } catch (e) { toast(t("bad_payload")); return; }
    S.settlement.pending.set(tok.token_id, tok);
    renderSettlement();
    toast(fmtMoney(tok.amount) + " · " + shortId(tok.sender_id));
  }
  async function runSettle() {
    const tokens = [...S.settlement.pending.values()];
    if (!tokens.length) { toast(t("empty_pending")); return; }
    const engine = new W.SettlementEngine();
    // تسجيل كل مرسل من توكناته وتمويله من مرساة بدء مشتركة "" (genesis)
    const seen = new Set();
    for (const tk of tokens) {
      if (seen.has(tk.sender_pubkey)) continue;
      seen.add(tk.sender_pubkey);
      const acct = await engine.registerDevice(tk.sender_pubkey, BIG_CAP);
      acct.chainAnchor = GENESIS;
      engine.cashIn(acct.deviceId, BIG_CAP, "fund-" + acct.deviceId);
    }
    const report = await engine.settleBatch(tokens, now());

    const fmtRows = (rows) => rows.join("") || '<div class="muted">—</div>';
    $("resSettled").innerHTML = fmtRows(report.settled.map((tk) =>
      '<div class="res ok">' + t("settled_row", { from: shortId(tk.sender_id), amount: fmtMoney(tk.amount), to: shortId(tk.recipient_id) }) + "</div>"));
    $("resRejected").innerHTML = fmtRows(report.rejected.filter((x) => x[1] !== "DUPLICATE").map(([tk, r]) =>
      '<div class="res bad">' + t("rejected_row", { id: shortId(tk.token_id), reason: I.reason(S.lang, r) }) + "</div>"));
    $("resFrozen").innerHTML = fmtRows(report.fraud_alerts.map((sid) =>
      '<div class="res bad">' + t("frozen_row", { id: shortId(sid) }) + "</div>"));
    const trial = engine.trialBalance();
    $("resRecon").innerHTML = '<div class="res ' + (trial === 0 ? "ok" : "bad") + '">' +
      t("recon", { p: engine.postings.length, s: engine.settledTokenIds.size, t: trial, state: t(trial === 0 ? "balanced" : "unbalanced") }) + "</div>";
    $("settleResults").style.display = "block";
  }

  // ---------- الماسح والمساعدات ----------
  function openScanner(target) {
    S.scanTarget = target;
    $("pasteBox").value = "";
    $("scanOverlay").style.display = "flex";
    S.scanner = new QR.Scanner($("scanVideo"), $("scanCanvas"));
    S.scanner.start(
      (text) => { closeScanner(); if (S.scanTarget) S.scanTarget(text); },
      () => { setStatus("scanHint", t("cam_fail"), "bad"); }
    );
  }
  function closeScanner() {
    if (S.scanner) { S.scanner.stop(); S.scanner = null; }
    $("scanOverlay").style.display = "none";
  }
  function usePaste() {
    const text = $("pasteBox").value.trim();
    if (!text) return;
    closeScanner();
    if (S.scanTarget) S.scanTarget(text);
  }

  let toastTimer = null;
  function toast(msg) {
    const el = $("toast");
    el.textContent = msg;
    el.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove("show"), 2600);
  }
  function setStatus(id, msg, cls) {
    const el = $(id);
    el.textContent = msg;
    el.className = "status " + (cls || "");
  }
  async function copyBtn(btn) {
    const code = btn.dataset.code || "";
    try { await navigator.clipboard.writeText(code); } catch (e) {
      const ta = document.createElement("textarea"); ta.value = code; document.body.appendChild(ta);
      ta.select(); try { document.execCommand("copy"); } catch (e2) {} ta.remove();
    }
    const old = btn.textContent; btn.textContent = t("copied");
    setTimeout(() => { btn.textContent = old; }, 1400);
  }

  // ---------- التهيئة ----------
  function init() {
    document.querySelectorAll(".lang-opt").forEach((b) => {
      b.onclick = () => { S.lang = b.dataset.lang; applyStatic(); rerenderDynamic(); };
    });
    $("pickSender").onclick = async () => { showRole("sender"); await initSender(); };
    $("pickReceiver").onclick = async () => { showRole("receiver"); await initReceiver(); };
    $("pickSettlement").onclick = () => { showRole("settlement"); initSettlement(); };
    document.querySelectorAll(".change-role").forEach((b) => (b.onclick = () => showRole(null)));

    $("recpScan").onclick = () => openScanner((txt) => {
      try { $("recpId").value = W.decodeIdQR(txt); } catch (e) {
        if (/^[0-9a-f]{16}$/i.test(txt.trim())) $("recpId").value = txt.trim().toLowerCase();
        else toast(t("bad_payload"));
      }
    });
    $("makeBtn").onclick = () => makeTransfer(false);
    $("fraudBtn").onclick = () => makeTransfer(true);
    $("senderCopy").onclick = () => copyBtn($("senderCopy"));

    $("myIdCopy").onclick = () => copyBtn($("myIdCopy"));
    $("scanTransferBtn").onclick = () => openScanner(onReceiveScan);
    $("showSettleBtn").onclick = () => { S.receiver.showIdx = 0; showForSettlement(); };
    $("receiverNext").onclick = () => { S.receiver.showIdx++; showForSettlement(); };

    $("scanTokenBtn").onclick = () => openScanner(onTokenScan);
    $("settleBtn").onclick = runSettle;

    $("scanCancel").onclick = closeScanner;
    $("pasteUse").onclick = usePaste;

    applyStatic();
    showRole(null);
  }

  function rerenderDynamic() {
    if (S.role === "sender" && S.sender) renderSender();
    if (S.role === "receiver" && S.receiver) renderReceiver();
    if (S.role === "settlement" && S.settlement) renderSettlement();
  }

  if (!(window.crypto && window.crypto.subtle && window.crypto.subtle.generateKey)) {
    document.addEventListener("DOMContentLoaded", () => {
      document.body.innerHTML = '<div style="padding:2rem;font-family:sans-serif;color:#fff;background:#0d1b2a">' +
        "هذا المتصفح لا يدعم Ed25519 في Web Crypto — جرّب Chrome/Edge أو Safari حديثاً.<br>" +
        "This browser lacks Ed25519 in Web Crypto — try a recent Chrome/Edge or Safari.</div>";
    });
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
