import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

import app as backend

JPEG = b"\xff\xd8\xff\xe0" + b"fake-jpeg-bytes" * 4
PNG = b"\x89PNG\r\n\x1a\n" + b"fake-png-bytes" * 4
KEY = "test-app-key"


def receipt_json(**overrides) -> str:
    base = {
        "is_receipt": True,
        "merchant": "Corner Cafe",
        "date": "2026-10-03",
        "currency": "USD",
        "items": [
            {"name": "Latte", "quantity": 2, "line_total_cents": 900},
            {"name": "Bagel", "quantity": 1, "line_total_cents": 350},
        ],
        "subtotal_cents": 1250,
        "tax_cents": 100,
        "tip_cents": 200,
        "total_cents": 1550,
        "notes": [],
    }
    base.update(overrides)
    return json.dumps(base)


class FakeMessages:
    def __init__(self, text=None, stop_reason="end_turn"):
        self.text = text
        self.stop_reason = stop_reason
        self.calls = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        content = [SimpleNamespace(type="text", text=self.text)] if self.text is not None else []
        return SimpleNamespace(stop_reason=self.stop_reason, content=content)


class FakeClient:
    def __init__(self, **kwargs):
        self.messages = FakeMessages(**kwargs)


@pytest.fixture(autouse=True)
def configured(monkeypatch):
    monkeypatch.setenv("APP_API_KEY", KEY)


@pytest.fixture
def client():
    return TestClient(backend.app)


def use_fake(monkeypatch, **kwargs) -> FakeClient:
    fake = FakeClient(**kwargs)
    monkeypatch.setattr(backend, "get_client", lambda: fake)
    return fake


def post(client, data=JPEG, key=KEY, filename="receipt.jpg"):
    headers = {"X-App-Key": key} if key is not None else {}
    return client.post("/v1/parse-receipt", files={"image": (filename, data)}, headers=headers)


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_parses_and_reconciles(client, monkeypatch):
    fake = use_fake(monkeypatch, text=receipt_json())
    res = post(client)
    assert res.status_code == 200
    body = res.json()
    assert body["merchant"] == "Corner Cafe"
    assert [i["name"] for i in body["items"]] == ["Latte", "Bagel"]
    assert body["items_total_cents"] == 1250
    assert body["reconciles"] is True
    assert body["checks"] == []

    # The request actually carries the image and the schema constraint.
    call = fake.messages.calls[0]
    assert call["output_config"]["format"]["type"] == "json_schema"
    image_block = call["messages"][0]["content"][0]
    assert image_block["source"]["media_type"] == "image/jpeg"


def test_sniffs_media_type_from_bytes_not_filename(client, monkeypatch):
    fake = use_fake(monkeypatch, text=receipt_json())
    res = post(client, data=PNG, filename="actually-a-png.jpg")
    assert res.status_code == 200
    assert fake.messages.calls[0]["messages"][0]["content"][0]["source"]["media_type"] == "image/png"


def test_flags_items_that_do_not_match_subtotal(client, monkeypatch):
    # A misread price: items total 1200 but the printed subtotal is 1250.
    items = [
        {"name": "Latte", "quantity": 2, "line_total_cents": 850},
        {"name": "Bagel", "quantity": 1, "line_total_cents": 350},
    ]
    use_fake(monkeypatch, text=receipt_json(items=items))
    body = post(client).json()
    assert body["reconciles"] is False
    assert body["items_total_cents"] == 1200
    assert "12.00" in body["checks"][0] and "12.50" in body["checks"][0]


def test_flags_total_mismatch(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json(total_cents=1600))
    body = post(client).json()
    assert body["reconciles"] is False
    assert any("15.50" in c and "16.00" in c for c in body["checks"])


def test_discount_lines_reduce_items_total(client, monkeypatch):
    items = [
        {"name": "Pasta", "quantity": 1, "line_total_cents": 1800},
        {"name": "Coupon", "quantity": 1, "line_total_cents": -300},
    ]
    use_fake(monkeypatch, text=receipt_json(items=items, subtotal_cents=1500, tax_cents=0, tip_cents=0, total_cents=1500))
    body = post(client).json()
    assert body["items_total_cents"] == 1500
    assert body["reconciles"] is True


def test_missing_subtotal_falls_back_to_items(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json(subtotal_cents=0, total_cents=1550))
    assert post(client).json()["reconciles"] is True  # 1250 items + 100 + 200


def test_rejects_missing_or_wrong_key(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json())
    assert post(client, key=None).status_code == 401
    assert post(client, key="wrong").status_code == 401


def test_fails_closed_when_server_has_no_key(client, monkeypatch):
    monkeypatch.delenv("APP_API_KEY")
    use_fake(monkeypatch, text=receipt_json())
    assert post(client).status_code == 503


def test_rejects_non_image_bytes(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json())
    assert post(client, data=b"%PDF-1.7 not an image").status_code == 415


def test_rejects_oversized_image(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json())
    big = b"\xff\xd8\xff" + b"0" * (backend.MAX_IMAGE_BYTES + 10)
    assert post(client, data=big).status_code == 413


def test_not_a_receipt(client, monkeypatch):
    use_fake(monkeypatch, text=receipt_json(is_receipt=False, items=[], merchant=""))
    res = post(client)
    assert res.status_code == 422
    assert "receipt" in res.json()["detail"].lower()


def test_refusal_is_a_clean_error(client, monkeypatch):
    use_fake(monkeypatch, text=None, stop_reason="refusal")
    assert post(client).status_code == 422


def test_truncated_output_is_a_clean_error(client, monkeypatch):
    use_fake(monkeypatch, text="{", stop_reason="max_tokens")
    res = post(client)
    assert res.status_code == 422
    assert "too long" in res.json()["detail"]


def test_garbage_model_output_is_a_clean_error(client, monkeypatch):
    use_fake(monkeypatch, text="definitely not json")
    assert post(client).status_code == 422
