# ديمو وصلة التفاعلي · Wasla Interactive Demo

ديمو ويب ثابت ثنائي اللغة (عربي/إنجليزي) يشغّل **منطق وصلة الفعلي في المتصفح**:
توقيع Ed25519 حقيقي عبر Web Crypto، سلسلة توقيعات متتابعة، وكشف الإنفاق
المزدوج عند التسوية مع دفتر مزدوج القيد. لا خادم ولا تبعيات ولا خطوة بناء.

A bilingual (Arabic/English) static web demo that runs **Wasla's real logic in
the browser**: genuine Ed25519 signing via Web Crypto, a sequential signature
chain, and double-spend detection at settlement with a double-entry ledger.
No backend, no dependencies, no build step.

## المحتوى · Files

| الملف · File | الدور · Role |
|---|---|
| `index.html` | الصفحة · page structure |
| `styles.css` | التصميم (RTL/LTR) · styling |
| `wasla-engine.js` | منفذ المحرك بـ Web Crypto · engine port (Ed25519 + SHA-256) |
| `i18n.js` | النصوص بلغتين · bilingual strings |
| `app.js` | متحكّم الديمو · demo controller |
| `engine.test.js` | اختبار المحرك في Node · headless engine test |
| `netlify.toml` | إعداد النشر · deploy config |

## النشر على Netlify · Deploy to Netlify

**سحب وإفلات · Drag & drop:** اسحب مجلد `wasla/web` إلى
[app.netlify.com/drop](https://app.netlify.com/drop). انتهى.

**عبر Git:** اربط المستودع واضبط:
- Base/Publish directory: `wasla/web`
- Build command: *(اتركه فارغاً · leave empty)*

**محلياً · Locally:**
```bash
cd wasla/web
python3 -m http.server 8000   # ثم افتح · then open http://localhost:8000
```

## التحقق · Verify

```bash
node wasla/web/engine.test.js   # 20 فحصاً لمنطق المحرك · 20 engine checks
```

## ملاحظة · Note

> كل توقيع هنا Ed25519 حقيقي، والكشف عن الإنفاق المزدوج يجري فعلياً في المتصفح.
> النموذج للعرض فقط ولا يتصل ببنك فعلي. يتطلب متصفحاً يدعم Ed25519 في Web
> Crypto (Chrome/Edge 137+، Safari 17+، Firefox 130+).
>
> Every signature is real Ed25519 and double-spend detection runs live in the
> browser. Demo only — not connected to a real bank. Requires a browser with
> Ed25519 in Web Crypto (Chrome/Edge 137+, Safari 17+, Firefox 130+).
