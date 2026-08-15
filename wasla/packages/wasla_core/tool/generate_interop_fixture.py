"""توليد بذرة التوافق المتبادل من برهان المفهوم Python.

يعاد تشغيله فقط عند تغيير بنية التوكن (مع رفع إصدار البروتوكول):
    cd wasla && python3 packages/wasla_core/tool/generate_interop_fixture.py

Ed25519 حتمي: نفس البذرة والحمولة ← نفس التوقيع بالبايت، فتثبت البذرة
أن wasla_core (Dart) مكافئ بايتاً-ببايت لنواة الـPoC المصادَق عليها.
"""

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[3]))

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from token_engine.crypto import DeviceKeys, canonical_json, sha256_hex
from token_engine.token import SignedToken

SEED = bytes(range(32))  # بذرة حتمية للاختبار فقط — ليست مفتاحاً حقيقياً
FIXED_TOKEN_ID = "00112233445566778899aabbccddeeff"


def main() -> None:
    keys = DeviceKeys(Ed25519PrivateKey.from_private_bytes(SEED))
    anchor = sha256_hex(b"wasla-interop-anchor")
    token = SignedToken.create(
        keys=keys, recipient_id="aabbccddeeff0011", amount=35000,
        seq=0, prev_hash=anchor, issued_at=1750000000, ttl_seconds=72 * 3600,
    )
    payload = {**token.payload(), "token_id": FIXED_TOKEN_ID}
    signature = keys.sign(canonical_json(payload))
    fixed = SignedToken(**payload, signature=signature)
    fixed.verify()

    fixture = {
        "seed_hex": SEED.hex(),
        "device_id": keys.device_id,
        "public_key_hex": keys.public_key_hex,
        "canonical_payload": canonical_json(payload).decode(),
        "token": fixed.to_dict(),
        "token_hash": fixed.token_hash,
    }
    out = pathlib.Path(__file__).resolve().parents[1] / "test" / "interop_fixture.json"
    out.write_text(json.dumps(fixture, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"كُتبت البذرة إلى {out}")


if __name__ == "__main__":
    main()
