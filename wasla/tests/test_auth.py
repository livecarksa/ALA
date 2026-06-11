"""مصادقة طلبات البوابة — إثبات الحيازة يمنع التصرف نيابة عن غير المالك.

يغلق ثغرة «البوابة بلا مصادقة» التي رصدها مجلس المراجعة.
"""

import time
import uuid

import pytest

from gateway.client import GatewayClient, GatewayError
from gateway.sandbox import BankakSandbox
from token_engine.crypto import DeviceKeys
from token_engine.wallet import OfflineWallet

from .helpers import NOW


@pytest.fixture()
def sandbox(tmp_path):
    box = BankakSandbox(db_path=str(tmp_path / "auth.db")).start()
    yield box
    box.stop()


def enroll(box, deposit: int = 100_000):
    wallet = OfflineWallet()
    client = GatewayClient(box.base_url, keys=wallet.keys)
    info = client.register(wallet.keys.public_key_hex, wallet.daily_cap)
    if deposit:
        client.cash_in(wallet.device_id, deposit, f"dep-{uuid.uuid4().hex[:8]}")
    wallet.apply_settlement(deposit, info["chain_anchor"])
    return wallet, client


class TestRegistrationOpen:
    def test_register_works_without_signature(self, sandbox):
        """التسجيل بوابة الانضمام — مفتوحة، فالجهاز الجديد لا حساب له بعد ليوقّع به."""
        keyless = GatewayClient(sandbox.base_url)
        wallet = OfflineWallet()
        info = keyless.register(wallet.keys.public_key_hex, wallet.daily_cap)
        assert info["device_id"] == wallet.device_id


class TestUnsignedRejected:
    def test_unsigned_settle_rejected(self, sandbox):
        sender, _ = enroll(sandbox)
        recipient, _ = enroll(sandbox, deposit=0)
        token = sender.send(recipient.device_id, 10_000, now=NOW)
        keyless = GatewayClient(sandbox.base_url)
        with pytest.raises(GatewayError):
            keyless.settle("b1", [token.to_dict()], now=NOW + 100)

    def test_unsigned_cash_in_and_balance_rejected(self, sandbox):
        wallet, _ = enroll(sandbox, deposit=0)
        keyless = GatewayClient(sandbox.base_url)
        with pytest.raises(GatewayError):
            keyless.cash_in(wallet.device_id, 1_000, "x")
        with pytest.raises(GatewayError):
            keyless.balance(wallet.device_id)


class TestForgedSignatureRejected:
    def test_unregistered_signer_rejected(self, sandbox):
        """مفتاح غير مسجل لا يُقبل توقيعه مهما كان صالحاً بنيوياً."""
        victim, _ = enroll(sandbox, deposit=0)
        rogue = GatewayClient(sandbox.base_url, keys=DeviceKeys())  # مفتاح لا حساب له
        with pytest.raises(GatewayError):
            rogue.balance(victim.device_id)  # جهاز غير مسجل → 401

    def test_tampered_body_after_signing_rejected(self, sandbox):
        sender, sc = enroll(sandbox)
        recipient, _ = enroll(sandbox, deposit=0)
        token = sender.send(recipient.device_id, 10_000, now=NOW)
        # نوقّع على دفعة ثم نغيّر الجسم — التوقيع يغطي بصمة الجسم فيُرفض
        import json
        import urllib.request

        from gateway.auth import sign_request

        path = "/api/v1/settlements"
        good_body = json.dumps({"batch_id": "b1", "tokens": [token.to_dict()]}).encode()
        ts = int(time.time())
        sig = sign_request(sender.keys, "POST", path, ts, good_body)
        tampered = json.dumps({"batch_id": "b2", "tokens": [token.to_dict()]}).encode()
        req = urllib.request.Request(
            sandbox.base_url + path, data=tampered, method="POST",
            headers={
                "Content-Type": "application/json",
                "X-Wasla-Device": sender.device_id,
                "X-Wasla-Timestamp": str(ts),
                "X-Wasla-Signature": sig,
            },
        )
        with pytest.raises(urllib.error.HTTPError) as exc:
            urllib.request.urlopen(req)
        assert exc.value.code == 401


class TestReplayWindow:
    def test_stale_timestamp_rejected(self, sandbox):
        import json
        import urllib.error
        import urllib.request

        from gateway.auth import MAX_REQUEST_SKEW, sign_request

        wallet, _ = enroll(sandbox, deposit=0)
        path = f"/api/v1/balance/{wallet.device_id}"
        stale = int(time.time()) - MAX_REQUEST_SKEW - 60
        sig = sign_request(wallet.keys, "GET", path, stale, b"")
        req = urllib.request.Request(
            sandbox.base_url + path, method="GET",
            headers={
                "X-Wasla-Device": wallet.device_id,
                "X-Wasla-Timestamp": str(stale),
                "X-Wasla-Signature": sig,
            },
        )
        with pytest.raises(urllib.error.HTTPError) as exc:
            urllib.request.urlopen(req)
        assert exc.value.code == 401


class TestAuthorizationScope:
    def test_cannot_fund_another_device(self, sandbox):
        _, attacker_client = enroll(sandbox, deposit=0)
        victim, _ = enroll(sandbox, deposit=0)
        # المهاجم موقّع بمفتاحه لكن يطلب تمويل حساب الضحية → 403
        with pytest.raises(GatewayError):
            attacker_client.cash_in(victim.device_id, 5_000, "evil")

    def test_cannot_read_another_device_balance(self, sandbox):
        _, attacker_client = enroll(sandbox, deposit=0)
        victim, _ = enroll(sandbox, deposit=0)
        with pytest.raises(GatewayError):
            attacker_client.balance(victim.device_id)
