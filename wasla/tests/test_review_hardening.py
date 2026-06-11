"""تثبيت إصلاحات مجلس الخبراء — كل اختبار يحرس ثغرة وُجدت في المراجعة.

المراجع: مجلس الأمن/التشفير، الدفع/التسوية، وجودة الكود.
"""

import pytest

from settlement.engine import (
    CLOCK_SKEW_TOLERANCE,
    MAX_TOKEN_TTL,
    RejectReason,
    SettlementEngine,
)
from token_engine.token import SignedToken, TokenError

from .helpers import NOW, make_user

DAY = 24 * 3600


def craft(wallet, recipient_id, amount, seq, prev_hash, issued_at, ttl=MAX_TOKEN_TTL):
    """توكن مصنوع يدوياً بمفاتيح المرسل — يحاكي تطبيقاً معدَّلاً (المهاجم)."""
    return SignedToken.create(
        keys=wallet.keys, recipient_id=recipient_id, amount=amount,
        seq=seq, prev_hash=prev_hash, issued_at=issued_at, ttl_seconds=ttl,
    )


class TestFutureDatingCapAttack:
    """أمن#2: تقسيم السقف بطابع إصدار يختاره المهاجم في المستقبل."""

    def test_future_dated_token_rejected(self):
        engine = SettlementEngine()
        attacker = make_user(engine, balance=100_000, daily_cap=30_000)
        victim = make_user(engine, balance=0)

        future = craft(attacker, victim.device_id, 30_000, 0,
                       attacker.chain_head, NOW + CLOCK_SKEW_TOLERANCE + 3600)
        report = engine.settle_batch([future.to_dict()], now=NOW)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.FUTURE_DATED

    def test_engine_enforces_own_ttl_not_client_value(self):
        """أمن#5: عمر التوكن يفرضه المحرك لا قيمة العميل."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=100_000)
        victim = make_user(engine, balance=0)

        long_lived = craft(attacker, victim.device_id, 10_000, 0,
                           attacker.chain_head, NOW, ttl=MAX_TOKEN_TTL + DAY)
        report = engine.settle_batch([long_lived.to_dict()], now=NOW + 100)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.BAD_TTL


class TestAnchorGriefing:
    """أمن#3: رفع توكن لا يُسوّى يجب ألا يدوّر مرساة الضحية."""

    def test_unsettled_junk_does_not_rotate_anchor(self):
        engine = SettlementEngine()
        victim = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)
        anchor0 = engine.accounts[victim.device_id].chain_anchor

        # توكن لا يتصل بالمرساة (prev مفبرك) ولا يُسوّي شيئاً
        junk = craft(victim, recipient.device_id, 1_000, 7, "ff" * 32, NOW)
        report1 = engine.settle_batch([junk.to_dict()], now=NOW + 10)
        assert report1.settled == []
        assert engine.accounts[victim.device_id].chain_anchor == anchor0  # لم تتقدم

        # توكن الضحية الصحيح المتصل بالمرساة الأصلية ما زال يُسوّى
        legit = victim.send(recipient.device_id, 1_000, now=NOW)
        report2 = engine.settle_batch([legit.to_dict()], now=NOW + 20)
        assert len(report2.settled) == 1
        assert engine.balance(recipient.device_id) == 1_000


class TestSupersededDescendants:
    """جودة#1: ما بُني فوق توكن مرفوض رفضاً قاتلاً لا يُسوّى (يتخطى الحلقة)."""

    def test_descendants_of_insufficient_funds_token_do_not_settle(self):
        engine = SettlementEngine()
        attacker = make_user(engine, balance=5_000)
        victim = make_user(engine, balance=0)

        t0 = attacker.send(victim.device_id, 5_000, now=NOW)  # يستنزف الرصيد
        t1 = craft(attacker, victim.device_id, 5_000, 1, t0.token_hash, NOW + 1)  # رصيد 0
        t2 = craft(attacker, victim.device_id, 1_000, 2, t1.token_hash, NOW + 2)

        report = engine.settle_batch(
            [t0.to_dict(), t1.to_dict(), t2.to_dict()], now=NOW + 100
        )
        reasons = {t.token_id: r for t, r in report.rejected}
        assert [t.token_id for t in report.settled] == [t0.token_id]
        assert reasons[t1.token_id] == RejectReason.INSUFFICIENT_FUNDS
        assert reasons[t2.token_id] == RejectReason.SUPERSEDED  # لم يُسوَّ متخطياً المرفوض
        assert engine.balance(victim.device_id) == 5_000

    def test_expired_token_still_skippable_chain_continues(self):
        """الانتهاء يبقى استثناءً: قيمته تعود للمرسل والسلسلة تكمل بعده."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        short = craft(sender, recipient.device_id, 5_000, 0, sender.chain_head, NOW, ttl=10)
        follow = craft(sender, recipient.device_id, 7_000, 1, short.token_hash, NOW + 5)
        report = engine.settle_batch([short.to_dict(), follow.to_dict()], now=NOW + 3600)
        assert [t.token_id for t in report.settled] == [follow.token_id]
        assert report.rejected[0][1] == RejectReason.EXPIRED


class TestCapPersistsAcrossBatches:
    """دفاع#1 عبر دفعات: عدّاد السقف اليومي يصمد بين دفعتين في نفس اليوم."""

    def test_daily_cap_enforced_across_separate_batches_same_day(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=100_000, daily_cap=30_000)
        victim = make_user(engine, balance=0)

        t1 = sender.send(victim.device_id, 30_000, now=NOW)  # يملأ سقف اليوم
        report1 = engine.settle_batch([t1.to_dict()], now=NOW + 100)
        new_anchor = report1.new_anchors[sender.device_id]

        # دفعة لاحقة نفس اليوم متصلة بالمرساة الجديدة — تُرفض لأن العدّاد محفوظ
        t2 = craft(sender, victim.device_id, 10_000, 0, new_anchor, NOW + 50)
        report = engine.settle_batch([t2.to_dict()], now=NOW + 200)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.DAILY_CAP


class TestMalformedAudit:
    """دفع#5: الحمولات المشوهة تُسجَّل للتدقيق لا تُبتلع صمتاً."""

    def test_malformed_token_recorded_not_dropped(self):
        engine = SettlementEngine()
        report = engine.settle_batch([{"garbage": 1}, {"token_id": "x"}], now=NOW)
        assert len(report.malformed) == 2
        assert report.settled == []
        assert report.rejected == []


class TestTypeConfusion:
    """أمن#6: المبلغ المنطقي bool يُرفض رغم أن isinstance(True, int) صحيح."""

    def test_bool_amount_rejected(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        with pytest.raises(TokenError):
            craft(sender, "00" * 8, True, 0, sender.chain_head, NOW)

    def test_non_three_letter_currency_rejected(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        with pytest.raises(TokenError):
            SignedToken.create(
                keys=sender.keys, recipient_id="00" * 8, amount=1_000, seq=0,
                prev_hash=sender.chain_head, issued_at=NOW, ttl_seconds=3600, currency="US",
            )
