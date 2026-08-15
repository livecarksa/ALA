# وصلة — طبقة التسوية (Supabase)

التسوية داخل بنكك: كل حركة مال بين عميلَي بنك الخرطوم، بلا اعتماد على
المحوّل القومي. المبالغ بالقرش (`bigint`) — لا كسور عشرية في مسار المال.

## البنية

```
supabase/
├── migrations/
│   ├── 0001_schema.sql        # accounts, reservations, settled_tokens, conflicts, daily_spend + RLS
│   └── 0002_settle_accept.sql # الدوال الذرّية + عرض المطابقة
├── functions/
│   ├── _shared/wallet.ts      # لقطة المحفظة ومرساة الحقبة (مشترك)
│   ├── register/index.ts      # تسجيل جهاز: الهوية تُشتق من المفتاح، حجز حقبة 0
│   └── settle/
│       ├── index.ts           # تحقق تشفيري ثم settle_accept بالترتيب + تجديد وحالة محفظة
│       └── verify.ts          # Ed25519 + التسلسل القانوني (مطابق لـ wasla_core)
└── tests/
    ├── settle_accept_test.sql # 25 تأكيداً ضد Postgres حقيقي
    └── run.sh
```

## الضمانات (مُختبَرة ضد Postgres حقيقي)

- **ذرّية**: `settle_accept` يحرّك المال قيداً مزدوجاً في معاملة واحدة — تنجح كلها أو لا شيء.
- **idempotency**: نفس `token_id` يعيد النتيجة بلا أثر مزدوج (انقطاع أثناء الرفع آمن).
- **لا إنفاق مزدوج**: قيد فريد `(sender_id, prev_hash)` يمسك التفرع ذرياً حتى تحت التسابق؛ يُسجَّل في `conflicts` ويُجمَّد الحساب. للتفرع أولوية على السقف والرصيد.
- **اتصال السلسلة**: `prev_hash` يجب أن يكون مرساة الحقبة أو رأس توكن سابق — وإلا `chain_broken`.
- **المطابقة**: عرض `reconciliation` — لكل حجز: المحجوز = المسوّى + المتبقي. صفر فروقات = دفتر سليم.

## التشغيل

```bash
# اختبارات SQL (تتطلب Postgres 15+ مع pgcrypto لـ gen_random_uuid)
DATABASE_URL=postgres://... supabase/tests/run.sh

# الدالة الطرفية محلياً (تتطلب Supabase CLI + Deno)
supabase functions serve settle

# النشر لمشروع مخصص لوصلة (لا يُنشر لمشاريع live car — قاعدة الفصل)
supabase db push && supabase functions deploy register settle
```

## النشر الحي (PoC)

منشور على مشروع Supabase مخصص لوصلة `wasla-poc` (منفصل تماماً عن مشاريع
live car — قاعدة الفصل): الهجرات الثلاث مطبقة، والدالتان `register`
و`settle` نشطتان بتفعيل JWT (المفتاح العلني anon كافٍ للاستدعاء).

```bash
# بناء التطبيق موصولاً بالبوابة المنشورة (المفتاح علني بطبيعته):
flutter build apk --release \
  --dart-define=WASLA_SETTLE_URL=https://bvyjjvwahkhjhbzckfwx.supabase.co \
  --dart-define=WASLA_ANON_KEY=<المفتاح العلني anon من لوحة المشروع>
```

الخطة المجانية توقف المشروع تلقائياً بعد أسبوع خمول — يُستعاد من اللوحة
(أو `restore_project`) قبل أي ديمو. `service_role` يبقى في متغيرات بيئة
الدوال فقط، لا يلمس العميل أبداً.

## التحقق التكاملي بلا سحابة

`tests/local_gateway.py` بوابة محلية بعقد الدوال الطرفية نفسه فوق
Postgres المحلي — يثبت عقد عميل التطبيق ضد SQL الحقيقية قبل أي نشر
(انظر `app/README.md` §التحقق التكاملي).

## التوافق التشفيري

`functions/settle/verify.ts` يطابق حرفياً التسلسل القانوني والتوقيع في
`wasla_core` (Dart) وبرهان المفهوم (Python) — مثبت بالبذرة الحتمية
`packages/wasla_core/test/interop_fixture.json` (نفس التوقيع بالبايت عبر
WebCrypto). دالة settle لا تنشئ توكنات؛ تتحقق منها فقط ثم تُسوّيها ذرياً.

## سرّية

المحرك سرّ تجاري (القرار الحاكم). هذا المستودع خاص؛ لا `service_role` ولا
أي سرّ في الكود أو الـcommits — كلها في متغيرات بيئة Supabase.
