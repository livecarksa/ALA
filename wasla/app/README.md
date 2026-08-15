# تطبيق وصلة (PoC بنمط بنكك)

واجهة عربية RTL فوق محرك `wasla_core` الحقيقي: حجز ← إرسال (QR/مقاطع
SMS، وماسح كاميرا) ← استقبال وتحقق أوف لاين ← سجل بمطابقة صفر فروقات ←
تسوية عند عودة الاتصال.

## التشغيل والبوابات

```bash
flutter pub get
flutter analyze --fatal-infos   # صفر ملاحظات
flutter test                    # دورة كاملة + دخان RTL
flutter run                     # جهاز حقيقي أو متصفح
```

## طبقة التسوية

افتراضياً **محاكاة محلية** (ديمو أوف لاين كامل بلا خادم). للربط بدوال
Supabase الطرفية الحقيقية (`register` + `settle`):

```bash
flutter build apk --release \
  --dart-define=WASLA_SETTLE_URL=https://<project>.supabase.co \
  --dart-define=WASLA_ANON_KEY=<anon-key>
```

لا أسرار في الكود — القيم من بيئة البناء حصراً.

## APK للتجربة الميدانية

شغّل workflow ‏`wasla-apk` من صفحة GitHub Actions (يدوياً بزر Run
workflow، أو تلقائياً مع كل تعديل للتطبيق) ونزّل `wasla-app-release-apk`
من Artifacts. ثبّته على جهازين، فعّل وضع الطيران، وأدِر سيناريو الديمو.

## التحقق التكاملي المحلي (عقد HTTP ضد SQL الحقيقية)

```bash
# Postgres محلي بهجرات وصلة ثم:
PGHOST=... PGPORT=... PGUSER=... PGDATABASE=... \
  python3 ../supabase/tests/local_gateway.py 8899 &
WASLA_E2E_URL=http://127.0.0.1:8899 flutter test test/settlement_e2e_test.dart
```

## قرارات بنيوية

- المفتاح الخاص في التخزين الآمن للنظام حصراً — لا يلمس حالة التطبيق.
- كل النصوص في `lib/l10n/*.arb` — لا نص صلب؛ أرقام غربية في المبالغ.
- خط IBM Plex Sans Arabic مضمّن (OFL) — الواجهة كاملة تعمل بلا إنترنت.
