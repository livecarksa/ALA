# wasla_core

محرك وصلة للتحويل الأوف لاين — Dart نقي بلا Flutter.

**سرّ تجاري.** هذا المستودع خاص؛ لا يُنشر المحرك ولا تُوثَّق خوارزمياته في أي
ملف يخرج من الفريق (القرار الحاكم في `wasla/CLAUDE.md`).

## الأوامر

```bash
dart pub get
dart analyze --fatal-infos     # صفر ملاحظات
dart test                      # 46 اختباراً — بوابات الخطة الإلزامية
dart test --coverage=coverage && \
  dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
# بوابة التغطية ≥ 90% إلزامية قبل أي دمج
```

## التوافق المتبادل

`test/interop_fixture.json` بذرة حتمية مولَّدة من نواة برهان المفهوم
(Python) عبر `tool/generate_interop_fixture.py` — تثبت أن التوقيع
والتسلسل القانوني والـhash متطابقة بايتاً-ببايت بين النواتين. تُجدَّد فقط
عند رفع إصدار بروتوكول التوكن مع حالة توافق خلفي.
