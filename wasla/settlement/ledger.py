"""دفتر معاملات مزدوج القيد.

كل تسوية قيدان متوازنان: مدين على حساب المرسل ودائن لحساب المستلم.
ميزان المراجعة يجب أن يساوي صفراً دائماً — أي انحراف يعني خللاً في المحرك.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Posting:
    posting_id: int
    debit_account: str
    credit_account: str
    amount: int  # بالقرش
    reference: str  # token_id أو مرجع الإيداع
    memo: str = ""


@dataclass
class Ledger:
    balances: dict[str, int] = field(default_factory=dict)
    postings: list[Posting] = field(default_factory=list)

    def open_account(self, account: str, _initial: int = 0) -> None:
        self.balances.setdefault(account, 0)

    def post(self, debit: str, credit: str, amount: int, reference: str, memo: str = "") -> Posting:
        if amount <= 0:
            raise ValueError("قيد بمبلغ غير موجب")
        self.open_account(debit)
        self.open_account(credit)
        posting = Posting(len(self.postings) + 1, debit, credit, amount, reference, memo)
        self.balances[debit] -= amount
        self.balances[credit] += amount
        self.postings.append(posting)
        return posting

    def balance(self, account: str) -> int:
        return self.balances.get(account, 0)

    def trial_balance(self) -> int:
        """مجموع كل الأرصدة — صفر دائماً في دفتر مزدوج القيد سليم."""
        return sum(self.balances.values())
