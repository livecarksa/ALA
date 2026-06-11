"""عميل بوابة التسوية — يستخدمه التطبيق المبسط للحديث مع بيئة الاختبار.

stdlib فقط (urllib) — لا تبعيات شبكية إضافية في النموذج الأولي.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from token_engine.errors import WaslaError


class GatewayError(WaslaError):
    """فشل في الاتصال بالبوابة أو ردّ خطأ منها."""


class GatewayClient:
    def __init__(self, base_url: str, timeout: float = 10.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            method=method,
            headers={"Content-Type": "application/json; charset=utf-8"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            try:
                detail = json.loads(exc.read().decode("utf-8")).get("error", "")
            except Exception:
                detail = ""
            raise GatewayError(f"البوابة ردت {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise GatewayError(f"تعذر الوصول للبوابة {self.base_url}: {exc.reason}") from exc

    def register(self, pubkey_hex: str, daily_cap: int) -> dict:
        return self._request("POST", "/api/v1/accounts", {"pubkey": pubkey_hex, "daily_cap": daily_cap})

    def cash_in(self, device_id: str, amount: int, reference: str) -> dict:
        return self._request(
            "POST", "/api/v1/cash-in",
            {"device_id": device_id, "amount": amount, "reference": reference},
        )

    def settle(self, batch_id: str, tokens: list[dict], now: int | None = None) -> dict:
        body = {"batch_id": batch_id, "tokens": tokens}
        if now is not None:
            body["now"] = now
        return self._request("POST", "/api/v1/settlements", body)

    def balance(self, device_id: str) -> dict:
        return self._request("GET", f"/api/v1/balance/{device_id}")

    def reconciliation(self) -> dict:
        return self._request("GET", "/api/v1/reconciliation")
