"""انتهاء الصلاحية (طبقة الدفاع الثالثة) وكشف التلاعب بالحمولة."""

import dataclasses

import pytest

from settlement.engine import RejectReason, SettlementEngine
from token_engine.errors import ExpiredToken, InvalidSignature
from token_engine.token import SignedToken, TokenError

from .helpers import NOW, make_user


class TestExpiry:
    def test_expired_token_rejected_at_settlement_funds_return_to_sender(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 20_000, now=NOW)
        after_expiry = token.expires_at + 1
        report = engine.settle_batch([token.to_dict()], now=after_expiry)

        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.EXPIRED
        # القيمة لم تُخصم: رصيد المرسل المسوّى سليم والمستلم بلا شيء
        assert engine.balance(sender.device_id) == 50_000
        assert engine.balance(recipient.device_id) == 0

    def test_recipient_wallet_refuses_expired_token(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 1_000, now=NOW)
        with pytest.raises(ExpiredToken):
            recipient.receive(token, now=token.expires_at + 1)

    def test_expired_token_does_not_break_rest_of_chain(self):
        """توكن منتهٍ وسط السلسلة لا يُسقط ما بعده — السلسلة تبقى متصلة."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        short_lived = SignedToken.create(
            keys=sender.keys,
            recipient_id=recipient.device_id,
            amount=5_000,
            seq=0,
            prev_hash=sender.chain_head,
            issued_at=NOW,
            ttl_seconds=10,
        )
        follow_up = SignedToken.create(
            keys=sender.keys,
            recipient_id=recipient.device_id,
            amount=7_000,
            seq=1,
            prev_hash=short_lived.token_hash,
            issued_at=NOW + 5,
            ttl_seconds=72 * 3600,
        )
        report = engine.settle_batch(
            [short_lived.to_dict(), follow_up.to_dict()], now=NOW + 3600
        )
        assert [t.token_id for t in report.settled] == [follow_up.token_id]
        assert report.rejected[0][1] == RejectReason.EXPIRED
        assert engine.balance(recipient.device_id) == 7_000


class TestTamper:
    def test_tampered_amount_invalidates_signature(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 1_000, now=NOW)
        inflated = dataclasses.replace(token, amount=99_000)
        with pytest.raises(InvalidSignature):
            inflated.verify()

        report = engine.settle_batch([inflated.to_dict()], now=NOW + 10)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.BAD_SIGNATURE

    def test_tampered_recipient_invalidates_signature(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        recipient = make_user(engine, balance=0)
        thief = make_user(engine, balance=0)

        token = sender.send(recipient.device_id, 1_000, now=NOW)
        redirected = dataclasses.replace(token, recipient_id=thief.device_id)
        report = engine.settle_batch([redirected.to_dict()], now=NOW + 10)
        assert report.settled == []
        assert report.rejected[0][1] == RejectReason.BAD_SIGNATURE
        assert engine.balance(thief.device_id) == 0

    def test_forged_sender_identity_fails_verification(self):
        """انتحال معرّف مرسل آخر يفشل: المعرّف مشتق من المفتاح العام."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        attacker = make_user(engine, balance=0)

        token = sender.send(attacker.device_id, 1_000, now=NOW)
        impersonated = dataclasses.replace(token, sender_id=attacker.device_id)
        with pytest.raises(InvalidSignature):
            impersonated.verify()

    def test_zero_and_negative_amounts_rejected(self):
        engine = SettlementEngine()
        sender = make_user(engine, balance=50_000)
        for bad_amount in (0, -5_000):
            with pytest.raises(TokenError):
                SignedToken.create(
                    keys=sender.keys,
                    recipient_id="recipient0000001",
                    amount=bad_amount,
                    seq=0,
                    prev_hash=sender.chain_head,
                    issued_at=NOW,
                    ttl_seconds=3600,
                )
