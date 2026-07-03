-- دالة القبول الذرّية: قلب التسوية المالي.
--
-- تُستدعى مرة لكل توكن اجتاز التحقق التشفيري في دالة settle الطرفية
-- (التوقيع، التسلسل، الصلاحية، الاتصال). مسؤوليتها الحركة المالية
-- الحرجة في **معاملة واحدة**: إما أن تنجح كلها أو لا شيء.
--
-- ضمانات:
--   • idempotency: نفس token_id يعيد النتيجة المخزنة بلا أثر مزدوج.
--   • لا إنفاق مزدوج: القيد الفريد (sender_id, prev_hash) يُمسك التفرع
--     ذرياً حتى تحت التسابق؛ يُسجَّل في conflicts ويُجمَّد الحساب.
--   • لا خلق نقود: خصم من remaining الحجز + إضافة لرصيد المستلم في
--     نفس المعاملة (قيد مزدوج).
--   • السقف اليومي بيوم الإصدار.
--
-- تعيد نصاً: settled | duplicate | double_spend | insufficient_funds |
--            daily_cap | account_frozen | reservation_closed.

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

  -- 4) كشف الإنفاق المزدوج له الأولوية على السقف والرصيد: الاحتيال يجب أن
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

  -- 6) السقف اليومي بيوم الإصدار.
  select spent into v_day_spent
    from daily_spend where device_id = p_sender_id and spend_day = p_issued_day;
  v_day_spent := coalesce(v_day_spent, 0);
  if v_day_spent + p_amount > v_reservation.daily_cap then
    return 'daily_cap';
  end if;

  -- 6) الرصيد المحجوز المتبقي يكفي؟
  if p_amount > v_reservation.remaining then
    return 'insufficient_funds';
  end if;

  -- 7) تسجيل التوكن. القيد الفريد (sender_id, prev_hash) شبكة أمان ضد
  --    التسابق (فرعان متزامنان) لو تجاوز أحدهما فحص الخطوة 3.
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

  -- 7) الحركة المالية المزدوجة القيد (كلها في هذه المعاملة).
  update reservations set remaining = remaining - p_amount where id = v_reservation.id;

  insert into accounts (device_id, pubkey, balance)
    values (p_recipient_id, 'pending:' || p_recipient_id, p_amount)
    on conflict (device_id) do update set balance = accounts.balance + p_amount;

  insert into daily_spend (device_id, spend_day, spent)
    values (p_sender_id, p_issued_day, p_amount)
    on conflict (device_id, spend_day) do update set spent = daily_spend.spent + p_amount;

  return 'settled';
end;
$$;

-- ---------------------------------------------------------------------------
-- تجديد الحجز بعد التسوية: يغلق الحقبة الحالية ويفتح مرساة/حقبة جديدة
-- بالمتبقي + أي إيداع جديد. ذرّي حتى لا تبقى المحفظة بلا حجز مفتوح.
-- ---------------------------------------------------------------------------
create or replace function renew_reservation(
  p_device_id   text,
  p_new_anchor  text,
  p_top_up      bigint default 0
) returns reservations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old reservations%rowtype;
  v_new reservations%rowtype;
begin
  select * into v_old
    from reservations where device_id = p_device_id and status = 'open' for update;
  if not found then
    raise exception 'no open reservation for %', p_device_id;
  end if;
  update reservations set status = 'closed', closed_at = now() where id = v_old.id;

  insert into reservations (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
    values (p_device_id, v_old.epoch + 1, v_old.remaining + p_top_up,
            v_old.remaining + p_top_up, v_old.daily_cap, p_new_anchor)
    returning * into v_new;
  return v_new;
end;
$$;

-- ---------------------------------------------------------------------------
-- المطابقة: لكل حجز يجب أن يكون المحجوز = المسوّى منه + المتبقي.
-- (المنتهي لا يُخصم أصلاً فيبقى ضمن المتبقي.) صفر فروقات = دفتر سليم.
-- ---------------------------------------------------------------------------
create view reconciliation as
select
  r.id                                            as reservation_id,
  r.device_id,
  r.epoch,
  r.reserved,
  r.remaining,
  coalesce(sum(s.amount), 0)                       as settled_out,
  r.reserved - r.remaining - coalesce(sum(s.amount), 0) as discrepancy
from reservations r
left join settled_tokens s on s.reservation_id = r.id and s.sender_id = r.device_id
group by r.id;
