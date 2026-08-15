/* النصوص بثلاث لغات — Trilingual strings: العربية / English / Kiswahili */
(function (global) {
  "use strict";

  const STR = {
    ar: {
      _dir: "rtl", _name: "العربية",
      title: "وصلة", tagline: "المال يصل ولو سقطت الشبكة",
      subtitle: "ديمو حي على ثلاثة أجهزة بتوقيع Ed25519 حقيقي — التحويل بالكاميرا وQR بلا أي شبكة",
      pick_role: "اختر دور هذا الجهاز",
      role_hint: "افتح هذه الصفحة على ثلاثة أجهزة (أو ثلاث نوافذ) واختر دوراً مختلفاً في كلٍّ منها. الكاميرا تحتاج رابط https. ولو تعذّرت الكاميرا، استخدم زر «الصق الرمز».",
      role_sender: "المُرسِل", role_sender_d: "هاتف يُنشئ تحويلاً موقّعاً ويعرضه كرمز QR",
      role_receiver: "المُستلِم", role_receiver_d: "هاتف يمسح التحويل ويستلم المال بلا شبكة",
      role_settlement: "محطة التسوية", role_settlement_d: "يتحقق من السلاسل ويكشف الإنفاق المزدوج",
      change_role: "↺ تغيير الدور",
      net_offline: "وضع أوف لاين — لا إنترنت ولا GSM",

      f_balance: "الرصيد المتاح", f_amount: "المبلغ (جنيه)", f_recipient: "معرّف المستلم",
      scan_recipient: "📷 امسح معرّف المستلم", create_transfer: "توقيع التحويل وعرضه QR",
      attempt_fraud: "🦹 محاولة إنفاق مزدوج",
      fraud_hint: "يعيد توقيع نفس النقطة لمستلم آخر (يحاكي تطبيقاً معدَّلاً) — ستكشفه محطة التسوية.",
      tok_for: "تحويل إلى", tok_seq: "تسلسل", tok_sig: "توقيع",
      show_qr_hint: "اعرض هذا الرمز ليمسحه المستلم",

      my_id: "معرّفي — اطلب من المرسل مسحه", scan_transfer: "📷 امسح التحويل",
      received_list: "المستلَم (بانتظار التسوية)", show_for_settlement: "📲 اعرض للتسوية",
      verified_ok: "تحقّق التوقيع محلياً ✓ بلا أي شبكة — استُلم {amount} من {id}",
      recipient_mismatch: "هذا التحويل موجّه لجهاز آخر — رُفض",
      already_have: "هذا التحويل مستلَم سابقاً",

      scan_token: "📷 امسح توكناً", pending_count: "بانتظار التسوية: {n}",
      settle_now: "تسوية الدفعة", settled_h: "مُسوّى", rejected_h: "مرفوض", frozen_h: "حسابات مجمّدة",
      trial: "ميزان المراجعة", balanced: "متوازن ✓", unbalanced: "خلل ✗",
      recon: "{p} قيداً · {s} توكناً مسوّى · الميزان {t} ({state})",
      settled_row: "{from} ← {amount} → {to}",
      rejected_row: "{id}: {reason}",
      frozen_row: "{id} — جُمّد لإنفاق مزدوج ⚠",

      scan_title: "وجّه الكاميرا نحو الرمز", paste_instead: "أو الصق الرمز نصاً",
      paste_ph: "الصق رمز WSLTX: أو WSLID: هنا", use_paste: "استخدم الرمز", cancel: "إلغاء",
      copy: "نسخ الرمز", copied: "نُسخ ✓", close: "إغلاق",
      cam_fail: "تعذّر فتح الكاميرا — استخدم اللصق بدلاً منها.",
      bad_payload: "رمز غير صالح أو لا يخص وصلة.",
      need_recipient: "حدّد معرّف المستلم أولاً (امسحه أو الصقه).",
      empty_pending: "لا توكنات بعد — امسح من أجهزة المستلمين.",
      foot_crypto: "كل توقيع هنا Ed25519 حقيقي عبر Web Crypto، والكشف عن الإنفاق المزدوج يجري فعلياً في المتصفح.",
      foot_proto: "نموذج للعرض — لا يتصل ببنك فعلي.",
      currency: "جنيه",
    },

    en: {
      _dir: "ltr", _name: "English",
      title: "Wasla", tagline: "Money arrives even when the network is down",
      subtitle: "Live three-device demo with real Ed25519 signatures — transfers by camera + QR, no network at all",
      pick_role: "Choose this device's role",
      role_hint: "Open this page on three devices (or three tabs) and pick a different role on each. The camera needs an https link. If the camera fails, use the “Paste code” button.",
      role_sender: "Sender", role_sender_d: "A phone that signs a transfer and shows it as a QR",
      role_receiver: "Receiver", role_receiver_d: "A phone that scans the transfer and receives money with no network",
      role_settlement: "Settlement station", role_settlement_d: "Verifies the chains and catches double-spending",
      change_role: "↺ Change role",
      net_offline: "Offline mode — no internet, no GSM",

      f_balance: "Available balance", f_amount: "Amount (SDG)", f_recipient: "Recipient ID",
      scan_recipient: "📷 Scan recipient ID", create_transfer: "Sign transfer & show QR",
      attempt_fraud: "🦹 Attempt a double-spend",
      fraud_hint: "Re-signs the same point to another recipient (simulates a tampered app) — settlement will catch it.",
      tok_for: "transfer to", tok_seq: "seq", tok_sig: "signature",
      show_qr_hint: "Show this code for the receiver to scan",

      my_id: "My ID — ask the sender to scan it", scan_transfer: "📷 Scan a transfer",
      received_list: "Received (awaiting settlement)", show_for_settlement: "📲 Show for settlement",
      verified_ok: "Signature verified locally ✓ with no network — received {amount} from {id}",
      recipient_mismatch: "This transfer is addressed to another device — rejected",
      already_have: "This transfer was already received",

      scan_token: "📷 Scan a token", pending_count: "Awaiting settlement: {n}",
      settle_now: "Settle the batch", settled_h: "Settled", rejected_h: "Rejected", frozen_h: "Frozen accounts",
      trial: "Trial balance", balanced: "balanced ✓", unbalanced: "broken ✗",
      recon: "{p} postings · {s} settled · trial {t} ({state})",
      settled_row: "{from} ← {amount} → {to}",
      rejected_row: "{id}: {reason}",
      frozen_row: "{id} — frozen for double-spend ⚠",

      scan_title: "Point the camera at the code", paste_instead: "or paste the code as text",
      paste_ph: "Paste a WSLTX: or WSLID: code here", use_paste: "Use code", cancel: "Cancel",
      copy: "Copy code", copied: "Copied ✓", close: "Close",
      cam_fail: "Couldn't open the camera — use paste instead.",
      bad_payload: "Invalid code or not a Wasla code.",
      need_recipient: "Set the recipient ID first (scan or paste it).",
      empty_pending: "No tokens yet — scan from the receivers' devices.",
      foot_crypto: "Every signature here is real Ed25519 via Web Crypto, and double-spend detection runs live in the browser.",
      foot_proto: "Demo only — not connected to a real bank.",
      currency: "SDG",
    },

    sw: {
      _dir: "ltr", _name: "Kiswahili",
      title: "Wasla", tagline: "Pesa hufika hata mtandao ukizimika",
      subtitle: "Onyesho la moja kwa moja kwa vifaa vitatu, sahihi halisi za Ed25519 — miamala kwa kamera na QR, bila mtandao wowote",
      pick_role: "Chagua jukumu la kifaa hiki",
      role_hint: "Fungua ukurasa huu kwenye vifaa vitatu (au vichupo vitatu) na uchague jukumu tofauti kila kimoja. Kamera inahitaji kiungo cha https. Kamera ikishindikana, tumia kitufe cha “Bandika msimbo”.",
      role_sender: "Mtumaji", role_sender_d: "Simu inayotia saini muamala na kuuonyesha kama QR",
      role_receiver: "Mpokeaji", role_receiver_d: "Simu inayoskani muamala na kupokea pesa bila mtandao",
      role_settlement: "Kituo cha Usuluhishi", role_settlement_d: "Huthibitisha minyororo na kugundua matumizi maradufu",
      change_role: "↺ Badilisha jukumu",
      net_offline: "Hali ya nje ya mtandao — hakuna intaneti wala GSM",

      f_balance: "Salio lililopo", f_amount: "Kiasi (SDG)", f_recipient: "Kitambulisho cha mpokeaji",
      scan_recipient: "📷 Skani kitambulisho cha mpokeaji", create_transfer: "Tia saini muamala & onyesha QR",
      attempt_fraud: "🦹 Jaribu matumizi maradufu",
      fraud_hint: "Hutia saini sehemu ile ile kwa mpokeaji mwingine (huiga programu iliyobadilishwa) — usuluhishi utaligundua.",
      tok_for: "muamala kwa", tok_seq: "mfululizo", tok_sig: "saini",
      show_qr_hint: "Onyesha msimbo huu ili mpokeaji auskani",

      my_id: "Kitambulisho changu — mwambie mtumaji akiskani", scan_transfer: "📷 Skani muamala",
      received_list: "Zilizopokelewa (zinasubiri usuluhishi)", show_for_settlement: "📲 Onyesha kwa usuluhishi",
      verified_ok: "Saini imethibitishwa hapa ✓ bila mtandao — zimepokelewa {amount} kutoka {id}",
      recipient_mismatch: "Muamala huu ni wa kifaa kingine — umekataliwa",
      already_have: "Muamala huu ulipokelewa awali",

      scan_token: "📷 Skani tokeni", pending_count: "Zinasubiri usuluhishi: {n}",
      settle_now: "Suluhisha kundi", settled_h: "Zimesuluhishwa", rejected_h: "Zimekataliwa", frozen_h: "Akaunti zilizogandishwa",
      trial: "Mizani ya ukaguzi", balanced: "imelingana ✓", unbalanced: "hitilafu ✗",
      recon: "Vidokezo {p} · {s} zimesuluhishwa · mizani {t} ({state})",
      settled_row: "{from} ← {amount} → {to}",
      rejected_row: "{id}: {reason}",
      frozen_row: "{id} — imegandishwa kwa matumizi maradufu ⚠",

      scan_title: "Elekeza kamera kwenye msimbo", paste_instead: "au bandika msimbo kama maandishi",
      paste_ph: "Bandika msimbo wa WSLTX: au WSLID: hapa", use_paste: "Tumia msimbo", cancel: "Ghairi",
      copy: "Nakili msimbo", copied: "Imenakiliwa ✓", close: "Funga",
      cam_fail: "Imeshindwa kufungua kamera — tumia kubandika badala yake.",
      bad_payload: "Msimbo si sahihi au si wa Wasla.",
      need_recipient: "Weka kitambulisho cha mpokeaji kwanza (skani au bandika).",
      empty_pending: "Hakuna tokeni bado — skani kutoka vifaa vya wapokeaji.",
      foot_crypto: "Kila saini hapa ni Ed25519 halisi kupitia Web Crypto, na ugunduzi wa matumizi maradufu hufanyika moja kwa moja kwenye kivinjari.",
      foot_proto: "Onyesho tu — haijaunganishwa na benki halisi.",
      currency: "SDG",
    },
  };

  const REASONS = {
    ar: { DOUBLE_SPEND: "إنفاق مزدوج — تفرع في السلسلة", BAD_SIGNATURE: "توقيع غير صالح", EXPIRED: "انتهت الصلاحية", CHAIN_BROKEN: "سلسلة غير متصلة", BAD_SEQUENCE: "تسلسل غير متطابق", DAILY_CAP: "تجاوز السقف اليومي", INSUFFICIENT_FUNDS: "رصيد غير كافٍ", DUPLICATE: "مكرر", ACCOUNT_FROZEN: "حساب مجمّد", UNREGISTERED_SENDER: "مرسل غير مسجل", KEY_MISMATCH: "مفتاح غير مطابق", FUTURE_DATED: "طابع مستقبلي", BAD_TTL: "عمر غير مسموح", SUPERSEDED: "تابع لمرفوض" },
    en: { DOUBLE_SPEND: "double-spend — chain fork", BAD_SIGNATURE: "invalid signature", EXPIRED: "expired", CHAIN_BROKEN: "chain not connected", BAD_SEQUENCE: "sequence mismatch", DAILY_CAP: "daily cap exceeded", INSUFFICIENT_FUNDS: "insufficient funds", DUPLICATE: "duplicate", ACCOUNT_FROZEN: "account frozen", UNREGISTERED_SENDER: "unregistered sender", KEY_MISMATCH: "key mismatch", FUTURE_DATED: "future-dated", BAD_TTL: "bad lifetime", SUPERSEDED: "descendant of rejected" },
    sw: { DOUBLE_SPEND: "matumizi maradufu — mnyororo umegawanyika", BAD_SIGNATURE: "saini si sahihi", EXPIRED: "muda umeisha", CHAIN_BROKEN: "mnyororo haujaunganishwa", BAD_SEQUENCE: "mfululizo haulingani", DAILY_CAP: "kikomo cha kila siku kimezidi", INSUFFICIENT_FUNDS: "salio halitoshi", DUPLICATE: "nakala", ACCOUNT_FROZEN: "akaunti imegandishwa", UNREGISTERED_SENDER: "mtumaji hajasajiliwa", KEY_MISMATCH: "ufunguo haulingani", FUTURE_DATED: "tarehe ya baadaye", BAD_TTL: "muda batili", SUPERSEDED: "mtoto wa iliyokataliwa" },
  };

  global.WaslaI18n = {
    strings: STR,
    langs: ["ar", "en", "sw"],
    t(lang, key, params) {
      let s = (STR[lang] && STR[lang][key]);
      if (s == null) s = (STR.en && STR.en[key]) || key;
      if (params) for (const k in params) s = s.split("{" + k + "}").join(params[k]);
      return s;
    },
    reason(lang, code) {
      return (REASONS[lang] && REASONS[lang][code]) || (REASONS.en[code]) || code;
    },
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
