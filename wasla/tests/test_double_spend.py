"""اختبارات الإنفاق المزدوج — نموذج التهديد الأساسي (القسم 4.2 من الدراسة).

كل اختبار هنا هجوم فعلي يصنع توكنات يدوياً متجاوزاً كود المحفظة،
لأن المهاجم الحقيقي لن يستخدم تطبيقنا.
"""

from settlement.engine import RejectReason, SettlementEngine
from token_engine.token import SignedToken

from .helpers import NOW, make_user


def fork_token(wallet, recipient_id: str, amount: int, seq: int, prev_hash: str, issued_at: int):
    """توكن مصنوع يدوياً بمفاتيح المهاجم — يحاكي تطبيقاً معدَّلاً."""
    return SignedToken.create(
        keys=wallet.keys,
        recipient_id=recipient_id,
        amount=amount,
        seq=seq,
        prev_hash=prev_hash,
        issued_at=issued_at,
        ttl_seconds=72 * 3600,
    )


class TestForkDetection:
    def test_fork_settles_first_branch_and_rejects_second(self):
        """تفريع السلسلة: نفس النقطة لتوكنين — الأسبق يُسوّى والثاني يُكشف."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=50_000)
        victim_a = make_user(engine, balance=0)
        victim_b = make_user(engine, balance=0)

        legit = attacker.send(victim_a.device_id, 30_000, now=NOW)
        forged = fork_token(attacker, victim_b.device_id, 30_000, legit.seq, legit.prev_hash, NOW + 5)

        report = engine.settle_batch([legit.to_dict(), forged.to_dict()], now=NOW + 100)

        assert [t.token_id for t in report.settled] == [legit.token_id]
        assert (forged.token_id, RejectReason.DOUBLE_SPEND) in [
            (t.token_id, r) for t, r in report.rejected
        ]
        assert engine.balance(victim_a.device_id) == 30_000
        assert engine.balance(victim_b.device_id) == 0

    def test_double_spender_account_is_frozen(self):
        """كشف التفرع يجمّد حساب المهاجم — لا تسوية لاحقة له."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=50_000)
        victim = make_user(engine, balance=0)

        legit = attacker.send(victim.device_id, 10_000, now=NOW)
        forged = fork_token(attacker, victim.device_id, 10_000, legit.seq, legit.prev_hash, NOW + 5)
        report = engine.settle_batch([legit.to_dict(), forged.to_dict()], now=NOW + 100)
        assert attacker.device_id in report.fraud_alerts

        # محاولة لاحقة بعد التجميد تُرفض بالكامل
        later = fork_token(attacker, victim.device_id, 1_000, 0, report.new_anchors[attacker.device_id], NOW + 200)
        report2 = engine.settle_batch([later.to_dict()], now=NOW + 300)
        assert report2.settled == []
        assert report2.rejected[0][1] == RejectReason.ACCOUNT_FROZEN

    def test_fork_descendants_rejected_with_branch(self):
        """كل ما بُني فوق الفرع الاحتيالي يسقط معه."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=100_000)
        victim = make_user(engine, balance=0)

        legit = attacker.send(victim.device_id, 10_000, now=NOW)
        forged1 = fork_token(attacker, victim.device_id, 10_000, legit.seq, legit.prev_hash, NOW + 5)
        forged2 = fork_token(attacker, victim.device_id, 20_000, 1, forged1.token_hash, NOW + 6)

        report = engine.settle_batch(
            [legit.to_dict(), forged1.to_dict(), forged2.to_dict()], now=NOW + 100
        )
        rejected = {t.token_id: r for t, r in report.rejected}
        assert rejected[forged1.token_id] == RejectReason.DOUBLE_SPEND
        assert rejected[forged2.token_id] == RejectReason.DOUBLE_SPEND
        assert engine.balance(victim.device_id) == 10_000

    def test_fork_across_separate_batches_detected(self):
        """الحالة الجوهرية: المستلمان يتصلان في أوقات مختلفة فيصل فرعا التفرع
        في دفعتين منفصلتين. يجب أن يُكشف الإنفاق المزدوج ويُجمّد المهاجم —
        لا أن يمرّ الفرع الثاني كسلسلة مبتورة بلا عقوبة."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=50_000)
        victim_a = make_user(engine, balance=0)
        victim_b = make_user(engine, balance=0)

        legit = attacker.send(victim_a.device_id, 30_000, now=NOW)
        forged = fork_token(attacker, victim_b.device_id, 30_000, legit.seq, legit.prev_hash, NOW + 5)

        report1 = engine.settle_batch([legit.to_dict()], now=NOW + 100)
        assert len(report1.settled) == 1  # الفرع الأول سُوّي لمستلمه البريء
        assert report1.fraud_alerts == []  # لا دليل تفرع بعد

        # الفرع الثاني يصل لاحقاً عبر دفعة منفصلة — نقطة استهلاكه محفوظة
        report2 = engine.settle_batch([forged.to_dict()], now=NOW + 200)
        assert report2.settled == []
        assert report2.rejected[0][1] == RejectReason.DOUBLE_SPEND
        assert attacker.device_id in report2.fraud_alerts
        assert engine.accounts[attacker.device_id].frozen is True
        assert engine.balance(victim_b.device_id) == 0


