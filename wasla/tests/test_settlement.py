"""المسار السعيد للتسوية، سلامة الدفتر مزدوج القيد، ودورة المحاكي كاملة."""

from settlement.engine import RejectReason, SettlementEngine
from settlement.simulator import run_simulation

from .helpers import NOW, make_user


class TestHappyPath:
    def test_multi_hop_offline_day_settles_and_ledger_balances(self):
        """يوم أوف لاين كامل: سلسلة تحويلات ثم تسوية — كل قرش في مكانه."""
        engine = SettlementEngine()
        alice = make_user(engine, balance=100_000)
        bob = make_user(engine, balance=20_000)
        merchant = make_user(engine, balance=0)

        t1 = alice.send(bob.device_id, 30_000, now=NOW)
        bob.receive(t1, now=NOW)
        t2 = alice.send(merchant.device_id, 10_000, now=NOW + 60)
        merchant.receive(t2, now=NOW + 60)
        t3 = bob.send(merchant.device_id, 5_000, now=NOW + 120)
        merchant.receive(t3, now=NOW + 120)

        # الطرفان يرفعان — المكرر يُسوّى مرة واحدة
        batch = alice.tokens_for_settlement() + bob.tokens_for_settlement() + merchant.tokens_for_settlement()
        report = engine.settle_batch(batch, now=NOW + 3600)

        assert len(report.settled) == 3
        assert report.fraud_alerts == []
        assert engine.balance(alice.device_id) == 60_000
        assert engine.balance(bob.device_id) == 45_000  # 20+30-5 ألف قرش
        assert engine.balance(merchant.device_id) == 15_000
        assert engine.ledger.trial_balance() == 0

    def test_wallet_chain_resumes_after_settlement(self):
        """بعد التسوية: مرساة جديدة وسلسلة جديدة تُسوّى بدورها بنجاح."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        t1 = sender.send(recipient.device_id, 10_000, now=NOW)
        report1 = engine.settle_batch([t1.to_dict()], now=NOW + 100)
        sender.apply_settlement(engine.balance(sender.device_id), report1.new_anchors[sender.device_id])

        t2 = sender.send(recipient.device_id, 15_000, now=NOW + 200)
        report2 = engine.settle_batch([t2.to_dict()], now=NOW + 300)
        assert [t.token_id for t in report2.settled] == [t2.token_id]
        assert engine.balance(recipient.device_id) == 25_000

    def test_recipient_without_prior_account_gets_credited(self):
        """استلام بلا حساب مسبق — يُفتح حساب للمستلم عند أول تسوية (شمول مالي)."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)

        token = sender.send("unbanked00000001", 8_000, now=NOW)
        report = engine.settle_batch([token.to_dict()], now=NOW + 10)
        assert len(report.settled) == 1
        assert engine.balance("unbanked00000001") == 8_000
        assert engine.ledger.trial_balance() == 0


class TestChainIntegrity:
    def test_token_with_unknown_prev_hash_rejected(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 1_000, now=NOW)
        # تخريب الربط: مرساة الحساب تغيّرت قبل وصول التوكن
        engine.accounts[sender.device_id].chain_anchor = "0" * 64
        report = engine.settle_batch([token.to_dict()], now=NOW + 10)
        assert report.rejected[0][1] == RejectReason.CHAIN_BROKEN

    def test_unregistered_sender_rejected(self):
        engine = SettlementEngine()
        outsider = make_user(SettlementEngine(), balance=50_000)  # مسجل في محرك آخر

        token = outsider.send("recipient0000001", 1_000, now=NOW)
        report = engine.settle_batch([token.to_dict()], now=NOW + 10)
        assert report.rejected[0][1] == RejectReason.UNREGISTERED_SENDER


class TestSimulator:
    def test_full_simulation_detects_fraud_and_balances(self):
        """دورة المحاكي كاملة: تحويلات، هجوم تفرع، تسوية — حتمية بالبذرة."""
        result = run_simulation(seed=42, users=8, verbose=False)
        assert result["settled"] > 0
        assert len(result["fraud_alerts"]) == 1  # المهاجم وحده
        assert result["trial_balance"] == 0  # الدفتر متوازن دائماً

    def test_simulation_deterministic_for_same_seed(self):
        a = run_simulation(seed=11, users=6, verbose=False)
        b = run_simulation(seed=11, users=6, verbose=False)
        assert (a["transfers"], a["settled"], a["rejected"]) == (
            b["transfers"],
            b["settled"],
            b["rejected"],
        )
