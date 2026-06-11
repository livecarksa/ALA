"""بوابة التسوية: HTTP، الديمومة عبر إعادة التشغيل، وidempotency الدفعات.

هذه ضمانات «بنية تتحمل انقطاع الكهرباء والاتصالات دون فقد
أو تكرار معاملات» (القسم 4.1 من الدراسة).
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


def register_funded(client: GatewayClient, deposit: int = 100_000) -> OfflineWallet:
    wallet = OfflineWallet()
    info = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
    if deposit:
        client.cash_in(wallet.device_id, deposit, f"dep-{uuid.uuid4().hex[:8]}")
    wallet.apply_settlement(deposit, info["chain_anchor"])
    return wallet


class TestHttpApi:
    def test_full_cycle_over_http(self, sandbox):
        client = GatewayClient(sandbox.base_url)
        sender = register_funded(client)
        recipient = register_funded(client, deposit=0)

        token = sender.send(recipient.device_id, 40_000, now=NOW)
        result = client.settle("batch-1", [token.to_dict()], now=NOW + 100)
        assert len(result["settled"]) == 1
        assert client.balance(recipient.device_id)["balance"] == 40_000
        assert client.reconciliation()["balanced"] is True

    def test_bad_requests_return_errors_not_crashes(self, sandbox):
        client = GatewayClient(sandbox.base_url)
        with pytest.raises(GatewayError):
            client.balance("f" * 16)  # جهاز غير معروف → 404
        with pytest.raises(GatewayError):
            client.cash_in("f" * 16, 1_000, "x")  # غير مسجل → 400
        with pytest.raises(GatewayError):
            client._request("POST", "/api/v1/settlements", {"غريب": True})

    def test_duplicate_registration_returns_same_account(self, sandbox):
        client = GatewayClient(sandbox.base_url)
        wallet = OfflineWallet()
        first = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
        second = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
        assert first["device_id"] == second["device_id"]
        assert first["chain_anchor"] == second["chain_anchor"]


class TestIdempotency:
    def test_same_batch_id_settles_once_and_returns_stored_result(self, sandbox):
        """انقطاع أثناء الرفع → إعادة الإرسال بنفس batch_id آمنة دائماً."""
        client = GatewayClient(sandbox.base_url)
        sender = register_funded(client)
        recipient = register_funded(client, deposit=0)

        token = sender.send(recipient.device_id, 25_000, now=NOW)
        first = client.settle("batch-retry", [token.to_dict()], now=NOW + 100)
        second = client.settle("batch-retry", [token.to_dict()], now=NOW + 200)

        assert first == second  # النتيجة المخزنة حرفياً
        assert client.balance(recipient.device_id)["balance"] == 25_000  # لا تكرار قيد

    def test_duplicate_cash_in_reference_credits_once(self, sandbox):
        client = GatewayClient(sandbox.base_url)
        wallet = OfflineWallet()
        client.register(wallet.keys.public_key_hex, wallet.daily_cap)
        client.cash_in(wallet.device_id, 50_000, "agent-receipt-77")
        client.cash_in(wallet.device_id, 50_000, "agent-receipt-77")  # وكيل أعاد المحاولة
        assert client.balance(wallet.device_id)["balance"] == 50_000


class TestDurability:
    def test_state_survives_restart(self, tmp_path):
        """انقطاع كهرباء: خادم جديد على نفس القاعدة — لا فقد ولا تكرار."""
        db = str(tmp_path / "durable.db")
        box1 = BankakSandbox(db_path=db).start()
        client1 = GatewayClient(box1.base_url)
        sender = register_funded(client1)
        recipient = register_funded(client1, deposit=0)
        token = sender.send(recipient.device_id, 30_000, now=NOW)
        client1.settle("batch-d1", [token.to_dict()], now=NOW + 100)
        box1.stop()

        box2 = BankakSandbox(db_path=db).start()
        client2 = GatewayClient(box2.base_url)
        try:
            assert client2.balance(recipient.device_id)["balance"] == 30_000
            assert client2.balance(sender.device_id)["balance"] == 70_000
            # إعادة رفع نفس الدفعة بعد إعادة التشغيل — idempotent عبر الديمومة أيضاً
            replay = client2.settle("batch-d1", [token.to_dict()], now=NOW + 500)
            assert client2.balance(recipient.device_id)["balance"] == 30_000
            assert replay["batch_id"] == "batch-d1"
            assert client2.reconciliation()["balanced"] is True
        finally:
            box2.stop()

    def test_double_spend_freeze_survives_restart(self, tmp_path):
        """تجميد المحتال قرار دائم — لا يزول بإعادة تشغيل الخادم."""
        from token_engine.token import SignedToken

        db = str(tmp_path / "freeze.db")
        box1 = BankakSandbox(db_path=db).start()
        client1 = GatewayClient(box1.base_url)
        attacker = register_funded(client1)
        victim = register_funded(client1, deposit=0)

        legit = attacker.send(victim.device_id, 10_000, now=NOW)
        forged = SignedToken.create(
            keys=attacker.keys, recipient_id=victim.device_id, amount=10_000,
            seq=legit.seq, prev_hash=legit.prev_hash, issued_at=NOW + 5, ttl_seconds=3600,
        )
        result = client1.settle("batch-f1", [legit.to_dict(), forged.to_dict()], now=NOW + 100)
        assert attacker.device_id in result["fraud_alerts"]
        box1.stop()

        box2 = BankakSandbox(db_path=db).start()
        try:
            info = GatewayClient(box2.base_url).balance(attacker.device_id)
            assert info["frozen"] is True
        finally:
            box2.stop()
