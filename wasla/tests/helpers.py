"""أدوات مشتركة للاختبارات."""

import time

from settlement.engine import SettlementEngine
from token_engine.wallet import OfflineWallet

NOW = int(time.time())


def make_user(engine: SettlementEngine, balance: int = 100_000, daily_cap: int = 500_000) -> OfflineWallet:
    """جهاز مسجل بإيداع جاهز للإنفاق الأوف لاين."""
    wallet = OfflineWallet(daily_cap=daily_cap)
    account = engine.register_device(wallet.keys.public_key_hex, daily_cap)
    if balance:
        engine.cash_in(wallet.device_id, balance)
    wallet.apply_settlement(balance, account.chain_anchor)
    return wallet
