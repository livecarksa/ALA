-- 0003: تشديد سياسة المستلم — عميل بنكك مسجّل فقط.
--
-- القرار الحاكم «التسوية داخل البنك: من محفظة عميل بنكك إلى محفظة عميل
-- بنكك» كان مطبَّقاً على المرسل وحده، بينما المستلم غير الموجود كان
-- يُفتح له حساب معلّق تلقائياً (إرث نسخة سابقة). من هذه الهجرة: لا حركة
-- مالية إلى حساب غير موجود — تعيد الدالة unregistered_recipient بلا أي
-- أثر، والتوكن نفسه يبقى صالحاً لإعادة الرفع بعد تسجيل المستلم لدى البنك
-- (ما لم تنته صلاحيته).
--
-- ترتيب مقصود لكشف الاحتيال: فحص المستلم يأتي **بعد** كشف التفرع —
-- توكن متفرع لمستلم غير مسجّل يجب أن يُسجَّل في conflicts ويجمّد
-- المحتال، لا أن يُحجب خلف رفض أخف.

-- سلامة مرجعية على مستوى القاعدة: المستلم المسجَّل شرط للتسجيل النهائي.
comment on column settled_tokens.recipient_id is
  'عميل بنكك مسجّل مسبقاً — لا يُفتح حساب عند التسوية (منذ 0003)';
alter table settled_tokens
  add constraint settled_tokens_recipient_fk
  foreign key (recipient_id) references accounts (device_id);

-- تعيد نصاً: settled | duplicate | double_spend | insufficient_funds |
--            daily_cap | account_frozen | reservation_closed |
--            chain_broken | unregistered_recipient.
create or replace function settle_accept(
  p_token_id     text,
  p_sender_id    text,
  p_recipient_id text,
  p_amount       bigint,
  p_currency     text,
  p_seq          integer,
  p_prev_hash    text,
  p_token_hash   text,
  p_issued_day   date
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reservation reservations%rowtype;
  v_existing    settled_tokens%rowtype;
  v_frozen      boolean;
  v_day_spent   bigint;
begin
  -- 1) idempotency: التوكن مسوّى سابقاً؟ أعِد النتيجة بلا أي تغيير.
  select * into v_existing from settled_tokens where token_id = p_token_id;
  if found then
    return 'duplicate';
  end if;

  -- 2) قفل حساب المرسل لتسلسل الحركة (يمنع سباق دفعتين متزامنتين).
  select frozen into v_frozen from accounts where device_id = p_sender_id for update;
  if not found then
    raise exception 'unregistered sender %', p_sender_id;
  end if;
  if v_frozen then
    return 'account_frozen';
  end if;

  -- 3) الحجز المفتوح للمرسل.
  select * into v_reservation
    from reservations
   where device_id = p_sender_id and status = 'open'
   for update;
  if not found then
    return 'reservation_closed';
  end if;

  -- 4) كشف الإنفاق المزدوج له الأولوية على كل رفض أخف: الاحتيال يجب أن
  --    يُكشف ويُجمَّد مهما كانت باقي الفحوص. نقطة سلسلة استُهلكت بتوكن آخر = تفرع.
  select * into v_existing
    from settled_tokens where sender_id = p_sender_id and prev_hash = p_prev_hash;
  if found and v_existing.token_id <> p_token_id then
    insert into conflicts (sender_id, prev_hash, existing_token_id, forked_token_id, amount)
      values (p_sender_id, p_prev_hash, v_existing.token_id, p_token_id, p_amount);
    update accounts set frozen = true where device_id = p_sender_id;
    return 'double_spend';
  end if;

  -- 5) الاتصال: prev يجب أن يكون مرساة الحقبة أو رأس توكن سابق لنفس المرسل.
  --    توكن يشير لنقطة مجهولة سلسلة مبتورة (يُرفع بالترتيب من المحرك الطرفي).
  if p_prev_hash <> v_reservation.chain_anchor
     and not exists (
       select 1 from settled_tokens
        where sender_id = p_sender_id and token_hash = p_prev_hash) then
    return 'chain_broken';
  end if;

  -- 6) المستلم عميل بنكك مسجّل؟ لا فتح حسابات معلّقة عند التسوية —
  --    بلا قفل صف هنا: القيد يُحسم عند حركة الرصيد في الخطوة 9.
  if not exists (select 1 from accounts where device_id = p_recipient_id) then
    return 'unregistered_recipient';
  end if;

  -- 7) السقف اليومي بيوم الإصدار.
  select spent into v_day_spent
    from daily_spend where device_id = p_sender_id and spend_day = p_issued_day;
  v_day_spent := coalesce(v_day_spent, 0);
  if v_day_spent + p_amount > v_reservation.daily_cap then
    return 'daily_cap';
  end if;

  -- 8) الرصيد المحجوز المتبقي يكفي؟
  if p_amount > v_reservation.remaining then
    return 'insufficient_funds';
  end if;

  -- 9) تسجيل التوكن. القيد الفريد (sender_id, prev_hash) شبكة أمان ضد
  --    التسابق (فرعان متزامنان) لو تجاوز أحدهما فحص الخطوة 4.
  begin
    insert into settled_tokens (
      token_id, sender_id, recipient_id, amount, currency,
      seq, prev_hash, token_hash, reservation_id)
    values (
      p_token_id, p_sender_id, p_recipient_id, p_amount, p_currency,
      p_seq, p_prev_hash, p_token_hash, v_reservation.id);
  exception
    when unique_violation then
      select * into v_existing
        from settled_tokens where sender_id = p_sender_id and prev_hash = p_prev_hash;
      insert into conflicts (sender_id, prev_hash, existing_token_id, forked_token_id, amount)
        values (p_sender_id, p_prev_hash, v_existing.token_id, p_token_id, p_amount);
      update accounts set frozen = true where device_id = p_sender_id;
      return 'double_spend';
  end;

  -- 10) الحركة المالية المزدوجة القيد (كلها في هذه المعاملة).
  update reservations set remaining = remaining - p_amount where id = v_reservation.id;

  update accounts set balance = balance + p_amount where device_id = p_recipient_id;
  if not found then
    -- لا مسار حذف للحسابات؛ لو حدث فالمعاملة كلها تنقلب — لا مال يضيع.
    raise exception 'recipient % vanished mid-transaction', p_recipient_id;
  end if;

  insert into daily_spend (device_id, spend_day, spent)
    values (p_sender_id, p_issued_day, p_amount)
    on conflict (device_id, spend_day) do update set spent = daily_spend.spent + p_amount;

  return 'settled';
end;
$$;
