"""طبقات النقل: الترميز الثنائي، مقاطع SMS، وحمولة QR — مع حالات التلف."""

import pytest

from settlement.engine import SettlementEngine
from token_engine.token import SignedToken, TokenError
from transport import SmsReassembler, qr_payload, read_qr_payload, to_sms_segments
from transport.codec import TOKEN_WIRE_SIZE, decode_token, encode_token

from .helpers import NOW, make_user


def sample_token() -> SignedToken:
    engine = SettlementEngine()
    sender = make_user(engine, balance=100_000)
    return sender.send("00ffaa0011bb22cc", 12_345, now=NOW)


class TestBinaryCodec:
    def test_roundtrip_preserves_token_and_signature(self):
        token = sample_token()
        wire = encode_token(token)
        assert len(wire) == TOKEN_WIRE_SIZE
        restored = decode_token(wire)
        assert restored == token
        restored.verify()  # التوقيع يصمد عبر الترميز — الحمولة أعيد بناؤها حرفياً

    def test_flipped_byte_breaks_signature(self):
        token = sample_token()
        wire = bytearray(encode_token(token))
        wire[60] ^= 0xFF  # قلب بايت داخل حقل المبلغ/الحمولة
        from token_engine.errors import InvalidSignature

        with pytest.raises((InvalidSignature, TokenError)):
            decode_token(bytes(wire)).verify()

    def test_garbage_rejected(self):
        with pytest.raises(TokenError):
            decode_token(b"\x00" * 10)
        with pytest.raises(TokenError):
            decode_token(b"\x00" * TOKEN_WIRE_SIZE)  # ترويسة غير معروفة


class TestSmsPath:
    def test_segments_fit_sms_and_roundtrip_any_order(self):
        token = sample_token()
        segments = to_sms_segments(token)
        assert all(len(s) <= 153 for s in segments)  # سعة المقطع المتسلسل GSM-7

        reassembler = SmsReassembler()
        result = None
        for segment in reversed(segments):  # وصول معكوس الترتيب
            result = reassembler.feed(segment)
        assert result == token
        result.verify()

    def test_duplicate_segment_harmless(self):
        token = sample_token()
        segments = to_sms_segments(token)
        reassembler = SmsReassembler()
        reassembler.feed(segments[0])
        reassembler.feed(segments[0])  # الشبكة كررت الرسالة
        result = None
        for segment in segments[1:]:
            result = reassembler.feed(segment)
        assert result == token

    def test_interleaved_transfers_reassembled_separately(self):
        """رسائل تحويلين متداخلتين تصل مختلطة — كلٌّ يكتمل على حدة."""
        engine = SettlementEngine()
        sender = make_user(engine, balance=100_000)
        token_a = sender.send("00ffaa0011bb22cc", 5_000, now=NOW)
        token_b = sender.send("00ffaa0011bb22cc", 7_000, now=NOW + 10)
        seg_a, seg_b = to_sms_segments(token_a), to_sms_segments(token_b)

        # تداخل كامل: مقطع من أ ثم مقطع من ب وهكذا
        interleaved = [s for pair in zip(seg_a, seg_b) for s in pair]
        interleaved += seg_a[len(seg_b):] + seg_b[len(seg_a):]

        reassembler = SmsReassembler()
        completed = []
        for segment in interleaved:
            done = reassembler.feed(segment)
            if done:
                completed.append(done)
        assert {t.token_id for t in completed} == {token_a.token_id, token_b.token_id}

    def test_corrupted_chunk_detected_before_signature_check(self):
        token = sample_token()
        segments = to_sms_segments(token)
        head, msg_id, pos, chunk = segments[-1].split("|", 3)
        bad_char = "B" if chunk[3] != "B" else "C"
        corrupted = f"{head}|{msg_id}|{pos}|{chunk[:3]}{bad_char}{chunk[4:]}"
        reassembler = SmsReassembler()
        for segment in segments[:-1]:
            reassembler.feed(segment)
        with pytest.raises(TokenError):
            reassembler.feed(corrupted)

    def test_missing_segment_reports_pending(self):
        token = sample_token()
        segments = to_sms_segments(token)
        reassembler = SmsReassembler()
        assert reassembler.feed(segments[0]) is None
        assert list(reassembler.pending().values()) == [f"1/{len(segments)}"]

    def test_malformed_segment_rejected(self):
        reassembler = SmsReassembler()
        for bad in ["hello", "WSL1|xx|abc|data", "WSL9|aa|1/1|data", "WSL1|aa|0/1|data"]:
            with pytest.raises(TokenError):
                reassembler.feed(bad)


class TestQrPath:
    def test_roundtrip(self):
        token = sample_token()
        payload = qr_payload(token)
        assert payload.startswith("WSLQR1:")
        restored = read_qr_payload(payload)
        assert restored == token
        restored.verify()

    def test_qr_payload_small_enough_for_low_density_qr(self):
        # ≤ 271 حرفاً يدخل في QR إصدار 10 بتصحيح أخطاء متوسط — كاميرات متواضعة
        assert len(qr_payload(sample_token())) <= 271

    def test_tampered_payload_rejected(self):
        payload = qr_payload(sample_token())
        with pytest.raises(TokenError):
            read_qr_payload("WSLQR1:!!!notbase64!!!")
        with pytest.raises(TokenError):
            read_qr_payload(payload[7:])  # بلا بادئة
