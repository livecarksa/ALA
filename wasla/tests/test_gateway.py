"""بوابة التسوية: HTTP، المصادقة، الديمومة عبر إعادة التشغيل، وidempotency الدفعات.

هذه ضمانات «بنية تتحمل انقطاع الكهرباء والاتصالات دون فقد
أو تكرار معاملات» (القسم 4.1) مع مصادقة الطلبات (مراجعة المجلس).
"""

import uuid

import pytest

from gateway.client import GatewayClient, GatewayError
from gateway.sandbox import BankakSandbox
from token_engine.wallet import OfflineWallet

from .helpers import NOW


@pytest.fixture()
def sandbox(tmp_path):
    box = BankakSandbox(db_path=str(tmp_path / "sandbox.db")).start()
    yield box
    box.stop()


def make_device(box, deposit: int = 100_000):
    """جهاز مسجَّل بعميله الموقّع بمفتاحه — كل هاتف يحدّث البنك كنفسه."""
    wallet = OfflineWallet()
    client = GatewayClient(box.base_url, keys=wallet.keys)
    info = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
    if deposit:
        client.cash_in(wallet.device_id, deposit, f"dep-{uuid.uuid4().hex[:8]}")
    wallet.apply_settlement(deposit, info["chain_anchor"])
    return wallet, client


class TestHttpApi:
    def test_full_cycle_over_http(self, sandbox):
        sender, sc = make_device(sandbox)
        recipient, rc = make_device(sandbox, deposit=0)

        token = sender.send(recipient.device_id, 40_000, now=NOW)
        result = sc.settle("batch-1", [token.to_dict()], now=NOW + 100)
        assert len(result["settled"]) == 1
        assert rc.balance(recipient.device_id)["balance"] == 40_000
        assert sc.reconciliation()["balanced"] is True

    def test_bad_requests_return_errors_not_crashes(self, sandbox):
        keyless = GatewayClient(sandbox.base_url)
        with pytest.raises(GatewayError):
            keyless.balance("f" * 16)  # غير موقّع → 401
        with pytest.raises(GatewayError):
            keyless.cash_in("f" * 16, 1_000, "x")  # غير موقّع → 401
        _, sc = make_device(sandbox)
        with pytest.raises(GatewayError):
            sc._request("POST", "/api/v1/settlements", {"غريب": True})  # موقّع لكن جسم سيئ → 400

    def test_duplicate_registration_returns_same_account(self, sandbox):
        client = GatewayClient(sandbox.base_url)  # التسجيل مفتوح
        wallet = OfflineWallet()
        first = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
        second = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
        assert first["device_id"] == second["device_id"]
        assert first["chain_anchor"] == second["chain_anchor"]


class TestIdempotency:
    def test_same_batch_id_settles_once_and_returns_stored_result(self, sandbox):
        """انقطاع أثناء الرفع → إعادة الإرسال بنفس batch_id آمنة دائماً."""
        sender, sc = make_device(sandbox)
        recipient, rc = make_device(sandbox, deposit=0)

        token = sender.send(recipient.device_id, 25_000, now=NOW)
        first = sc.settle("batch-retry", [token.to_dict()], now=NOW + 100)
        second = sc.settle("batch-retry", [token.to_dict()], now=NOW + 200)

        assert first == second  # النتيجة المخزنة حرفياً
        assert rc.balance(recipient.device_id)["balance"] == 25_000  # لا تكرار قيد

    def test_duplicate_cash_in_reference_credits_once(self, sandbox):
        wallet, c = make_device(sandbox, deposit=0)
        c.cash_in(wallet.device_id, 50_000, "agent-receipt-77")
        c.cash_in(wallet.device_id, 50_000, "agent-receipt-77")  # وكيل أعاد المحاولة
        assert c.balance(wallet.device_id)["balance"] == 50_000

    def test_cash_in_reference_amount_mismatch_rejected(self, sandbox):
        """دفع#3: نفس المرجع بمبلغ مختلف تضارب يُرفع لا يُبتلع صمتاً."""
        wallet, c = make_device(sandbox, deposit=0)
        c.cash_in(wallet.device_id, 50_000, "agent-receipt-9")
        with pytest.raises(GatewayError):
            c.cash_in(wallet.device_id, 60_000, "agent-receipt-9")
        assert c.balance(wallet.device_id)["balance"] == 50_000


class TestDurability:
    def test_state_survives_restart(self, tmp_path):
        """انقطاع كهرباء: خادم جديد على نفس القاعدة — لا فقد ولا تكرار."""
        db = str(tmp_path / "durable.db")
        box1 = BankakSandbox(db_path=db).start()
        sender, sc = make_device(box1)
        recipient, _ = make_device(box1, deposit=0)
        token = sender.send(recipient.device_id, 30_000, now=NOW)
        sc.settle("batch-d1", [token.to_dict()], now=NOW + 100)
        box1.stop()

        box2 = BankakSandbox(db_path=db).start()
        sc2 = GatewayClient(box2.base_url, keys=sender.keys)
        rc2 = GatewayClient(box2.base_url, keys=recipient.keys)
        try:
            assert rc2.balance(recipient.device_id)["balance"] == 30_000
            assert sc2.balance(sender.device_id)["balance"] == 70_000
            # إعادة رفع نفس الدفعة بعد إعادة التشغيل — idempotent عبر الديمومة أيضاً
            replay = sc2.settle("batch-d1", [token.to_dict()], now=NOW + 500)
            assert rc2.balance(recipient.device_id)["balance"] == 30_000
            assert replay["batch_id"] == "batch-d1"
            assert GatewayClient(box2.base_url).reconciliation()["balanced"] is True
        finally:
            box2.stop()

    def test_double_spend_freeze_survives_restart(self, tmp_path):
        """تجميد المحتال قرار دائم — لا يزول بإعادة تشغيل الخادم."""
        from token_engine.token import SignedToken

        db = str(tmp_path / "freeze.db")
        box1 = BankakSandbox(db_path=db).start()
        attacker, ac = make_device(box1)
        victim, _ = make_device(box1, deposit=0)

        legit = attacker.send(victim.device_id, 10_000, now=NOW)
        forged = SignedToken.create(
            keys=attacker.keys, recipient_id=victim.device_id, amount=10_000,
            seq=legit.seq, prev_hash=legit.prev_hash, issued_at=NOW + 5, ttl_seconds=3600,
        )
        result = ac.settle("batch-f1", [legit.to_dict(), forged.to_dict()], now=NOW + 100)
        assert attacker.device_id in result["fraud_alerts"]
        box1.stop()

        box2 = BankakSandbox(db_path=db).start()
        try:
            ac2 = GatewayClient(box2.base_url, keys=attacker.keys)
            assert ac2.balance(attacker.device_id)["frozen"] is True
        finally:
            box2.stop()
