#!/usr/bin/env python3
"""Try the receipt parser on a real photo, no server or app needed.

    export ANTHROPIC_API_KEY=sk-ant-...        # or run `ant auth login`
    python3 try_receipt.py ~/Desktop/receipt.jpg

This is the actual accuracy test for the riskiest part of the app: does
Claude itemize *your* real receipts correctly? Try a few -- a restaurant
bill, a grocery run with discounts, something crumpled or photographed at
an angle. The "checks" at the bottom are the same reconciliation the app
will use to warn you when something was misread.

iPhone photos are often HEIC and several MB; if the file isn't a supported
format or is too big, this converts a temporary JPEG copy with macOS's
built-in `sips` (the original is never touched).
"""
import os
import subprocess
import sys
import tempfile

import anthropic

import app as backend


def load_image(path: str) -> tuple[bytes, str]:
    with open(path, "rb") as f:
        data = f.read()
    media_type = backend.sniff_media_type(data)
    if media_type and len(data) <= backend.MAX_IMAGE_BYTES:
        return data, media_type

    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "receipt.jpg")
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-Z", "2000", path, "--out", out],
            check=True, capture_output=True,
        )
        with open(out, "rb") as f:
            return f.read(), "image/jpeg"


def dollars(cents: int) -> str:
    return backend._cents(cents)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    data, media_type = load_image(sys.argv[1])
    try:
        receipt = backend.parse_receipt_image(data, media_type)
    except backend.ReceiptParseError as exc:
        print(f"Couldn't parse: {exc}")
        return 1
    except (anthropic.AuthenticationError, TypeError) as exc:
        print("No usable Anthropic credentials. Set ANTHROPIC_API_KEY or run `ant auth login`.")
        print(f"({type(exc).__name__})")
        return 1

    if not receipt.is_receipt:
        print("That doesn't look like a receipt.")
        return 1

    items_total, checks = backend.reconcile(receipt)
    print(f"\n{receipt.merchant or '(unknown merchant)'}   {receipt.date or '(no date)'}   [{receipt.currency}]\n")
    width = max((len(i.name) for i in receipt.items), default=10)
    for item in receipt.items:
        qty = f"x{item.quantity}" if item.quantity != 1 else "  "
        print(f"  {item.name:<{width}}  {qty:>3}  {dollars(item.line_total_cents):>9}")
    print(f"\n  {'Items total':<{width}}       {dollars(items_total):>9}")
    for label, value in [("Subtotal", receipt.subtotal_cents), ("Tax", receipt.tax_cents),
                         ("Tip / service", receipt.tip_cents), ("Total", receipt.total_cents)]:
        print(f"  {label:<{width}}       {dollars(value):>9}")

    print()
    if checks:
        print("CHECKS (something may have been misread):")
        for c in checks:
            print(f"  - {c}")
    else:
        print("Checks: everything adds up.")
    for note in receipt.notes:
        print(f"Note: {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
