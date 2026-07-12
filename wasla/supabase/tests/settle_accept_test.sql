-- اختبارات دالة settle_accept ضد Postgres حقيقي — الحركة المالية الحرجة.
-- تُشغَّل على قاعدة نظيفة: كل قسم يبدأ بحالة معروفة ويتحقق بـ assert.

\set ON_ERROR_STOP on
set client_min_messages = notice;

-- مساعد التأكيد.
create or replace function assert_eq(actual anyelement, expected anyelement, label text)
returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAIL [%]: توقعت %، وجدت %', label, expected, actual;
  else
    raise notice 'ok: %', label;
  end if;
end; $$;

-- تهيئة نظيفة.
truncate settled_tokens, conflicts, daily_spend, reservations, accounts restart identity cascade;

-- حسابات وحجوزات.
insert into accounts (device_id, pubkey, balance) values
  ('sender0000000001', 'a0', 0),
  ('recip00000000001', 'r0', 0),
  ('recip00000000002', 'r0b', 0);
insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
  values ('sender0000000001', 0, 100000, 100000, 30000, 'anchor0');

-- ===========================================================================
do $$
declare r text;
begin
  -- 1) تسوية عادية تنجح وتحرّك المال قيداً مزدوجاً.
  r := settle_accept('tok1','sender0000000001','recip00000000001',
        20000,'SDG',0,'anchor0','hash1','2025-06-01');
  perform assert_eq(r, 'settled', 'تسوية عادية');
  perform assert_eq((select remaining from reservations where device_id='sender0000000001'),
        80000::bigint, 'خصم من المحجوز');
  perform assert_eq((select balance from accounts where device_id='recip00000000001'),
        20000::bigint, 'إضافة لرصيد المستلم');

  -- 2) idempotency: نفس التوكن لا يكرّر أثراً.
  r := settle_accept('tok1','sender0000000001','recip00000000001',
        20000,'SDG',0,'anchor0','hash1','2025-06-01');
  perform assert_eq(r, 'duplicate', 'إعادة الرفع مكررة');
  perform assert_eq((select remaining from reservations where device_id='sender0000000001'),
        80000::bigint, 'لا خصم مزدوج على التكرار');
  perform assert_eq((select balance from accounts where device_id='recip00000000001'),
        20000::bigint, 'لا إضافة مزدوجة على التكرار');

  -- 3) إنفاق مزدوج: توكن آخر بنفس (sender, prev_hash) يُكشف ويُجمّد الحساب.
  r := settle_accept('tok1fork','sender0000000001','recip00000000002',
        20000,'SDG',0,'anchor0','hash1b','2025-06-01');
  perform assert_eq(r, 'double_spend', 'كشف التفرع');
  perform assert_eq((select frozen from accounts where device_id='sender0000000001'),
        true, 'تجميد المحتال');
  perform assert_eq((select count(*)::int from conflicts), 1, 'تسجيل التعارض');
  perform assert_eq((select existing_token_id from conflicts), 'tok1', 'التعارض يشير للفرع الأسبق');
  perform assert_eq((select balance from accounts where device_id='recip00000000002'),
        0::bigint, 'مستلم الفرع المرفوض لا يُقيّد');

  -- 4) الحساب المجمّد يرفض أي تسوية لاحقة.
  r := settle_accept('tok2','sender0000000001','recip00000000001',
        1000,'SDG',1,'hash1','hash2','2025-06-01');
  perform assert_eq(r, 'account_frozen', 'رفض المجمّد');
end $$;

-- ===========================================================================
-- السقف اليومي والرصيد على حساب نظيف.
truncate settled_tokens, conflicts, daily_spend, reservations, accounts restart identity cascade;
insert into accounts (device_id, pubkey) values ('s2','k2'), ('rr','kr');
insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
  values ('s2', 0, 100000, 100000, 30000, 'a2');

do $$
declare r text;
begin
  r := settle_accept('a','s2','rr',20000,'SDG',0,'a2','h_a','2025-06-01');
  perform assert_eq(r, 'settled', 'أول تسوية تحت السقف');
  -- إصدار نفس اليوم يتجاوز السقف (20000 + 15000 > 30000).
  r := settle_accept('b','s2','rr',15000,'SDG',1,'h_a','h_b','2025-06-01');
  perform assert_eq(r, 'daily_cap', 'رفض تجاوز السقف اليومي');
  -- يوم مختلف: بذمّة يومه.
  r := settle_accept('b','s2','rr',15000,'SDG',1,'h_a','h_b','2025-06-02');
  perform assert_eq(r, 'settled', 'يوم جديد سقف جديد');
end $$;

-- رفض تجاوز المحجوز: سقف عالٍ حتى يبين حدّ الرصيد (لا يحجبه السقف).
insert into accounts (device_id, pubkey) values ('s3','k3');
insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
  values ('s3', 0, 5000, 5000, 500000, 'a3');
