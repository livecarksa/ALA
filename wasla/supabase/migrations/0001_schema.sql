-- وصلة — مخطط التسوية داخل بنكك.
-- المبدأ: كل حركة مال داخل بنك الخرطوم (طرفا المعاملة عميلا بنكك)، لا
-- اعتماد على المحوّل القومي. المبالغ بالقرش (bigint) — لا كسور عشرية.
--
-- ثابت أمني محوري: لا يُسوّى توكنان يشيران لنفس نقطة السلسلة
-- (sender_id, prev_hash) أبداً — القيد الفريد أدناه يفرض ذلك ذرياً على
-- مستوى قاعدة البيانات، فيصبح كشف الإنفاق المزدوج مقاوماً للتسابق.

-- ---------------------------------------------------------------------------
-- الحسابات: عميل بنكك ومفتاحه العام ورصيده المسوّى على دفتر البنك.
-- ---------------------------------------------------------------------------
create table accounts (
  device_id   text primary key,                         -- 16 hex مشتق من المفتاح
  pubkey      text not null unique,                      -- 64 hex
  balance     bigint not null default 0 check (balance >= 0), -- الرصيد المسوّى بالقرش
  frozen      boolean not null default false,            -- مجمّد لإنفاق مزدوج مكشوف
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- الحجوزات: رصيد أُخرج من دفتر البنك ليُنفَق أوف لاين، بمرساة سلسلة وحقبة.
-- تسوية توكن صادر تُخصم من remaining. حجز واحد مفتوح لكل جهاز في كل حقبة.
-- ---------------------------------------------------------------------------
create table reservations (
  id           uuid primary key default gen_random_uuid(),
  device_id    text not null references accounts (device_id),
  epoch        integer not null,                         -- يرتفع مع كل تسوية/تجديد
  reserved     bigint not null check (reserved >= 0),    -- المحجوز الأصلي
  remaining    bigint not null check (remaining >= 0),   -- المتبقي القابل للإنفاق
  daily_cap    bigint not null check (daily_cap > 0),
  chain_anchor text not null,                            -- مرساة سلسلة هذه الحقبة
  status       text not null default 'open' check (status in ('open', 'closed')),
  opened_at    timestamptz not null default now(),
  closed_at    timestamptz,
  unique (device_id, epoch)
);

-- حجز مفتوح واحد فقط لكل جهاز في أي لحظة.
create unique index one_open_reservation_per_device
  on reservations (device_id) where (status = 'open');

-- ---------------------------------------------------------------------------
-- التوكنات المسوّاة: سجل نهائي لكل توكن قُبل. المفتاح الأساسي token_id
-- يمنح idempotency (إعادة الرفع لا تكرّر)، والقيد الفريد (sender_id,
-- prev_hash) يمنع الإنفاق المزدوج ذرياً — نقطة سلسلة تُستهلك مرة واحدة.
-- ---------------------------------------------------------------------------
create table settled_tokens (
  token_id       text primary key,                       -- 32 hex
  sender_id      text not null references accounts (device_id),
  recipient_id   text not null,                          -- قد يُفتح حسابه عند أول تسوية
  amount         bigint not null check (amount > 0),
  currency       text not null default 'SDG',
  seq            integer not null check (seq >= 0),
  prev_hash      text not null,
  token_hash     text not null,                          -- رأس السلسلة بعد هذا التوكن
  reservation_id uuid not null references reservations (id),
  settled_at     timestamptz not null default now(),
  constraint no_fork_per_chain_point unique (sender_id, prev_hash)
);

create index settled_tokens_sender_idx on settled_tokens (sender_id);
create index settled_tokens_reservation_idx on settled_tokens (reservation_id);

-- ---------------------------------------------------------------------------
-- التعارضات: كل محاولة إنفاق مزدوج مكشوفة تُسجَّل هنا للتدقيق والتجميد.
-- ---------------------------------------------------------------------------
create table conflicts (
  id                uuid primary key default gen_random_uuid(),
  sender_id         text not null,
  prev_hash         text not null,
  existing_token_id text not null,                       -- الفرع الأسبق المسوّى
  forked_token_id   text not null,                       -- الفرع المرفوض
  amount            bigint not null,
  detected_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- الإنفاق اليومي: عدّاد السقف بيوم الإصدار (يصمد عبر الدفعات).
-- ---------------------------------------------------------------------------
create table daily_spend (
  device_id text not null references accounts (device_id),
  spend_day date not null,
  spent     bigint not null default 0 check (spent >= 0),
  primary key (device_id, spend_day)
);

-- ---------------------------------------------------------------------------
-- أمان مستوى الصف (RLS): العميل يرى بياناته فقط؛ التسوية تجري بدور
-- الخدمة (service_role) الذي يتجاوز RLS. لا كتابة مباشرة من العميل على
-- جداول المال — كل تغيير يمرّ عبر دالة settle_accept ذات SECURITY DEFINER.
-- ---------------------------------------------------------------------------
alter table accounts       enable row level security;
alter table reservations   enable row level security;
alter table settled_tokens enable row level security;
alter table conflicts      enable row level security;
alter table daily_spend    enable row level security;

-- المعرّف يأتي من مطالبة JWT 'device_id' (يضبطها الوسيط عند المصادقة).
create policy account_self_read on accounts
  for select using (device_id = current_setting('request.device_id', true));

create policy reservation_self_read on reservations
  for select using (device_id = current_setting('request.device_id', true));

create policy settled_self_read on settled_tokens
  for select using (
    sender_id = current_setting('request.device_id', true)
    or recipient_id = current_setting('request.device_id', true));

-- لا سياسات كتابة للعملاء: الكتابة حصراً عبر service_role/SECURITY DEFINER.
