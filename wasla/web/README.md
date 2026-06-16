# ديمو وصلة متعدد الأجهزة · Wasla Multi-Device Demo

ديمو ويب ثابت **ثلاثي اللغة** (العربية / English / Kiswahili) يشغّل منطق وصلة
الفعلي في المتصفح: توقيع **Ed25519 حقيقي** عبر Web Crypto، نقل **جهازاً لجهاز
بالكاميرا وQR** بلا أي شبكة، وكشف الإنفاق المزدوج عند التسوية. بلا خادم وبلا خطوة بناء.

A trilingual (Arabic / English / Swahili) static web demo running Wasla's real
logic in the browser: genuine **Ed25519** signing via Web Crypto, **device-to-device
transport by camera + QR** with no network, and double-spend detection at
settlement. No backend, no build step.

## الأدوار الثلاثة · The three roles

افتح الصفحة على ثلاثة أجهزة (أو ثلاث نوافذ) واختر دوراً في كلٍّ:
Open the page on three devices (or tabs) and pick a role on each:

1. **المُرسِل · Sender** — يوقّع تحويلاً ويعرضه كرمز QR. زر «محاولة إنفاق مزدوج» يصنع تفرّعاً عمداً.
2. **المُستلِم · Receiver** — يعرض معرّفه QR، يمسح التحويل بالكاميرا، ويتحقق من التوقيع محلياً بلا شبكة.
3. **محطة التسوية · Settlement** — يمسح التوكنات، يكشف التفرّع (الإنفاق المزدوج)، يجمّد المحتال، ويُظهر ميزان دفتر = صفر.

> لكل عملية مسح **مسار بديل بالنسخ واللصق** (زر «الصق الرمز») فيعمل الديمو حتى لو تعذّرت الكاميرا.
> Every scan has a **copy/paste fallback**, so the demo works even if the camera fails.

## الملفات · Files

| الملف · File | الدور · Role |
|---|---|
| `index.html`, `styles.css` | الواجهة (RTL/LTR) · UI |
| `wasla-engine.js` | المحرك + ترميز QR المضغوط · engine + compact QR codec (Ed25519, SHA-256) |
| `i18n.js` | النصوص بثلاث لغات · trilingual strings |
| `qr-ui.js` | رسم QR + ماسح الكاميرا · QR render + camera scanner |
| `app.js` | منطق الأدوار · role logic |
| `vendor/` | qrcode-generator (MIT) + jsQR (Apache-2.0) — محليّان بلا CDN |
| `engine.test.js` | 27 فحصاً في Node · headless checks |

## النشر · Deploy

**ربط المستودع (مستحسن) · Repo link (recommended):**
في Netlify: *Add new site → Import from Git* → اختر المستودع. الإعداد جاهز في
`netlify.toml` بجذر المستودع (`publish = "wasla/web"`)، فكل دفعة Git تُنشَر تلقائياً.
Netlify reads the root `netlify.toml` (`publish = "wasla/web"`); every push auto-deploys.

**سحب وإفلات · Drag & drop:** اسحب مجلد `wasla/web` إلى
[app.netlify.com/drop](https://app.netlify.com/drop).

**محلياً · Locally:**
```bash
cd wasla/web && python3 -m http.server 8000   # http://localhost:8000
```
> الكاميرا تتطلب **https** (أو localhost). Netlify يوفّر https تلقائياً.
> The camera requires **https** (or localhost). Netlify provides https automatically.

## التحقق · Verify
```bash
node wasla/web/engine.test.js   # 27 فحصاً · checks (Ed25519 + codec + fork detection)
```

> نموذج للعرض فقط، لا يتصل ببنك فعلي. يتطلب متصفحاً يدعم Ed25519 في Web Crypto
> (Chrome/Edge 137+، Safari 17+، Firefox 130+). مسح QR يستخدم BarcodeDetector
> الأصلي أو jsQR بديلاً.
