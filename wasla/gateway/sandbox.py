"""بيئة اختبار بنكك المحاكية — خادم HTTP بواجهة REST.

الواجهات تعكس ما ستوفره اتفاقية الوصول التقني (القسم 5.3):

    POST /api/v1/accounts          {pubkey, daily_cap}
    POST /api/v1/cash-in           {device_id, amount, reference}
    POST /api/v1/settlements       {batch_id, tokens[], now?}
    GET  /api/v1/balance/<device_id>
    GET  /api/v1/reconciliation

التشغيل المستقل:  python3 -m gateway.sandbox --port 8980 --db wasla-sandbox.db
"""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from token_engine.errors import InvalidSignature

from .auth import Unauthorized, verify_request
from .service import GatewayService

MAX_BODY_BYTES = 5 * 1024 * 1024  # دفعة تسوية مدينة كاملة تبقى دون هذا بكثير


class _Handler(BaseHTTPRequestHandler):
    service: GatewayService  # يُحقن عند إنشاء الخادم

    def log_message(self, *args) -> None:  # صمت في الاختبارات
        pass

    def _reply(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        if not 0 <= length <= MAX_BODY_BYTES:
            raise ValueError("حجم طلب غير مقبول")
        return self.rfile.read(length) if length else b""

    def _json(self, body: bytes) -> dict:
        data = json.loads(body.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("جسم الطلب يجب أن يكون كائن JSON")
        return data

    def _authenticate(self, path: str, body: bytes) -> str:
        """يتحقق من توقيع الطلب ويعيد معرّف الجهاز الموثَّق، أو يرفع Unauthorized."""
        device = self.headers.get("X-Wasla-Device")
        timestamp = self.headers.get("X-Wasla-Timestamp")
        signature = self.headers.get("X-Wasla-Signature")
        if not (device and timestamp and signature):
            raise Unauthorized("طلب غير موقّع — المصادقة مطلوبة")
        pubkey = self.service.pubkey_for(device)
        if pubkey is None:
            raise Unauthorized("جهاز غير مسجل")
        try:
            verify_request(pubkey, signature, self.command, path, int(timestamp), body, int(time.time()))
        except (InvalidSignature, ValueError) as exc:
            raise Unauthorized(str(exc)) from exc
        return device

    def do_GET(self) -> None:
        try:
            match = re.fullmatch(r"/api/v1/balance/([0-9a-f]{16})", self.path)
            if match:
                device = self._authenticate(self.path, b"")
                if device != match.group(1):
                    self._reply(403, {"error": "استعلام رصيد جهاز آخر غير مسموح"})
                    return
                self._reply(200, self.service.balance(match.group(1)))
            elif self.path == "/api/v1/reconciliation":
                self._reply(200, self.service.reconciliation())  # تقرير تشغيلي مفتوح
            else:
                self._reply(404, {"error": "مسار غير معروف"})
        except Unauthorized as exc:
            self._reply(401, {"error": str(exc)})
        except KeyError as exc:
            self._reply(404, {"error": str(exc)})
        except Exception as exc:  # حافة الخادم: لا انهيار على طلب سيئ
            self._reply(500, {"error": f"خطأ داخلي: {exc}"})

    def do_POST(self) -> None:
        try:
            body = self._read_body()
            if self.path == "/api/v1/accounts":
                # التسجيل بوابة الانضمام — مفتوحة، والجسم نفسه يحمل المفتاح العام
                data = self._json(body)
                result = self.service.register(str(data["pubkey"]), int(data["daily_cap"]))
            elif self.path == "/api/v1/cash-in":
                device = self._authenticate(self.path, body)
                data = self._json(body)
                if str(data["device_id"]) != device:
                    self._reply(403, {"error": "تمويل حساب جهاز آخر غير مسموح"})
                    return
                result = self.service.cash_in(
                    str(data["device_id"]), int(data["amount"]), str(data["reference"])
                )
            elif self.path == "/api/v1/settlements":
                self._authenticate(self.path, body)  # يكفي أن يكون المُرسِل جهازاً مسجلاً
                data = self._json(body)
                result = self.service.settle(
                    str(data["batch_id"]),
                    list(data["tokens"]),
                    now=int(data["now"]) if data.get("now") else None,
                )
            else:
                self._reply(404, {"error": "مسار غير معروف"})
                return
            self._reply(200, result)
        except Unauthorized as exc:
            self._reply(401, {"error": str(exc)})
        except (KeyError, ValueError, TypeError, json.JSONDecodeError) as exc:
            self._reply(400, {"error": f"طلب غير صالح: {exc}"})
        except Exception as exc:
            self._reply(500, {"error": f"خطأ داخلي: {exc}"})


class BankakSandbox:
    """يدير دورة حياة الخادم — للاختبارات والعرض الحي."""

    def __init__(self, db_path: str = ":memory:", port: int = 0):
        self.service = GatewayService(db_path)
        handler = type("BoundHandler", (_Handler,), {"service": self.service})
        self._server = ThreadingHTTPServer(("127.0.0.1", port), handler)
        self.port = self._server.server_address[1]
        self.base_url = f"http://127.0.0.1:{self.port}"
        self._thread: threading.Thread | None = None

    def start(self) -> "BankakSandbox":
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        if self._thread:
            self._thread.join(timeout=5)
        self.service.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="بيئة اختبار بنكك المحاكية")
    parser.add_argument("--port", type=int, default=8980)
    parser.add_argument("--db", default="wasla-sandbox.db", help="ملف SQLite المعمّر")
    args = parser.parse_args()
    sandbox = BankakSandbox(db_path=args.db, port=args.port).start()
    print(f"بيئة اختبار بنكك تعمل على {sandbox.base_url} — قاعدة البيانات: {args.db}")
    print("أوقفها بـ Ctrl+C")
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        sandbox.stop()


if __name__ == "__main__":
    main()
