"""بوابة محلية بعقد دوال Supabase الطرفية نفسه — للتحقق التكاملي.

تطبّق POST ‎/functions/v1/register و/settle فوق Postgres محلي يشغّل
هجرات وصلة الحقيقية (settle_accept/renew_reservation)، مع تحقق توقيع
Ed25519 عبر نواة الـPoC المصادَق عليها. الغرض: إثبات عقد عميل التطبيق
(HttpSettlementApi) ضد SQL الفعلي قبل أي نشر سحابي — ليست للإنتاج.

التشغيل:
    PGHOST=/var/lib/postgresql/wasla_pg/sock PGPORT=5544 PGUSER=wasla \
    PGDATABASE=wasla_e2e python3 supabase/tests/local_gateway.py 8899
"""

from __future__ import annotations

import json
import os
import re
import secrets
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from token_engine.crypto import sha256_hex  # noqa: E402
from token_engine.token import SignedToken  # noqa: E402

HEX = {16: re.compile(r"^[0-9a-f]{16}$"), 32: re.compile(r"^[0-9a-f]{32}$"),
       64: re.compile(r"^[0-9a-f]{64}$"), 128: re.compile(r"^[0-9a-f]{128}$")}
CURRENCY = re.compile(r"^[A-Z]{3}$")


def psql(sql: str) -> str:
    """تنفيذ SQL وإرجاع الناتج نصاً. القيم تُدرج بعد تحقق صارم بالأنماط
    أعلاه (hex/أعداد فقط) فلا مسار حقن."""
    out = subprocess.run(
        ["psql", "-qtA", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def wallet_snapshot(device_id: str) -> dict:
    row = psql(f"""
        select coalesce((select balance from accounts where device_id='{device_id}'),0),
               coalesce((select frozen  from accounts where device_id='{device_id}'),false),
               coalesce(r.epoch,0), coalesce(r.remaining,0),
               coalesce(r.daily_cap,500000), coalesce(r.chain_anchor,'')
        from (select 1) _
        left join reservations r
          on r.device_id='{device_id}' and r.status='open'
    """)
    balance, frozen, epoch, remaining, cap, anchor = row.split("|")
    return {
        "balance": int(balance), "frozen": frozen == "t",
        "epoch": int(epoch), "remaining": int(remaining),
        "daily_cap": int(cap), "chain_anchor": anchor,
    }


def handle_register(body: dict) -> dict:
    pubkey = body.get("pubkey", "")
    if not HEX[64].match(pubkey):
        raise ValueError("مفتاح عام غير صالح")
    derived = sha256_hex(bytes.fromhex(pubkey))[:16]
    if derived != body.get("device_id"):
        raise ValueError("المعرّف لا يطابق المفتاح العام")
    reserve = int(body.get("reserve", 500000))
    cap = int(body.get("daily_cap", 500000))
    existing = psql(f"select pubkey from accounts where device_id='{derived}'")
    if not existing:
        psql(f"insert into accounts (device_id, pubkey) values ('{derived}','{pubkey}')")
    elif existing != pubkey:
        raise ValueError("الجهاز مسجّل بمفتاح مختلف")
    has_open = psql(
        f"select 1 from reservations where device_id='{derived}' and status='open'")
    if not has_open:
        anchor = sha256_hex(f"anchor:{derived}:0:{secrets.token_hex(8)}".encode())
        psql(f"""insert into reservations
                 (device_id, epoch, reserved, remaining, daily_cap, chain_anchor)
                 values ('{derived}',0,{reserve},{reserve},{cap},'{anchor}')""")
    return {"wallet": wallet_snapshot(derived)}


def _validate_token(t: dict) -> str | None:
    checks = [
        HEX[32].match(str(t.get("token_id", ""))),
        HEX[16].match(str(t.get("sender_id", ""))),
        HEX[64].match(str(t.get("sender_pubkey", ""))),
        HEX[16].match(str(t.get("recipient_id", ""))),
        HEX[64].match(str(t.get("prev_hash", ""))),
        HEX[128].match(str(t.get("signature", ""))),
        CURRENCY.match(str(t.get("currency", ""))),
        isinstance(t.get("amount"), int) and t["amount"] > 0,
        isinstance(t.get("seq"), int) and t["seq"] >= 0,
        isinstance(t.get("issued_at"), int),
        isinstance(t.get("expires_at"), int),
    ]
    return None if all(checks) else "malformed"


def handle_settle(body: dict) -> dict:
    now = int(body.get("now") or time.time())
    results = []
    for wire in body.get("batch", []):
        reason = _validate_token(wire)
        if reason:
            results.append({"token_id": wire.get("token_id", "?"), "status": reason})
            continue
        token = SignedToken(**{k: wire[k] for k in (
            "token_id", "sender_id", "sender_pubkey", "recipient_id", "amount",
            "currency", "seq", "prev_hash", "issued_at", "expires_at", "signature")})
        try:
            token.verify()
        except Exception:
            results.append({"token_id": token.token_id, "status": "bad_signature"})
            continue
        if now > token.expires_at:
            results.append({"token_id": token.token_id, "status": "expired"})
            continue
        day = time.strftime("%Y-%m-%d", time.gmtime(token.issued_at))
        status = psql(f"""select settle_accept(
            '{token.token_id}','{token.sender_id}','{token.recipient_id}',
            {token.amount},'{token.currency}',{token.seq},
            '{token.prev_hash}','{token.token_hash}','{day}')""")
        results.append({"token_id": token.token_id, "status": status})

    response: dict = {
        "settled": sum(1 for r in results if r["status"] == "settled"),
        "rejected": [r for r in results
                     if r["status"] not in ("settled", "duplicate")],
        "frozen": [],
        "results": results,
    }
    device_id = body.get("device_id")
    if device_id and HEX[16].match(device_id):
        sent_ids = {w.get("token_id") for w in body.get("batch", [])
                    if w.get("sender_id") == device_id}
        sent_stuck = any(r["token_id"] in sent_ids and
                         r["status"] not in ("settled", "duplicate")
                         for r in results)
        if body.get("renew") and not sent_stuck:
            anchor = sha256_hex(
                f"anchor:{device_id}:renew:{secrets.token_hex(8)}".encode())
            psql(f"select renew_reservation('{device_id}','{anchor}',0)")
        response["wallet"] = wallet_snapshot(device_id)
    return response


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802
        length = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
            if self.path.endswith("/register"):
                payload, code = handle_register(body), 200
            elif self.path.endswith("/settle"):
                payload, code = handle_settle(body), 200
            else:
                payload, code = {"error": "مسار مجهول"}, 404
        except Exception as e:  # noqa: BLE001 — عقد الخطأ نص واحد
            payload, code = {"error": str(e)}, 400
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):  # صمت في الاختبارات
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    print(f"بوابة وصلة المحلية على http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
