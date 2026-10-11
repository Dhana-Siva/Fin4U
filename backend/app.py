"""Receipt-parsing backend: one job -- turn a photo of a receipt into
structured line items using Claude's vision, so the app can let the user
split them.

Deliberately stateless. The image is read into memory, sent to Anthropic,
and discarded; nothing about the receipt is written to disk, a database,
or the logs. That keeps the privacy story simple (and true) for the
in-app disclosure and privacy policy: "your receipt photo is processed to
extract the items and is not stored."

Amounts are integer cents everywhere. Floating-point dollars drift (0.1 +
0.2 != 0.3), and the whole point of this app is shares that add up
exactly, so money never touches a float.
"""
import base64
import hmac
import logging
import os

import anthropic
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from pydantic import BaseModel

log = logging.getLogger("receipt-backend")

# Claude Opus 5.5 is the skill-recommended default; this is a plain env
# override so switching to a cheaper model for high volume is a config
# change, not a code change.
MODEL = os.environ.get("RECEIPT_MODEL", "claude-opus-5-5")

# The Anthropic API caps images at 5 MB; the app downsizes before upload,
# so anything bigger than this is a bug or abuse, not a real receipt.
MAX_IMAGE_BYTES = 5 * 1024 * 1024


# Fixed list so the app can colour-code and total by category without
# fuzzy matching free-text. Keep in sync with Category in the iOS app.
CATEGORIES = [
    "groceries", "dining", "transport", "shopping", "health",
    "entertainment", "utilities", "other",
]


class ReceiptParseError(Exception):
    """The model answered, but not with a usable receipt."""


SYSTEM_PROMPT = """You extract structured data from photos of purchase receipts (restaurants, groceries, retail, pharmacies).

Rules:
- Every amount is an integer number of cents (or the currency's smallest unit). $12.34 -> 1234.
- `items` is the list of purchased lines, in the order printed. Use the item name as printed, but drop pure product codes/SKUs and obvious noise.
- `line_total_cents` is what that line cost in total (price x quantity), not the unit price. For weighed goods ("1.23 lb @ 2.99/lb") use quantity 1 and the charged total.
- Discounts, coupons and promotions are their own items with a NEGATIVE `line_total_cents`.
- If a quantity is not stated, it is 1.
- `subtotal_cents`, `tax_cents`, `tip_cents`, `total_cents`: as printed. Sum multiple tax lines into `tax_cents`. Put service charges / gratuity in `tip_cents`. Use 0 for anything the receipt does not show -- never infer or compute these yourself.
- `currency` is the ISO 4217 code implied by the symbol/locale ("USD", "INR", ...); use "USD" if you genuinely cannot tell.
- `date` is YYYY-MM-DD, or an empty string if it is not legible.
- `category` is the single best fit for the whole receipt, chosen from the allowed values (supermarket -> groceries, restaurant/cafe/bar -> dining, fuel/rideshare/transit -> transport, pharmacy/clinic -> health, bills -> utilities, anything unclear -> other).
- Each item also has its own `category` from the same allowed values, because one receipt can mix kinds of purchase (a supermarket sells groceries but also vitamins, medicine or toiletries -> health; clothing or kitchenware -> shopping). Categorise each item by what it is. Most items on a receipt will match the receipt's `category`; only differ where the item clearly belongs elsewhere. Discount lines take the category of the item they discount, or the receipt's `category` if unclear.
- Never invent items. If a line is partly unreadable, include what you can read and add a short note to `notes`. Use `notes` for anything the user should double-check.
- If the image is not a receipt, set `is_receipt` to false and leave the other fields empty/zero."""

RECEIPT_SCHEMA = {
    "type": "object",
    "properties": {
        "is_receipt": {"type": "boolean"},
        "merchant": {"type": "string"},
        "date": {"type": "string"},
        "currency": {"type": "string"},
        "category": {"type": "string", "enum": CATEGORIES},
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "quantity": {"type": "integer"},
                    "line_total_cents": {"type": "integer"},
                    "category": {"type": "string", "enum": CATEGORIES},
                },
                "required": ["name", "quantity", "line_total_cents", "category"],
                "additionalProperties": False,
            },
        },
        "subtotal_cents": {"type": "integer"},
        "tax_cents": {"type": "integer"},
        "tip_cents": {"type": "integer"},
        "total_cents": {"type": "integer"},
        "notes": {"type": "array", "items": {"type": "string"}},
    },
    "required": [
        "is_receipt", "merchant", "date", "currency", "category", "items",
        "subtotal_cents", "tax_cents", "tip_cents", "total_cents", "notes",
    ],
    "additionalProperties": False,
}


class ReceiptItem(BaseModel):
    name: str
    quantity: int
    line_total_cents: int
    # Empty means "same as the receipt" -- the app falls back to that.
    category: str = ""


