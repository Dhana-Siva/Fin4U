"""Local stand-in for the model, for exercising the iOS app end to end
without an Anthropic key or any API spend.

    uvicorn dev_mock_server:app --port 8000

The real endpoint code runs (auth, image sniffing, size limits,
reconciliation) -- only the model call is faked. Set MOCK_MISMATCH=1 to
return a receipt whose items don't add up to its subtotal, to see the
app's "something may have been misread" warning.
"""
import os
import time

os.environ.setdefault("APP_API_KEY", "dev-key")

import app as backend  # noqa: E402
from app import app  # noqa: E402,F401  (re-exported for uvicorn)

ITEMS = [
    backend.ReceiptItem(name="Organic Bananas", quantity=1, line_total_cents=189),
    backend.ReceiptItem(name="Whole Milk 1 gal", quantity=1, line_total_cents=429),
    backend.ReceiptItem(name="Sourdough Bread", quantity=1, line_total_cents=599),
    backend.ReceiptItem(name="Chicken Breast", quantity=1, line_total_cents=1124),
    backend.ReceiptItem(name="Pasta Sauce", quantity=2, line_total_cents=698),
    backend.ReceiptItem(name="Member Discount", quantity=1, line_total_cents=-150),
]


def fake_parse(image_bytes: bytes, media_type: str, client=None) -> backend.ParsedReceipt:
    time.sleep(1.5)  # long enough to see the loading state
    items_total = sum(i.line_total_cents for i in ITEMS)
    subtotal = items_total + (200 if os.environ.get("MOCK_MISMATCH") else 0)
    tax = 178
    return backend.ParsedReceipt(
        is_receipt=True,
        merchant="Green Valley Market",
        date="2026-10-09",
        currency="USD",
        category="groceries",
        items=ITEMS,
        subtotal_cents=subtotal,
        tax_cents=tax,
        tip_cents=0,
        total_cents=subtotal + tax,
        notes=["Mock data - no model was called."],
    )


backend.parse_receipt_image = fake_parse
