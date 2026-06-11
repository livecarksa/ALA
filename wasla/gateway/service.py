"""خدمة التسوية المعمّرة: محرك التسوية فوق قاعدة SQLite.

ضمانتان جوهريتان لمتطلب «بنية تتحمل انقطاع الكهرباء دون فقد
أو تكرار معاملات» (القسم 4.1):

1. كل عملية كتابة تُحفظ ذرياً قبل إعادة النتيجة — إعادة التشغيل
   تستأنف من آخر حالة محفوظة.
2. التسوية idempotent بمعرّف دفعة: نفس batch_id يعيد النتيجة
   المخزنة حرفياً بلا أي أثر مالي جديد — انقطاع الاتصال أثناء
   الرفع وإعادة المحاولة آمنان دائماً.
"""

from __future__ import annotations

import json
import sqlite3
import threading

from settlement.engine import SettlementEngine
from token_engine.crypto import sha256_hex

_SCHEMA = """
CREATE TABLE IF NOT EXISTS engine_state (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    state TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS settlement_batches (
    batch_id TEXT PRIMARY KEY,
    result TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
"""


class GatewayService:
    def __init__(self, db_path: str = ":memory:"):
        self._db = sqlite3.connect(db_path, check_same_thread=False)
        self._db.executescript(_SCHEMA)
        self._lock = threading.Lock()  # خادم HTTP متعدد الخيوط — المحرك يُلمس تسلسلياً
        row = self._db.execute("SELECT state FROM engine_state WHERE id = 1").fetchone()
        self.engine = SettlementEngine.from_state(json.loads(row[0])) if row else SettlementEngine()

    def _reload_from_db(self) -> None:
        """يعيد المحرك في الذاكرة لآخر حالة محفوظة — يُستدعى إن فشل الحفظ."""
        row = self._db.execute("SELECT state FROM engine_state WHERE id = 1").fetchone()
        self.engine = SettlementEngine.from_state(json.loads(row[0])) if row else SettlementEngine()

    def _persist(self) -> None:
        """حفظ ذري للحالة. إن فشل الحفظ نُرجع المحرك في الذاكرة للحالة المحفوظة
        حتى لا تبقى تعديلات لم تُكتب مصدراً وحيداً للحقيقة بين الطلبات."""
        state = json.dumps(self.engine.to_state(), ensure_ascii=False)
        try:
            with self._db:
                self._db.execute(
                    "INSERT INTO engine_state (id, state) VALUES (1, ?) "
                    "ON CONFLICT (id) DO UPDATE SET state = excluded.state",
                    (state,),
                )
        except Exception:
            self._reload_from_db()
            raise

    # ---------- العمليات ----------

    def register(self, pubkey_hex: str, daily_cap: int) -> dict:
        with self._lock:
            existing_id = sha256_hex(bytes.fromhex(pubkey_hex))[:16]
            if existing_id in self.engine.accounts:
                account = self.engine.accounts[existing_id]  # تسجيل مكرر — نفس الحساب
            else:
                self.engine.register_device(pubkey_hex, daily_cap)
                self._persist()  # يُرجع الحالة إن فشل، فلا حساب شبح في الذاكرة
                account = self.engine.accounts[existing_id]
            return {
                "device_id": account.device_id,
                "chain_anchor": account.chain_anchor,
                "daily_cap": account.daily_cap,
            }

    def cash_in(self, device_id: str, amount: int, reference: str) -> dict:
        with self._lock:
            if device_id not in self.engine.accounts:
                raise KeyError("جهاز غير مسجل")
            # نفس المرجع لنفس الجهاز إيداع واحد — وكيل أعاد المحاولة بعد انقطاع.
            # لكن لو اختلف المبلغ لنفس المرجع فهو تضارب يُرفع لا يُبتلع صمتاً.
            prior = next(
                (p for p in self.engine.ledger.postings
                 if p.reference == reference and p.credit_account == device_id),
                None,
            )
            if prior is not None:
                if prior.amount != amount:
                    raise ValueError(
                        f"المرجع {reference} مستخدم بمبلغ {prior.amount} لا {amount}"
                    )
            else:
                self.engine.cash_in(device_id, amount, reference)
                self._persist()
            return {"device_id": device_id, "balance": self.engine.balance(device_id)}

    def settle(self, batch_id: str, tokens: list[dict], now: int | None = None) -> dict:
        with self._lock:
            row = self._db.execute(
                "SELECT result FROM settlement_batches WHERE batch_id = ?", (batch_id,)
            ).fetchone()
            if row:
                return json.loads(row[0])  # دفعة مكررة — النتيجة المخزنة حرفياً

            report = self.engine.settle_batch(tokens, now=now)
            result = report.to_dict()
            result["batch_id"] = batch_id
            result["balances_after_batch"] = {
                t.sender_id: self.engine.balance(t.sender_id) for t in report.settled
            }
            state = json.dumps(self.engine.to_state(), ensure_ascii=False)
            try:
                with self._db:  # الحالة ونتيجة الدفعة في معاملة واحدة — لا منطقة رمادية
                    self._db.execute(
                        "INSERT INTO engine_state (id, state) VALUES (1, ?) "
                        "ON CONFLICT (id) DO UPDATE SET state = excluded.state",
                        (state,),
                    )
                    self._db.execute(
                        "INSERT INTO settlement_batches (batch_id, result) VALUES (?, ?)",
                        (batch_id, json.dumps(result, ensure_ascii=False)),
                    )
            except Exception:
                # فشل الحفظ: نُرجع المحرك للحالة المحفوظة فلا تُسوّى دفعة بلا سجل
                self._reload_from_db()
                raise
            return result

    def pubkey_for(self, device_id: str) -> str | None:
        """المفتاح العام المسجَّل للجهاز — تستخدمه طبقة المصادقة للتحقق."""
        with self._lock:
            account = self.engine.accounts.get(device_id)
            return account.pubkey if account else None

    def balance(self, device_id: str) -> dict:
        with self._lock:
            if device_id not in self.engine.accounts and device_id not in self.engine.ledger.balances:
                raise KeyError("جهاز غير معروف")
            account = self.engine.accounts.get(device_id)
            return {
                "device_id": device_id,
                "balance": self.engine.balance(device_id),
                "frozen": account.frozen if account else False,
                "chain_anchor": account.chain_anchor if account else None,
            }

    def reconciliation(self) -> dict:
        """تقرير المطابقة اليومية بين دفتر وصلة وحسابات البنك (القسم 5.3)."""
        with self._lock:
            ledger = self.engine.ledger
            return {
                "trial_balance": ledger.trial_balance(),
                "balanced": ledger.trial_balance() == 0,
                "postings_count": len(ledger.postings),
                "settled_tokens": len(self.engine._settled_token_ids),
                "accounts": len(self.engine.accounts),
                "frozen_accounts": sorted(
                    d for d, a in self.engine.accounts.items() if a.frozen
                ),
            }

    def close(self) -> None:
        self._db.close()
