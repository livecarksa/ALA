"""عميل بوابة التسوية — يستخدمه التطبيق المبسط للحديث مع بيئة الاختبار.

stdlib فقط (urllib) — لا تبعيات شبكية إضافية في النموذج الأولي.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

from token_engine.errors import WaslaError

from .auth import sign_request


class GatewayError(WaslaError):
    """فشل في الاتصال بالبوابة أو ردّ خطأ منها."""


class GatewayClient:
    """عميل البوابة. إن مُرّر `keys` يوقّع كل طلب بمفتاح الجهاز —
    وهو المطلوب لكل ما عدا التسجيل (بوابة الانضمام المفتوحة)."""

    def __init__(self, base_url: str, timeout: float = 10.0, keys=None):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.keys = keys

    def _request(self, method: str, path: str, body: dict | None = None) -> dict:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
        headers = {"Content-Type": "application/json; charset=utf-8"}
        if self.keys is not None:
            timestamp = int(time.time())
            headers["X-Wasla-Device"] = self.keys.device_id
            headers["X-Wasla-Timestamp"] = str(timestamp)
            headers["X-Wasla-Signature"] = sign_request(
                self.keys, method, path, timestamp, data or b""
            )
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            method=method,
            headers=headers,
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