class TestReplayAndDuplicates:
    def test_replay_same_token_settles_once(self):
        """إعادة رفع نفس التوكن (من الطرفين أو بإعادة إرسال) — تسوية واحدة فقط."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 20_000, now=NOW)
        report = engine.settle_batch([token.to_dict(), token.to_dict()], now=NOW + 100)
        assert len(report.settled) == 1
        assert report.rejected[0][1] == RejectReason.DUPLICATE
        assert engine.balance(recipient.device_id) == 20_000

    def test_replay_in_later_batch_rejected(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 20_000, now=NOW)
        engine.settle_batch([token.to_dict()], now=NOW + 100)
        report2 = engine.settle_batch([token.to_dict()], now=NOW + 200)
        assert report2.settled == []
        assert report2.rejected[0][1] == RejectReason.DUPLICATE
        assert engine.balance(recipient.device_id) == 20_000  # لم يتضاعف


class TestCraftedChains:
    def test_overspend_via_crafted_chain_hits_balance_check(self):
        """مهاجم يفبرك سلسلة تنفق أكثر من رصيده المسوّى — يُوقفه فحص الرصيد."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=10_000)
        victim = make_user(engine, balance=0)

        t1 = fork_token(attacker, victim.device_id, 9_000, 0, attacker.chain_head, NOW)
        t2 = fork_token(attacker, victim.device_id, 9_000, 1, t1.token_hash, NOW + 1)
        report = engine.settle_batch([t1.to_dict(), t2.to_dict()], now=NOW + 100)

        rejected = {t.token_id: r for t, r in report.rejected}
        assert [t.token_id for t in report.settled] == [t1.token_id]
        assert rejected[t2.token_id] == RejectReason.INSUFFICIENT_FUNDS
        assert engine.balance(victim.device_id) == 9_000

    def test_token_signed_with_old_key_after_rotation_rejected(self):
        """بعد تدوير مفتاح الحساب (جهاز مسروق مثلاً) تسقط توكنات المفتاح القديم.

        انتحال device_id بمفتاح مزور يفشل أصلاً في token.verify لأن المعرّف
        مشتق من المفتاح؛ فحص KEY_MISMATCH يغطي الحالة المتبقية: مفتاح سليم
        الاشتقاق لكنه لم يعد المفتاح المسجل للحساب.
        """
        engine = SettlementEngine()
        user = make_user(engine, balance=50_000)
        victim = make_user(engine, balance=0)

        old_token = user.send(victim.device_id, 1_000, now=NOW)
        # البنك دوّر مفتاح الحساب بعد بلاغ سرقة الجهاز
        from token_engine.crypto import DeviceKeys

        engine.accounts[user.device_id].pubkey = DeviceKeys().public_key_hex
        report = engine.settle_batch([old_token.to_dict()], now=NOW + 10)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.KEY_MISMATCH
