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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if not 0 < length <= MAX_BODY_BYTES:
            raise ValueError("حجم طلب غير مقبول")
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("جسم الطلب يجب أن يكون كائن JSON")
        return data

    def do_GET(self) -> None:
        try:
            match = re.fullmatch(r"/api/v1/balance/([0-9a-f]{16})", self.path)
            if match:
                self._reply(200, self.service.balance(match.group(1)))
            elif self.path == "/api/v1/reconciliation":
                self._reply(200, self.service.reconciliation())
            else:
                self._reply(404, {"error": "مسار غير معروف"})
        except KeyError as exc:
            self._reply(404, {"error": str(exc)})
        except Exception as exc:  # حافة الخادم: لا انهيار على طلب سيئ
            self._reply(500, {"error": f"خطأ داخلي: {exc}"})

    def do_POST(self) -> None:
        try:
            body = self._read_json()
            if self.path == "/api/v1/accounts":
                result = self.service.register(str(body["pubkey"]), int(body["daily_cap"]))
            elif self.path == "/api/v1/cash-in":
                result = self.service.cash_in(
                    str(body["device_id"]), int(body["amount"]), str(body["reference"])
                )
            elif self.path == "/api/v1/settlements":
                result = self.service.settle(
                    str(body["batch_id"]),
                    list(body["tokens"]),
                    now=int(body["now"]) if body.get("now") else None,
                )
            else:
                self._reply(404, {"error": "مسار غير معروف"})
                return
            self._reply(200, result)
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
