"""التطبيق المبسط: العرض الحي للبوابة الثانية + دورة CLI كاملة."""

import pytest

from app.demo import run_demo
from gateway.sandbox import BankakSandbox


class TestGate2Demo:
    def test_demo_full_offline_transfer_and_settlement(self, tmp_path):
        """مُخرج البوابة الثانية: تحويل أوف لاين كامل بين جهازين وتسويته
        عبر بيئة الاختبار — مع نجاة الحالة من إعادة تشغيل الخادم."""
        result = run_demo(verbose=False, db_path=str(tmp_path / "demo.db"))

        assert result["balances"]["البقّال"] == 35_000
        assert result["balances"]["الأخ"] == 20_000
        assert result["balances"]["الأم"] == 150_000 - 35_000 - 20_000
        assert result["reconciliation"]["balanced"] is True
        assert result["reconciliation"]["settled_tokens"] == 2
        assert result["sms_segments"] >= 2  # التوكن لا يتسع في رسالة واحدة
        assert result["qr_payload_chars"] <= 271


class TestCli:
    def test_cli_full_cycle(self, tmp_path, monkeypatch, capsys):
        """انشئ → ارسل (QR) → استلم → سوّ → رصيد — عبر أوامر CLI الفعلية."""
        from app import cli

        box = BankakSandbox(db_path=str(tmp_path / "cli.db")).start()
        monkeypatch.setenv("WASLA_HOME", str(tmp_path / "home"))
        monkeypatch.setenv("WASLA_GATEWAY", box.base_url)
        try:
            cli.main(["انشئ", "--اسم", "ali", "--ايداع", "1500"])
            cli.main(["انشئ", "--اسم", "omer"])
            omer_id = cli.load_wallet("omer").device_id

            cli.main(["ارسل", "--من", "ali", "--الى", omer_id, "--مبلغ", "200.50", "--قناة", "qr"])
            payload = next(
                line.strip() for line in capsys.readouterr().out.splitlines()
                if line.strip().startswith("WSLQR1:")
            )
            cli.main(["استلم", "--اسم", "omer", "--حمولة", payload])
            cli.main(["سوّ", "--اسم", "ali"])
            cli.main(["سوّ", "--اسم", "omer"])

            cli.main(["رصيد", "--اسم", "omer"])
            out = capsys.readouterr().out
            assert "200.50" in out  # وصل المبلغ مسوّى
            from gateway.client import GatewayClient

            omer = cli.load_wallet("omer")  # عميل موقّع بمفتاح عمر
            client = GatewayClient(box.base_url, keys=omer.keys)
            assert client.balance(omer_id)["balance"] == 20_050
        finally:
            box.stop()

    def test_cli_sms_channel(self, tmp_path, monkeypatch, capsys):
        from app import cli

        box = BankakSandbox(db_path=str(tmp_path / "cli2.db")).start()
        monkeypatch.setenv("WASLA_HOME", str(tmp_path / "home2"))
        monkeypatch.setenv("WASLA_GATEWAY", box.base_url)
        try:
            cli.main(["انشئ", "--اسم", "sara", "--ايداع", "300"])
            cli.main(["انشئ", "--اسم", "hadi"])
            hadi_id = cli.load_wallet("hadi").device_id

            cli.main(["ارسل", "--من", "sara", "--الى", hadi_id, "--مبلغ", "75", "--قناة", "sms"])
            segments = [
                line.strip() for line in capsys.readouterr().out.splitlines()
                if line.strip().startswith("WSL1|")
            ]
            assert len(segments) >= 2
            args = ["استلم", "--اسم", "hadi"]
            for segment in segments:
                args += ["--مقطع", segment]
            cli.main(args)
            assert "التوقيع سليم" in capsys.readouterr().out
        finally:
            box.stop()

    def test_cli_refuses_overdraft(self, tmp_path, monkeypatch):
        from app import cli

        box = BankakSandbox(db_path=str(tmp_path / "cli3.db")).start()
        monkeypatch.setenv("WASLA_HOME", str(tmp_path / "home3"))
        monkeypatch.setenv("WASLA_GATEWAY", box.base_url)
        try:
            cli.main(["انشئ", "--اسم", "poor", "--ايداع", "10"])
            with pytest.raises(SystemExit):
                cli.main(["ارسل", "--من", "poor", "--الى", "00" * 8, "--مبلغ", "11"])
        finally:
            box.stop()