class ParsedReceipt(BaseModel):
    is_receipt: bool
    merchant: str
    date: str
    currency: str
    category: str
    items: list[ReceiptItem]
    subtotal_cents: int
    tax_cents: int
    tip_cents: int
    total_cents: int
    notes: list[str]


class ReceiptResponse(ParsedReceipt):
    # Computed here, never trusted from the model: lets the app tell the
    # user "these items don't add up to the printed subtotal -- something
    # was misread" instead of silently splitting a wrong number.
    items_total_cents: int
    reconciles: bool
    checks: list[str]


def _cents(value: int) -> str:
    sign = "-" if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 100}.{value % 100:02d}"


def reconcile(receipt: ParsedReceipt) -> tuple[int, list[str]]:
    """Returns (items_total_cents, human-readable problems). An empty
    problem list means the printed numbers agree with each other."""
    items_total = sum(item.line_total_cents for item in receipt.items)
    checks: list[str] = []

    if receipt.subtotal_cents > 0 and items_total != receipt.subtotal_cents:
        checks.append(
            f"The items add up to {_cents(items_total)} but the receipt's "
            f"subtotal is {_cents(receipt.subtotal_cents)}."
        )

    # Without a printed subtotal, fall back to the items themselves.
    base = receipt.subtotal_cents if receipt.subtotal_cents > 0 else items_total
    expected_total = base + receipt.tax_cents + receipt.tip_cents
    if receipt.total_cents > 0 and expected_total != receipt.total_cents:
        checks.append(
            f"Subtotal + tax + tip is {_cents(expected_total)} but the "
            f"receipt's total is {_cents(receipt.total_cents)}."
        )

    return items_total, checks


def sniff_media_type(data: bytes) -> str | None:
    """Trust the bytes, not the client-supplied Content-Type."""
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[:4] == b"GIF8":
        return "image/gif"
    return None


def get_client() -> anthropic.Anthropic:
    # Resolves credentials from the environment (ANTHROPIC_API_KEY, etc.).
    return anthropic.Anthropic()


def parse_receipt_image(image_bytes: bytes, media_type: str, client=None) -> ParsedReceipt:
    client = client or get_client()
    response = client.messages.create(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM_PROMPT,
        output_config={"format": {"type": "json_schema", "schema": RECEIPT_SCHEMA}},
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": media_type,
                        "data": base64.standard_b64encode(image_bytes).decode("utf-8"),
                    },
                },
                {"type": "text", "text": "Extract this receipt."},
            ],
        }],
    )

    if response.stop_reason == "refusal":
        raise ReceiptParseError("The image couldn't be processed. Try retaking the photo.")
    if response.stop_reason == "max_tokens":
        raise ReceiptParseError("That receipt is too long to read in one go. Try scanning it in sections.")

    text = next((block.text for block in response.content if block.type == "text"), None)
    if not text:
        raise ReceiptParseError("Couldn't read that receipt. Try retaking the photo.")
    try:
        return ParsedReceipt.model_validate_json(text)
    except ValueError as exc:
        # Log the failure class only -- the text is receipt content.
        log.error("Model returned unparseable receipt JSON (%s)", type(exc).__name__)
        raise ReceiptParseError("Couldn't read that receipt. Try retaking the photo.") from exc


app = FastAPI(title="Receipt parsing backend")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/v1/parse-receipt", response_model=ReceiptResponse)
def parse_receipt(
    image: UploadFile = File(...),
    x_app_key: str | None = Header(default=None),
) -> ReceiptResponse:
    # Every request here spends real money, so the endpoint fails closed:
    # no configured key means nothing is served. A key shipped inside an
    # app is deterrence, not real security (App Attest / per-device
    # tokens are the proper upgrade) -- but it stops casual abuse.
    expected_key = os.environ.get("APP_API_KEY")
    if not expected_key:
        raise HTTPException(status_code=503, detail="Server is not configured.")
    if not x_app_key or not hmac.compare_digest(x_app_key, expected_key):
        raise HTTPException(status_code=401, detail="Unauthorized.")

    data = image.file.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image is too large (5 MB max).")
    media_type = sniff_media_type(data)
    if media_type is None:
        raise HTTPException(
            status_code=415,
            detail="Unsupported image. Send a JPEG, PNG, WebP or GIF.",
        )

    try:
        parsed = parse_receipt_image(data, media_type)
    except ReceiptParseError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except anthropic.RateLimitError as exc:
        raise HTTPException(status_code=503, detail="Busy right now. Try again in a moment.") from exc
    except anthropic.APIError as exc:
        # Class name only: exception text can echo request details.
        log.error("Anthropic call failed (%s)", type(exc).__name__)
        raise HTTPException(status_code=502, detail="Couldn't reach the receipt reader. Try again.") from exc

    if not parsed.is_receipt:
        raise HTTPException(status_code=422, detail="That doesn't look like a receipt.")

    items_total, checks = reconcile(parsed)
    return ReceiptResponse(
        **parsed.model_dump(),
        items_total_cents=items_total,
        reconciles=not checks,
        checks=checks,
    )
