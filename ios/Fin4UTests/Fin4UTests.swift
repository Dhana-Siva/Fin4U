import XCTest
import UIKit
@testable import Fin4U

final class MoneyTests: XCTestCase {
    func testParsesWhatPeopleType() {
        XCTAssertEqual(Money.parseCents("12"), 1200)
        XCTAssertEqual(Money.parseCents("12.5"), 1250)
        XCTAssertEqual(Money.parseCents("12.50"), 1250)
        XCTAssertEqual(Money.parseCents(".99"), 99)
        XCTAssertEqual(Money.parseCents("1,234.56"), 123456)
        XCTAssertEqual(Money.parseCents(" 7.00 "), 700)
        XCTAssertEqual(Money.parseCents("0"), 0)
    }

    func testParsesNegativeDiscounts() {
        XCTAssertEqual(Money.parseCents("-1.50"), -150)
        XCTAssertEqual(Money.parseCents("-0.05"), -5)
    }

    func testRoundsHalfCentsInsteadOfDrifting() {
        // 0.1 + 0.2 style float errors can't happen: everything is Decimal.
        XCTAssertEqual(Money.parseCents("0.30"), 30)
        XCTAssertEqual(Money.parseCents("19.99"), 1999)
        XCTAssertEqual(Money.parseCents("1.005"), 101)
    }

    func testRejectsGarbage() {
        XCTAssertNil(Money.parseCents(""))
        XCTAssertNil(Money.parseCents("abc"))
        XCTAssertNil(Money.parseCents("12.3.4"))
        XCTAssertNil(Money.parseCents("-"))
    }

    func testPlainFormatting() {
        XCTAssertEqual(Money.plain(1234), "12.34")
        XCTAssertEqual(Money.plain(5), "0.05")
        XCTAssertEqual(Money.plain(0), "0.00")
        XCTAssertEqual(Money.plain(-150), "-1.50")
    }

    func testPlainAndParseRoundTrip() {
        for cents in [0, 1, 99, 100, 1999, 123456, -1, -150, -100000] {
            XCTAssertEqual(Money.parseCents(Money.plain(cents)), cents, "round trip of \(cents)")
        }
    }

    func testCurrencyFormatting() {
        XCTAssertEqual(Money.format(1234, currency: "USD").filter { $0.isNumber || $0 == "." }, "12.34")
        XCTAssertTrue(Money.format(1234, currency: "USD").contains("$"))
        XCTAssertTrue(Money.format(-150, currency: "USD").contains("1.50"))
        // An empty currency code falls back to USD rather than crashing.
        XCTAssertTrue(Money.format(100, currency: "").contains("$"))
    }
}

final class ReconciliationTests: XCTestCase {
    private func checks(items: Int, subtotal: Int, tax: Int = 0, tip: Int = 0, total: Int) -> [String] {
        Reconciliation.checks(itemsTotal: items, printedSubtotal: subtotal, tax: tax, tip: tip, printedTotal: total, currency: "USD")
    }

    func testAgreeingNumbersProduceNoProblems() {
        XCTAssertEqual(checks(items: 1250, subtotal: 1250, tax: 100, tip: 200, total: 1550), [])
    }

    func testItemsThatMissTheSubtotalAreFlagged() {
        let problems = checks(items: 1200, subtotal: 1250, tax: 100, tip: 200, total: 1550)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("12.00") && problems[0].contains("12.50"))
    }

    func testTotalThatDoesntAddUpIsFlagged() {
        let problems = checks(items: 1250, subtotal: 1250, tax: 100, tip: 200, total: 1600)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("15.50") && problems[0].contains("16.00"))
    }

    func testMissingSubtotalFallsBackToItems() {
        XCTAssertEqual(checks(items: 1250, subtotal: 0, tax: 100, tip: 200, total: 1550), [])
        XCTAssertEqual(checks(items: 1250, subtotal: 0, tax: 100, tip: 200, total: 1600).count, 1)
    }

    func testNothingPrintedMeansNothingToCheck() {
        XCTAssertEqual(checks(items: 999, subtotal: 0, total: 0), [])
    }

    func testBothProblemsCanFireTogether() {
        XCTAssertEqual(checks(items: 1000, subtotal: 1250, tax: 100, tip: 0, total: 1500).count, 2)
    }
}