do $$
declare r text;
begin
  r := settle_accept('d','s3','rr',6000,'SDG',0,'a3','h_d','2025-06-03');
  perform assert_eq(r, 'insufficient_funds', 'رفض تجاوز المحجوز (سقف عالٍ)');
  perform assert_eq((select remaining from reservations where device_id='s3'),
        5000::bigint, 'الرفض لا يخصم شيئاً');
end $$;

-- الاتصال: توكن يشير لنقطة سلسلة مجهولة يُرفض chain_broken، والمتصل بالرأس يُقبل.
insert into accounts (device_id, pubkey) values ('s4','k4');
insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
  values ('s4', 0, 50000, 50000, 500000, 'a4');
do $$
declare r text;
begin
  r := settle_accept('x1','s4','rr',1000,'SDG',5,'ghost_prev','h_x1','2025-06-04');
  perform assert_eq(r, 'chain_broken', 'رفض نقطة سلسلة مجهولة');
  -- المتصل بالمرساة يُقبل ثم المتصل برأسه يُقبل.
  r := settle_accept('y1','s4','rr',1000,'SDG',0,'a4','h_y1','2025-06-04');
  perform assert_eq(r, 'settled', 'المتصل بالمرساة يُقبل');
  r := settle_accept('y2','s4','rr',1000,'SDG',1,'h_y1','h_y2','2025-06-04');
  perform assert_eq(r, 'settled', 'المتصل برأس السابق يُقبل');
end $$;

-- ===========================================================================
-- المستلم غير المسجّل يُرفض بلا أي أثر — بنكك فقط (هجرة 0003).
insert into accounts (device_id, pubkey) values ('s5','k5');
insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
  values ('s5', 0, 50000, 50000, 500000, 'a5');
do $$
declare r text;
begin
  r := settle_accept('z1','s5','ghost_recipient',1000,'SDG',0,'a5','h_z1','2025-06-05');
  perform assert_eq(r, 'unregistered_recipient', 'رفض مستلم غير مسجّل');
  perform assert_eq((select remaining from reservations where device_id='s5'),
        50000::bigint, 'رفض المستلم لا يخصم شيئاً');
  perform assert_eq((select count(*)::int from accounts where device_id='ghost_recipient'),
        0, 'لا يُفتح حساب معلّق');
  perform assert_eq((select count(*)::int from settled_tokens where token_id='z1'),
        0, 'لا تسجيل لتوكن مستلمه غير مسجّل');
  -- التوكن نفسه يُقبل بإعادة الرفع بعد تسجيل المستلم لدى البنك.
  insert into accounts (device_id, pubkey) values ('ghost_recipient','kg');
  r := settle_accept('z1','s5','ghost_recipient',1000,'SDG',0,'a5','h_z1','2025-06-05');
  perform assert_eq(r, 'settled', 'يُقبل بعد تسجيل المستلم');
  -- أولوية كشف الاحتيال: تفرع نحو مستلم غير مسجّل يُكشف ويجمّد لا يُحجب.
  r := settle_accept('z1fork','s5','ghost2',1000,'SDG',0,'a5','h_z1f','2025-06-05');
  perform assert_eq(r, 'double_spend', 'التفرع يُكشف حتى لمستلم غير مسجّل');
  perform assert_eq((select frozen from accounts where device_id='s5'),
        true, 'تجميد المحتال رغم مستلم غير مسجّل');
end $$;

-- ===========================================================================
-- تجديد الحجز والمطابقة صفر فروقات.
do $$
declare v_new reservations%rowtype; v_disc bigint;
begin
  v_new := renew_reservation('s2', 'a2_new', 0);
  perform assert_eq(v_new.epoch, 1, 'الحقبة ترتفع بالتجديد');
  perform assert_eq(v_new.remaining, 65000::bigint, 'المتبقي يُرحّل');
  perform assert_eq((select count(*)::int from reservations
      where device_id='s2' and status='open'), 1, 'حجز مفتوح واحد بعد التجديد');
  -- المطابقة: لا فرق في أي حجز على مستوى المنظومة كلها.
  select coalesce(sum(abs(discrepancy)),0) into v_disc from reconciliation;
  perform assert_eq(v_disc, 0::bigint, 'المطابقة: صفر فروقات (المحجوز = المسوّى + المتبقي)');
end $$;

-- ===========================================================================
-- قيد الحجز المفتوح الواحد يُفرض على مستوى القاعدة.
do $$
declare ok boolean := false;
begin
  begin
    insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
      values ('s2', 99, 1, 1, 1, 'x');  -- حجز مفتوح ثانٍ لنفس الجهاز
  exception when unique_violation then ok := true;
  end;
  perform assert_eq(ok, true, 'منع حجزين مفتوحين لنفس الجهاز');
end $$;

select 'ALL SQL TESTS PASSED' as result;
