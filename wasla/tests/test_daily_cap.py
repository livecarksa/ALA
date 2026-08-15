"""السقف اليومي — طبقة الدفاع الأولى: يحدّ الخسارة القصوى لأي اختراق.

يُفحص مرتين: في المحفظة (حماية المستخدم) وفي محرك التسوية (لا ثقة بالعميل).
"""

import pytest

from settlement.engine import RejectReason, SettlementEngine
from token_engine.errors import DailyCapExceeded, InsufficientOfflineBalance
from token_engine.token import SignedToken

from .helpers import NOW, make_user

DAY = 24 * 3600


class TestWalletSideCap:
    def test_wallet_blocks_spend_over_daily_cap(self):
        engine = SettlementEngine()
        wallet = make_user(engine, balance=100_000, daily_cap=30_000)

        wallet.send("recipient0000001", 20_000, now=NOW)
        with pytest.raises(DailyCapExceeded):
            wallet.send("recipient0000001", 15_000, now=NOW)

    def test_cap_resets_next_day(self):
        engine = SettlementEngine()
        wallet = make_user(engine, balance=100_000, daily_cap=30_000)

        wallet.send("recipient0000001", 30_000, now=NOW)
        token = wallet.send("recipient0000001", 30_000, now=NOW + DAY)
        assert token.amount == 30_000

    def test_wallet_blocks_overspending_balance(self):
        engine = SettlementEngine()
        wallet = make_user(engine, balance=10_000, daily_cap=500_000)
        with pytest.raises(InsufficientOfflineBalance):
            wallet.send("recipient0000001", 10_001, now=NOW)


class TestEngineSideCap:
    def test_engine_rejects_crafted_tokens_over_cap(self):
        """تطبيق معدَّل يتجاوز فحص المحفظة — المحرك يرفض ما فوق السقف."""
        engine = SettlementEngine()
        attacker = make_user(engine, balance=100_000, daily_cap=30_000)
        victim = make_user(engine, balance=0)

        prev = attacker.chain_head
        tokens = []
        for seq, amount in enumerate([20_000, 20_000]):  # المجموع فوق السقف
            token = SignedToken.create(
                keys=attacker.keys,
                recipient_id=victim.device_id,
                amount=amount,
                seq=seq,
                prev_hash=prev,
                issued_at=NOW + seq,
                ttl_seconds=3600,
            )
            prev = token.token_hash
            tokens.append(token)

        report = engine.settle_batch([t.to_dict() for t in tokens], now=NOW + 100)
        assert [t.token_id for t in report.settled] == [tokens[0].token_id]
        assert (tokens[1].token_id, RejectReason.DAILY_CAP) in [
            (t.token_id, r) for t, r in report.rejected
        ]
        assert engine.balance(victim.device_id) == 20_000

    def test_engine_cap_tracked_per_issue_day(self):
        """توكنات يومين مختلفين تُحسب كلٌّ على سقف يومها."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=100_000, daily_cap=30_000)
        victim = make_user(engine, balance=0)

        t1 = sender.send(victim.device_id, 30_000, now=NOW)
        t2 = sender.send(victim.device_id, 30_000, now=NOW + DAY)
        report = engine.settle_batch([t1.to_dict(), t2.to_dict()], now=NOW + DAY + 100)
        assert len(report.settled) == 2
        assert engine.balance(victim.device_id) == 60_000