final class ExpenseDraftTests: XCTestCase {
    func testTotalsAreAlwaysDerivedFromItems() {
        let draft = ExpenseDraft(
            items: [
                DraftItem(name: "Pasta", quantity: 1, cents: 1800),
                DraftItem(name: "Coupon", quantity: 1, cents: -300),
            ],
            taxCents: 120,
            tipCents: 200
        )
        XCTAssertEqual(draft.subtotalCents, 1500)
        XCTAssertEqual(draft.totalCents, 1820)

        draft.items.removeLast()
        XCTAssertEqual(draft.subtotalCents, 1800)
        XCTAssertEqual(draft.totalCents, 2120)
    }

    func testFixingAMisreadItemClearsTheWarning() {
        let draft = ExpenseDraft(
            items: [DraftItem(name: "Latte", quantity: 2, cents: 850), DraftItem(name: "Bagel", quantity: 1, cents: 350)],
            taxCents: 100,
            tipCents: 200,
            printedSubtotalCents: 1250,
            printedTotalCents: 1550
        )
        XCTAssertFalse(draft.checks.isEmpty)
        draft.items[0].cents = 900
        XCTAssertEqual(draft.checks, [])
    }

    func testCannotSaveAnEmptyExpense() {
        XCTAssertFalse(ExpenseDraft().canSave)
        XCTAssertTrue(ExpenseDraft(items: [DraftItem(name: "x", quantity: 1, cents: 100)]).canSave)
    }

    func testParsesBackendDates() throws {
        let date = try XCTUnwrap(ExpenseDraft.parseDate("2026-10-03"))
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 10, 3])
        XCTAssertNil(ExpenseDraft.parseDate(""))
        XCTAssertNil(ExpenseDraft.parseDate("last Tuesday"))
    }

    func testUnknownCategoryFallsBackToOther() {
        XCTAssertEqual(ExpenseCategory(raw: "groceries"), .groceries)
        XCTAssertEqual(ExpenseCategory(raw: "spaceships"), .other)
    }
}

/// The exact shape the backend returns (see backend/app.py ReceiptResponse),
/// including the extra fields the app deliberately ignores.
final class BackendContractTests: XCTestCase {
    private let json = """
    {
      "is_receipt": true,
      "merchant": "Green Valley Market",
      "date": "2026-10-09",
      "currency": "USD",
      "category": "groceries",
      "items": [
        {"name": "Whole Milk 1 gal", "quantity": 1, "line_total_cents": 429},
        {"name": "Pasta Sauce", "quantity": 2, "line_total_cents": 698}
      ],
      "subtotal_cents": 1127,
      "tax_cents": 90,
      "tip_cents": 0,
      "total_cents": 1217,
      "notes": ["Mock data"],
      "items_total_cents": 1127,
      "reconciles": true,
      "checks": []
    }
    """

    func testDecodesTheBackendResponse() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try decoder.decode(ParsedReceipt.self, from: Data(json.utf8))

        XCTAssertTrue(parsed.isReceipt)
        XCTAssertEqual(parsed.merchant, "Green Valley Market")
        XCTAssertEqual(parsed.items.map(\.lineTotalCents), [429, 698])
        XCTAssertEqual(parsed.items[1].quantity, 2)
        XCTAssertEqual(parsed.subtotalCents, 1127)
        XCTAssertEqual(parsed.totalCents, 1217)

        let draft = ExpenseDraft(parsed: parsed, image: nil)
        XCTAssertEqual(draft.category, .groceries)
        XCTAssertEqual(draft.subtotalCents, 1127)
        XCTAssertEqual(draft.totalCents, 1217)
        XCTAssertEqual(draft.checks, [])
    }

    func testBackendErrorMessagesReachTheUser() {
        let body = Data(#"{"detail": "That doesn't look like a receipt."}"#.utf8)
        XCTAssertEqual(ReceiptAPI.errorMessage(status: 422, data: body), "That doesn't look like a receipt.")
        XCTAssertTrue(ReceiptAPI.errorMessage(status: 401, data: body).contains("isn't set up"))
        XCTAssertTrue(ReceiptAPI.errorMessage(status: 500, data: Data("oops".utf8)).contains("500"))
    }
}

final class ImagePrepTests: XCTestCase {
    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testLargePhotosAreShrunkToTheMaxSide() throws {
        let data = try XCTUnwrap(ImagePrep.jpeg(from: solidImage(width: 4000, height: 3000)))
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(result.size.width, result.size.height) * result.scale, 2000, accuracy: 1)
        XCTAssertLessThanOrEqual(data.count, ImagePrep.maxBytes)
    }

    func testSmallImagesAreNotUpscaled() throws {
        let data = try XCTUnwrap(ImagePrep.jpeg(from: solidImage(width: 600, height: 800)))
        let result = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(result.size.height * result.scale, 800, accuracy: 1)
    }
}
