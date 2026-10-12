import XCTest
import UIKit
import SwiftData
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

final class ExpenseMathTests: XCTestCase {
    private let sam = Participant(id: "sam", name: "Sam")
    private let alex = Participant(id: "alex", name: "Alex")

    private func shared(with others: [Participant]) -> SplitPlan {
        SplitPlan(isShared: true, participants: others, customDefault: nil)
    }

    func testAllocationAlwaysAddsUpToTheTotal() {
        for total in [0, 1, 99, 100, 1001, 12_345, -150, -1] {
            for weights in [[1, 1], [1, 1, 1], [3334, 3333, 3333], [7000, 3000], [1, 0, 2]] {
                XCTAssertEqual(ExpenseMath.allocate(total, weights: weights).reduce(0, +), total,
                               "total \(total) weights \(weights)")
            }
        }
    }

    func testThreeWayEvenSplitGivesTheOddCentToTheFirstPerson() {
        let split = ExpenseMath.equalSplit([.me, sam, alex])
        XCTAssertEqual(split.map(\.basisPoints), [3334, 3333, 3333])
        XCTAssertEqual(split.reduce(0) { $0 + $1.basisPoints }, 10_000)
    }

    func testNormalizeDropsUnknownPeopleAndRescales() {
        let split = [
            ShareEntry(personID: "me", name: "You", basisPoints: 5000),
            ShareEntry(personID: "gone", name: "Gone", basisPoints: 3000),
            ShareEntry(personID: "sam", name: "Sam", basisPoints: 2000),
        ]
        let result = ExpenseMath.normalize(split, allowed: [.me, sam])
        XCTAssertEqual(result?.map(\.personID), ["me", "sam"])
        XCTAssertEqual(result?.reduce(0) { $0 + $1.basisPoints }, 10_000)
        XCTAssertNil(ExpenseMath.normalize(split, allowed: [alex]))
    }

    func testAnUnsharedExpenseIsEntirelyYours() {
        let plan = SplitPlan()
        let lines = [LineInput(cents: 1000, category: .groceries, override: nil)]
        let totals = ExpenseMath.personTotals(plan: plan, lines: lines, taxCents: 80, tipCents: 0)
        XCTAssertEqual(totals, [PersonTotal(id: "me", name: "You", cents: 1080)])
    }

    func testEvenSplitDividesItemsTaxAndTipAndAddsUp() {
        let lines = [
            LineInput(cents: 1001, category: .dining, override: nil),
            LineInput(cents: 500, category: .dining, override: nil),
        ]
        let totals = ExpenseMath.personTotals(plan: shared(with: [sam]), lines: lines, taxCents: 133, tipCents: 301)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cents }, 1001 + 500 + 133 + 301)
        XCTAssertEqual(totals.count, 2)
    }

    func testAnItemSplitOnlyWithSamIsNotChargedToYou() {
        let sharedOnly = [ShareEntry(personID: "sam", name: "Sam", basisPoints: 10_000)]
        let lines = [
            LineInput(cents: 1000, category: .groceries, override: nil),   // even: 500 / 500
            LineInput(cents: 600, category: .groceries, override: sharedOnly),  // all Sam
        ]
        let totals = ExpenseMath.personTotals(plan: shared(with: [sam]), lines: lines, taxCents: 0, tipCents: 0)
        XCTAssertEqual(totals.first { $0.id == "me" }?.cents, 500)
        XCTAssertEqual(totals.first { $0.id == "sam" }?.cents, 1100)
    }

    func testTaxFollowsWhoCarriesTheItems() {
        // You carry 25% of the items, so you carry 25% of the tax.
        let custom = [
            ShareEntry(personID: "me", name: "You", basisPoints: 2500),
            ShareEntry(personID: "sam", name: "Sam", basisPoints: 7500),
        ]
        let lines = [LineInput(cents: 2000, category: .dining, override: custom)]
        let totals = ExpenseMath.personTotals(plan: shared(with: [sam]), lines: lines, taxCents: 200, tipCents: 0)
        XCTAssertEqual(totals.first { $0.id == "me" }?.cents, 500 + 50)
        XCTAssertEqual(totals.first { $0.id == "sam" }?.cents, 1500 + 150)
    }

    func testTotalsStillAddUpWithADiscountLine() {
        let lines = [
            LineInput(cents: 1299, category: .health, override: nil),
            LineInput(cents: -150, category: .groceries, override: nil),
        ]
        let totals = ExpenseMath.personTotals(plan: shared(with: [sam, alex]), lines: lines, taxCents: 77, tipCents: 0)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cents }, 1299 - 150 + 77)
    }

    func testCategoryTotalsAddUpToYourTotalAndKeepMixedReceiptsApart() {
        let lines = [
            LineInput(cents: 3000, category: .groceries, override: nil),
            LineInput(cents: 1000, category: .health, override: nil),
        ]
        let byCategory = ExpenseMath.categoryTotals(
            for: "me", plan: SplitPlan(), lines: lines, taxCents: 400, tipCents: 0, receiptCategory: .groceries
        )
        XCTAssertEqual(byCategory.values.reduce(0, +), 4400)
        XCTAssertEqual(byCategory[.groceries], 3000 + 300)  // tax follows spend 3:1
        XCTAssertEqual(byCategory[.health], 1000 + 100)
    }

    func testOnlyYourShareReachesYourCategoryTotals() {
        let lines = [
            LineInput(cents: 2000, category: .groceries, override: nil),
            LineInput(cents: 1000, category: .health, override: [ShareEntry(personID: "sam", name: "Sam", basisPoints: 10_000)]),
        ]
        let mine = ExpenseMath.categoryTotals(
            for: "me", plan: shared(with: [sam]), lines: lines, taxCents: 0, tipCents: 0, receiptCategory: .groceries
        )
        XCTAssertEqual(mine, [.groceries: 1000])  // the health item was all Sam's
    }

    func testAReceiptWithOnlyATotalFallsBackToTheReceiptCategory() {
        let byCategory = ExpenseMath.categoryTotals(
            for: "me", plan: SplitPlan(), lines: [], taxCents: 0, tipCents: 2500, receiptCategory: .dining
        )
        XCTAssertEqual(byCategory, [.dining: 2500])
    }

    func testDescribeReadsNaturally() {
        XCTAssertEqual(ExpenseMath.describe(ExpenseMath.equalSplit([.me, sam])), "Even · You, Sam")
        XCTAssertEqual(ExpenseMath.describe([ShareEntry(personID: "sam", name: "Sam", basisPoints: 10_000)]), "Sam only")
        XCTAssertEqual(
            ExpenseMath.describe([
                ShareEntry(personID: "me", name: "You", basisPoints: 6000),
                ShareEntry(personID: "sam", name: "Sam", basisPoints: 4000),
            ]),
            "You 60% · Sam 40%"
        )
        XCTAssertEqual(ExpenseMath.percentText(3333), "33.33%")
    }

    func testChangingThePeopleResetsAHandEditedDefault() {
        var plan = shared(with: [sam])
        plan.customDefault = [ShareEntry(personID: "me", name: "You", basisPoints: 7000),
                              ShareEntry(personID: "sam", name: "Sam", basisPoints: 3000)]
        plan.toggle(alex)
        XCTAssertNil(plan.customDefault)
        XCTAssertEqual(plan.defaultSplit.map(\.basisPoints), [3334, 3333, 3333])
    }
}

final class ItemCategoryTests: XCTestCase {
    private func parsed(itemCategories: [String?]) throws -> ParsedReceipt {
        let items = itemCategories.enumerated().map { index, category in
            var item: [String: Any] = ["name": "Item \(index)", "quantity": 1, "line_total_cents": 100]
            if let category { item["category"] = category }
            return item
        }
        let json: [String: Any] = [
            "is_receipt": true, "merchant": "Shoprite", "date": "2026-10-09", "currency": "USD",
            "category": "groceries", "items": items, "subtotal_cents": 100 * items.count,
            "tax_cents": 0, "tip_cents": 0, "total_cents": 100 * items.count, "notes": [],
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ParsedReceipt.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testItemsKeepTheirOwnCategoryAndFallBackToTheReceipts() throws {
        let draft = ExpenseDraft(parsed: try parsed(itemCategories: ["health", nil, "", "dining"]), image: nil)
        XCTAssertEqual(draft.items.map(\.category), [.health, .groceries, .groceries, .dining])
    }

    func testChoosingAReceiptCategoryAppliesToEveryItem() throws {
        let draft = ExpenseDraft(parsed: try parsed(itemCategories: ["health", "groceries"]), image: nil)
        draft.setCategoryForAll(.shopping)
        XCTAssertEqual(draft.category, .shopping)
        XCTAssertEqual(draft.items.map(\.category), [.shopping, .shopping])
    }

    func testAnUnsharedDraftIsAllYours() throws {
        let draft = ExpenseDraft(parsed: try parsed(itemCategories: [nil, nil]), image: nil)
        XCTAssertEqual(draft.personTotals.map(\.cents), [draft.totalCents])
    }
}

final class OnePersonShareTests: XCTestCase {
    private let sam = Participant(id: "sam", name: "Sam")
    private let alex = Participant(id: "alex", name: "Alex")

    private func draft(sharedWith person: Participant? = nil) -> ExpenseDraft {
        let d = ExpenseDraft(items: [
            DraftItem(name: "Pizza", quantity: 1, cents: 2000, category: .dining),
            DraftItem(name: "Soda", quantity: 1, cents: 500, category: .dining),
        ], taxCents: 250)
        d.plan.isShared = true
        if let person { d.plan.selectOnly(person) }
        return d
    }

    func testPickingSomeoneElseReplacesThePerson() {
        var plan = SplitPlan(isShared: true)
        plan.selectOnly(sam)
        plan.selectOnly(alex)
        XCTAssertEqual(plan.participants, [alex])
        plan.selectOnly(alex)  // tapping the chosen person clears it
        XCTAssertNil(plan.other)
    }

    func testTwoWaySplitsAreClampedAndAddUp() {
        var plan = SplitPlan(isShared: true)
        plan.selectOnly(sam)
        XCTAssertEqual(plan.split(otherShare: 3000).map(\.basisPoints), [7000, 3000])
        XCTAssertEqual(plan.split(otherShare: 0).map(\.personID), ["me"])
        XCTAssertEqual(plan.split(otherShare: 10_000).map(\.personID), ["sam"])
        XCTAssertEqual(plan.split(otherShare: 25_000).map(\.personID), ["sam"])  // over 100% clamps
        XCTAssertEqual(plan.split(otherShare: -5).map(\.personID), ["me"])
    }

    func testEveryItemStartsAtFiftyPercent() {
        let d = draft(sharedWith: sam)
        XCTAssertEqual(d.defaultOtherShare, 5000)
        XCTAssertEqual(d.items.map { d.otherShare(of: $0) }, [5000, 5000])
    }

    func testChangingOneItemLeavesTheOthersAlone() {
        let d = draft(sharedWith: sam)
        d.setOtherShare(10_000, of: d.items[1].id)  // soda is all Sam's
        XCTAssertEqual(d.otherShare(of: d.items[0]), 5000)
        XCTAssertEqual(d.otherShare(of: d.items[1]), 10_000)
        let totals = d.personTotals
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cents }, d.totalCents)
        XCTAssertEqual(totals.first { $0.id == "me" }?.cents, 1000 + 100)  // half the pizza + 40% of the tax (1000 of 2500)
    }

    func testSettingAnItemBackToTheDefaultClearsItsOverride() {
        let d = draft(sharedWith: sam)
        d.setOtherShare(8000, of: d.items[0].id)
        XCTAssertNotNil(d.items[0].split)
        d.setOtherShare(5000, of: d.items[0].id)
        XCTAssertNil(d.items[0].split)
    }

    func testChangingTheDefaultMovesEveryItemWithoutAnOverride() {
        let d = draft(sharedWith: sam)
        d.setOtherShare(10_000, of: d.items[1].id)
        d.setDefaultOtherShare(2500)
        XCTAssertEqual(d.otherShare(of: d.items[0]), 2500)
        XCTAssertEqual(d.otherShare(of: d.items[1]), 10_000)  // kept its own
    }

    func testAnItemSplitShowsExactAmountsThatAddUp() {
        // $5.00 shared with Sam at 20% -> you $4.00, Sam $1.00.
        let d = ExpenseDraft(items: [DraftItem(name: "Snacks", quantity: 1, cents: 500, category: .groceries)])
        d.plan.isShared = true
        d.plan.selectOnly(sam)
        d.setOtherShare(2000, of: d.items[0].id)
        let amounts = d.amounts(of: d.items[0])
        XCTAssertEqual(amounts.you, 400)
        XCTAssertEqual(amounts.other, 100)
    }

    func testOddAmountsStillAddUpToTheItem() {
        let d = ExpenseDraft(items: [DraftItem(name: "Wrap", quantity: 1, cents: 333, category: .dining)])
        d.plan.isShared = true
        d.plan.selectOnly(sam)
        let amounts = d.amounts(of: d.items[0])  // 50% of $3.33
        XCTAssertEqual(amounts.you + amounts.other, 333)
        XCTAssertEqual(Set([amounts.you, amounts.other]), [166, 167])
    }

    func testSwitchingPeopleDropsTheOldOverrides() {
        let d = draft(sharedWith: sam)
        d.setOtherShare(8000, of: d.items[0].id)
        d.plan.selectOnly(alex)
        XCTAssertEqual(d.otherShare(of: d.items[0]), 5000)  // back to the default for Alex
    }
}

final class ItemizeTests: XCTestCase {
    private let sam = Participant(id: "sam", name: "Sam")

    private func draft() -> ExpenseDraft {
        let d = ExpenseDraft(items: [
            DraftItem(name: "Pizza", quantity: 1, cents: 2000, category: .dining),
            DraftItem(name: "My salad", quantity: 1, cents: 1000, category: .dining),
            DraftItem(name: "Soda", quantity: 1, cents: 500, category: .dining),
        ], taxCents: 350)
        d.plan.isShared = true
        d.plan.selectOnly(sam)
        return d
    }

    func testShareAllSharesEveryItemAtOnePercentage() {
        let d = draft()
        d.setDefaultOtherShare(2500)
        XCTAssertEqual(d.items.map { d.otherShare(of: $0) }, [2500, 2500, 2500])
    }

    func testItemizedItemsStartUnshared() {
        let d = draft()
        d.setItemize(true)
        XCTAssertEqual(d.items.map { d.isShared($0) }, [false, false, false])
        XCTAssertEqual(d.personTotals.first { $0.id == "sam" }?.cents, 0)
        XCTAssertEqual(d.personTotals.first { $0.id == "me" }?.cents, d.totalCents)
    }

    func testOnlyTheSharedItemsAreSplit() {
        let d = draft()
        d.setItemize(true)
        d.setItemShared(true, of: d.items[0].id)  // pizza, at the 50% default
        XCTAssertTrue(d.isShared(d.items[0]))
        XCTAssertEqual(d.otherShare(of: d.items[0]), 5000)
        XCTAssertFalse(d.isShared(d.items[1]))
        let totals = d.personTotals
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cents }, d.totalCents)
        // Sam: half the pizza (1000) + tax in proportion (1000 of 3500 items x 350 = 100).
        XCTAssertEqual(totals.first { $0.id == "sam" }?.cents, 1100)
    }

    func testASharedItemKeepsItsOwnPercentageEvenIfItMatchesTheDefault() {
        let d = draft()
        d.setItemize(true)
        d.setItemShared(true, of: d.items[0].id)
        d.setOtherShare(5000, of: d.items[0].id)  // same as default, still shared
        XCTAssertTrue(d.isShared(d.items[0]))
        d.setOtherShare(2000, of: d.items[0].id)
        XCTAssertEqual(d.otherShare(of: d.items[0]), 2000)
    }

    func testTurningAnItemOffMakesItAllYours() {
        let d = draft()
        d.setItemize(true)
        d.setItemShared(true, of: d.items[2].id)
        d.setItemShared(false, of: d.items[2].id)
        XCTAssertFalse(d.isShared(d.items[2]))
        XCTAssertEqual(d.amounts(of: d.items[2]).you, 500)
    }

    func testReturningToShareAllClearsPerItemChoices() {
        let d = draft()
        d.setItemize(true)
        d.setItemShared(true, of: d.items[0].id)
        d.setItemize(false)
        XCTAssertTrue(d.items.allSatisfy { $0.split == nil })
        XCTAssertEqual(d.items.map { d.otherShare(of: $0) }, [5000, 5000, 5000])
    }

    func testItemizeSurvivesSavingAsASnapshot() throws {
        var plan = SplitPlan(isShared: true, participants: [sam])
        plan.itemize = true
        let data = try JSONEncoder().encode(SplitSnapshot(participants: plan.participants, defaultSplit: nil, itemize: plan.itemize))
        let back = try JSONDecoder().decode(SplitSnapshot.self, from: data)
        XCTAssertEqual(back.itemize, true)
        // An expense saved before this existed has no `itemize` key at all.
        let old = try JSONDecoder().decode(SplitSnapshot.self, from: Data(#"{"participants":[],"defaultSplit":null}"#.utf8))
        XCTAssertNil(old.itemize)
    }
}

final class SpendStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func spend(_ y: Int, _ m: Int, _ d: Int, _ cents: Int, _ category: ExpenseCategory = .groceries,
                       currency: String = "USD", hour: Int = 12) -> Spend {
        Spend(date: date(y, m, d, hour: hour), currency: currency, cents: cents, categories: [category: cents])
    }

    func testMonthlyTotalsGroupByMonthAndIgnoreOtherYears() {
        let spends = [spend(2026, 10, 3, 1000), spend(2026, 10, 20, 500), spend(2026, 1, 5, 700), spend(2025, 10, 9, 9999)]
        let months = SpendStats.monthlyTotals(spends, year: 2026, currency: "USD", calendar: calendar)
        XCTAssertEqual(months, [10: 1500, 1: 700])
    }

    func testDailyTotalsMergeSameDayAcrossTimesAndSortNewestFirst() {
        let spends = [
            spend(2026, 10, 9, 1000, hour: 8), spend(2026, 10, 9, 250, hour: 21),
            spend(2026, 10, 2, 400),
        ]
        let days = SpendStats.dailyTotals(spends, currency: "USD", calendar: calendar)
        XCTAssertEqual(days.map(\.cents), [1250, 400])
        XCTAssertEqual(days.map(\.count), [2, 1])
        XCTAssertEqual(days.first?.day, calendar.startOfDay(for: date(2026, 10, 9)))
    }

    func testCurrenciesAreNeverAddedTogether() {
        let spends = [spend(2026, 10, 1, 1000), spend(2026, 10, 2, 99_900, currency: "INR")]
        XCTAssertEqual(SpendStats.primaryCurrency(spends), "INR")
        XCTAssertEqual(SpendStats.total(spends, currency: "USD"), 1000)
        XCTAssertEqual(SpendStats.otherCurrencies(spends, besides: "USD").map(\.currency), ["INR"])
    }

    func testCategoryTotalsAddUpAndSortBiggestFirst() {
        let spends = [spend(2026, 10, 1, 1000, .dining), spend(2026, 10, 2, 3000, .groceries), spend(2026, 10, 3, 500, .dining)]
        let totals = SpendStats.categoryTotals(spends, currency: "USD")
        XCTAssertEqual(totals.map(\.category), [.groceries, .dining])
        XCTAssertEqual(totals.map(\.cents), [3000, 1500])
    }

    func testYearsRunFromTheEarliestExpenseToNow() {
        let spends = [spend(2024, 5, 1, 100), spend(2026, 1, 1, 100)]
        XCTAssertEqual(SpendStats.years(spends, now: date(2026, 10, 11), calendar: calendar), 2024...2026)
        XCTAssertEqual(SpendStats.years([], now: date(2026, 10, 11), calendar: calendar), 2026...2026)
    }

    func testEmptyInputsGiveEmptyResults() {
        XCTAssertEqual(SpendStats.primaryCurrency([]), "USD")
        XCTAssertEqual(SpendStats.total([], currency: "USD"), 0)
        XCTAssertTrue(SpendStats.dailyTotals([], currency: "USD", calendar: calendar).isEmpty)
    }
}

final class OwedTests: XCTestCase {
    private let sam = Participant(id: "sam", name: "Sam")

    private func owed(_ id: String, _ name: String, _ cents: Int) -> PersonTotal { PersonTotal(id: id, name: name, cents: cents) }

    private func spend(_ cents: Int, owed: [PersonTotal], currency: String = "USD") -> Spend {
        Spend(date: Date(), currency: currency, cents: cents, categories: [:], owed: owed)
    }

    func testOwedAddsUpPerPersonAcrossExpenses() {
        let spends = [
            spend(500, owed: [owed("sam", "Sam", 500)]),
            spend(800, owed: [owed("sam", "Sam", 300), owed("daya", "Daya", 900)]),
            spend(100, owed: []),
        ]
        let totals = SpendStats.owed(spends, currency: "USD")
        XCTAssertEqual(totals.map(\.name), ["Daya", "Sam"])
        XCTAssertEqual(totals.map(\.cents), [900, 800])
        XCTAssertEqual(SpendStats.totalOwed(spends, currency: "USD"), 1700)
    }

    func testOwedInOtherCurrenciesIsNotMixedIn() {
        let spends = [spend(500, owed: [owed("sam", "Sam", 500)]), spend(500, owed: [owed("sam", "Sam", 9000)], currency: "INR")]
        XCTAssertEqual(SpendStats.totalOwed(spends, currency: "USD"), 500)
    }

    /// The container is returned too: a model object is only usable while its
    /// container is alive.
    @MainActor
    private func savedExpense(settled: Bool) throws -> (container: ModelContainer, expense: Expense) {
        let container = try ModelContainer(
            for: Expense.self, ExpenseItem.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let draft = ExpenseDraft(
            merchant: "Thai Garden",
            items: [DraftItem(name: "Dinner", quantity: 1, cents: 5000, category: .dining)],
            taxCents: 500
        )
        draft.plan.isShared = true
        draft.plan.selectOnly(sam)
        draft.isSettled = settled
        draft.save(in: context)
        try context.save()
        return (container, try context.fetch(FetchDescriptor<Expense>()).first!)
    }

    @MainActor
    func testWhatOthersOweIsTheirShareWithTaxIncluded() throws {
        let (container, expense) = try savedExpense(settled: false)
        withExtendedLifetime(container) {
            XCTAssertEqual(expense.owedToMe.map(\.cents), [2750])  // half of $55.00
            XCTAssertEqual(expense.myTotalCents, 2750)
        }
    }

    @MainActor
    func testSettledExpensesAreNoLongerOwedAndStaySettledWhenReopened() throws {
        let (container, expense) = try savedExpense(settled: true)
        withExtendedLifetime(container) {
            XCTAssertTrue(expense.owedToMe.isEmpty)
            XCTAssertTrue(ExpenseDraft(expense: expense).isSettled)
            XCTAssertEqual(expense.myTotalCents, 2750)  // your own share is unaffected
        }
    }

    @MainActor
    func testUnsharedExpensesOweNothing() throws {
        let container = try ModelContainer(
            for: Expense.self, ExpenseItem.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let draft = ExpenseDraft(items: [DraftItem(name: "Milk", quantity: 1, cents: 400, category: .groceries)])
        draft.save(in: container.mainContext)
        let expense = try container.mainContext.fetch(FetchDescriptor<Expense>()).first!
        withExtendedLifetime(container) { XCTAssertTrue(expense.owedToMe.isEmpty) }
    }

    @MainActor
    func testTurningSharingOffClearsTheSettledFlag() throws {
        let draft = ExpenseDraft(items: [DraftItem(name: "Milk", quantity: 1, cents: 400, category: .groceries)])
        draft.plan.isShared = true
        draft.plan.selectOnly(sam)
        draft.isSettled = true
        draft.plan.isShared = false
        let container = try ModelContainer(
            for: Expense.self, ExpenseItem.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        draft.save(in: container.mainContext)
        XCTAssertFalse(try container.mainContext.fetch(FetchDescriptor<Expense>()).first!.isSettled)
    }
}

final class ProfileTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
        suite = "profile-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeProfile() -> Profile { Profile(defaults: defaults, directory: directory) }

    private func imageData(width: CGFloat, height: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    func testInitialsAndFirstName() {
        let profile = makeProfile()
        XCTAssertEqual(profile.initials, "")
        profile.name = "  Dhana Siva  "
        XCTAssertEqual(profile.displayName, "Dhana Siva")
        XCTAssertEqual(profile.firstName, "Dhana")
        XCTAssertEqual(profile.initials, "DS")
        profile.name = "dhana"
        XCTAssertEqual(profile.initials, "D")
        profile.name = "Mary Ann Smith"
        XCTAssertEqual(profile.initials, "MS")
    }

    func testNameSurvivesRelaunch() {
        makeProfile().name = "Dhana"
        XCTAssertEqual(makeProfile().name, "Dhana")
    }

    func testPhotoIsCroppedToASquareAndShrunk() throws {
        let profile = makeProfile()
        XCTAssertTrue(profile.setPhoto(from: imageData(width: 3000, height: 1500)))
        let stored = try XCTUnwrap(profile.photo)
        XCTAssertEqual(stored.size.width, stored.size.height)
        XCTAssertLessThanOrEqual(stored.size.width, Profile.photoSide)
        XCTAssertLessThan(try XCTUnwrap(profile.photoData).count, 200_000)
    }

    func testSmallPhotosAreNotBlownUp() throws {
        let profile = makeProfile()
        XCTAssertTrue(profile.setPhoto(from: imageData(width: 200, height: 300)))
        XCTAssertEqual(try XCTUnwrap(profile.photo).size.width, 200)
    }

    func testPhotoSurvivesRelaunchAndCanBeRemoved() {
        let profile = makeProfile()
        XCTAssertTrue(profile.setPhoto(from: imageData(width: 400, height: 400)))
        XCTAssertTrue(makeProfile().hasPhoto)
        profile.removePhoto()
        XCTAssertFalse(profile.hasPhoto)
        XCTAssertFalse(makeProfile().hasPhoto)
    }

    func testBadImageDataIsRejectedAndKeepsTheOldPhoto() {
        let profile = makeProfile()
        XCTAssertTrue(profile.setPhoto(from: imageData(width: 100, height: 100)))
        XCTAssertFalse(profile.setPhoto(from: Data("not an image".utf8)))
        XCTAssertTrue(profile.hasPhoto)
    }

    func testGreetingFollowsTheTimeOfDay() {
        XCTAssertEqual(Greeting.title(firstName: "Dhana", hour: 8), "Good morning, Dhana")
        XCTAssertEqual(Greeting.title(firstName: "Dhana", hour: 14), "Good afternoon, Dhana")
        XCTAssertEqual(Greeting.title(firstName: "Dhana", hour: 20), "Good evening, Dhana")
        XCTAssertEqual(Greeting.title(firstName: "Dhana", hour: 2), "Good evening, Dhana")
        XCTAssertEqual(Greeting.title(firstName: "", hour: 9), "Fin4U")
    }
}

final class MonthSeriesTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    func testAlwaysTwelveMonthsInOrderWithBlanksAsZero() {
        let series = SpendStats.monthSeries([10: 6747, 2: 4550], calendar: calendar)
        XCTAssertEqual(series.count, 12)
        XCTAssertEqual(series.map(\.month), Array(1...12))
        XCTAssertEqual(series.first?.label, "Jan")
        XCTAssertEqual(series.last?.label, "Dec")
        XCTAssertEqual(series[1].cents, 4550)
        XCTAssertEqual(series[9].cents, 6747)
        XCTAssertEqual(series.filter { $0.cents == 0 }.count, 10)
    }

    func testAnEmptyYearIsTwelveZeros() {
        XCTAssertEqual(SpendStats.monthSeries([:], calendar: calendar).map(\.cents), Array(repeating: 0, count: 12))
    }
}

final class CollapsedSectionsTests: XCTestCase {
    func testNothingIsCollapsedByDefault() {
        let collapsed = CollapsedSections(raw: "")
        XCTAssertTrue(DashboardSection.allCases.allSatisfy { !collapsed.contains($0) })
    }

    func testTogglingCollapsesAndExpands() {
        var collapsed = CollapsedSections(raw: "")
        collapsed.toggle(.chart)
        XCTAssertTrue(collapsed.contains(.chart))
        XCTAssertFalse(collapsed.contains(.recent))
        collapsed.toggle(.chart)
        XCTAssertFalse(collapsed.contains(.chart))
    }

    func testItRoundTripsThroughItsStoredString() {
        var collapsed = CollapsedSections(raw: "")
        collapsed.toggle(.recent)
        collapsed.toggle(.summary)
        let restored = CollapsedSections(raw: collapsed.raw)
        XCTAssertEqual(restored, collapsed)
        XCTAssertEqual(collapsed.raw, "recent,summary")  // stable order
    }

    func testUnknownNamesAreIgnored() {
        let collapsed = CollapsedSections(raw: "chart,somethingNew,,recent")
        XCTAssertEqual(collapsed.sections, [.chart, .recent])
    }
}

final class SplitwisePayloadTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testSharesBecomeNumberedUserFieldsThatAddUpToTheCost() throws {
        let fields = try SplitwisePayload.fields(
            description: "Thai Garden", date: Date(timeIntervalSince1970: 1_790_000_000), currency: "USD",
            totalCents: 5500, groupID: 0,
            shares: [
                SplitwiseShare(userID: 11, paidCents: 5500, owedCents: 2750),
                SplitwiseShare(userID: 22, paidCents: 0, owedCents: 2750),
            ],
            details: "notes", calendar: utc
        )
        XCTAssertEqual(fields["cost"], "55.00")
        XCTAssertEqual(fields["description"], "Thai Garden")
        XCTAssertEqual(fields["currency_code"], "USD")
        XCTAssertEqual(fields["group_id"], "0")
        XCTAssertEqual(fields["users__0__user_id"], "11")
        XCTAssertEqual(fields["users__0__paid_share"], "55.00")
        XCTAssertEqual(fields["users__0__owed_share"], "27.50")
        XCTAssertEqual(fields["users__1__user_id"], "22")
        XCTAssertEqual(fields["users__1__paid_share"], "0.00")
        XCTAssertEqual(fields["users__1__owed_share"], "27.50")
    }

    func testOddCentsStayExact() throws {
        let fields = try SplitwisePayload.fields(
            description: "x", date: Date(), currency: "USD", totalCents: 189, groupID: 7,
            shares: [SplitwiseShare(userID: 1, paidCents: 189, owedCents: 95), SplitwiseShare(userID: 2, paidCents: 0, owedCents: 94)],
            details: ""
        )
        XCTAssertEqual(fields["users__0__owed_share"], "0.95")
        XCTAssertEqual(fields["users__1__owed_share"], "0.94")
        XCTAssertEqual(fields["group_id"], "7")
    }

    func testRefusesToSendAmountsThatDontAddUp() {
        XCTAssertThrowsError(try SplitwisePayload.fields(
            description: "x", date: Date(), currency: "USD", totalCents: 1000, groupID: 0,
            shares: [SplitwiseShare(userID: 1, paidCents: 1000, owedCents: 400), SplitwiseShare(userID: 2, paidCents: 0, owedCents: 500)],
            details: ""
        )) { XCTAssertEqual($0 as? SplitwisePayloadError, .sharesDontAddUp) }
        XCTAssertThrowsError(try SplitwisePayload.fields(
            description: "x", date: Date(), currency: "USD", totalCents: 1000, groupID: 0,
            shares: [SplitwiseShare(userID: 1, paidCents: 0, owedCents: 500), SplitwiseShare(userID: 2, paidCents: 0, owedCents: 500)],
            details: ""
        )) { XCTAssertEqual($0 as? SplitwisePayloadError, .nobodyPaid) }
    }

    func testTheDateIsNoonUTCOnTheReceiptsOwnDay() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let lateEvening = la.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 30))!
        XCTAssertEqual(SplitwisePayload.isoDate(lateEvening, calendar: la), "2026-10-09T12:00:00Z")
        let earlyMorning = la.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 5))!
        XCTAssertEqual(SplitwisePayload.isoDate(earlyMorning, calendar: la), "2026-01-01T12:00:00Z")
    }

    func testTheNoteListsItemsAndWhoPaysForEach() {
        let text = SplitwisePayload.details(
            merchant: "Shoprite",
            items: [
                (name: "Milk", cents: 429, shares: [(name: "Dhana", cents: 215), (name: "Sam", cents: 214)]),
                (name: "Vitamins", cents: 1299, shares: [(name: "Dhana", cents: 1299), (name: "Sam", cents: 0)]),
            ],
            taxCents: 120, tipCents: 0, currency: "USD"
        )
        XCTAssertTrue(text.contains("Receipt from Shoprite"))
        XCTAssertTrue(text.contains("Milk $4.29  ->  Dhana $2.15 / Sam $2.14"))
        XCTAssertTrue(text.contains("Vitamins $12.99  ->  Dhana $12.99"))  // Sam's zero share is left out
        XCTAssertFalse(text.contains("Sam $0.00"))
        XCTAssertTrue(text.contains("Tax $1.20"))
        XCTAssertFalse(text.contains("Tip"))
    }

    func testDecodesSplitwiseResponses() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let user = try decoder.decode(SplitwiseCurrentUserResponse.self, from: Data(#"{"user":{"id":5,"first_name":"Daya","last_name":null,"email":"d@example.com","registration_status":"confirmed"}}"#.utf8))
        XCTAssertEqual(user.user.displayName, "Daya")
        let friends = try decoder.decode(SplitwiseFriendsResponse.self, from: Data(#"{"friends":[{"id":9,"first_name":"Sam","last_name":"Lee","email":null}]}"#.utf8))
        XCTAssertEqual(friends.friends.first?.displayName, "Sam Lee")
        let ok = try decoder.decode(SplitwiseCreateExpenseResponse.self, from: Data(#"{"expenses":[{"id":123456}],"errors":{}}"#.utf8))
        XCTAssertEqual(ok.expenses?.first?.id, 123456)
        XCTAssertEqual(ok.errors?.messages, [])
        let bad = try decoder.decode(SplitwiseCreateExpenseResponse.self, from: Data(#"{"expenses":[],"errors":{"base":["Total must equal the sum of shares"]}}"#.utf8))
        XCTAssertEqual(bad.errors?.messages, ["Total must equal the sum of shares"])
    }
}

/// Answers every request from a closure, so API code runs without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SplitwiseAPITests: XCTestCase {
    private func api(token: String? = "tok") -> SplitwiseAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SplitwiseAPI(token: { token }, session: URLSession(configuration: configuration))
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testRefusesToCallWithoutAToken() async {
        do { _ = try await api(token: nil).currentUser(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SplitwiseError, .notConnected) }
    }

    func testSendsTheTokenAndReadsTheUser() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"user":{"id":5,"first_name":"Daya","last_name":"D","email":"d@x.com"}}"#.utf8)) }
        let user = try await api().currentUser()
        XCTAssertEqual(user.id, 5)
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.absoluteString, "https://secure.splitwise.com/api/v3.0/get_current_user")
    }

    func testAnExpiredOrRevokedTokenIsReportedAsSignedOut() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":"Invalid API Request: you are not logged in"}"#.utf8)) }
        do { _ = try await api().friends(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SplitwiseError, .unauthorized) }
    }

    func testGroupsLeaveOutSplitwisesCatchAllGroupZero() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"groups":[{"id":0,"name":"Non-group expenses"},{"id":42,"name":"Apartment"}]}"#.utf8)) }
        let groups = try await api().groups()
        XCTAssertEqual(groups.map(\.name), ["Apartment"])
    }

    func testCreateExpensePostsFormFieldsAndReturnsTheNewId() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"expenses":[{"id":987}],"errors":{}}"#.utf8)) }
        let id = try await api().createExpense(fields: ["cost": "55.00", "description": "Thai & Co", "details": "a\nb"])
        XCTAssertEqual(id, 987)
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        let body = String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "cost=55.00&description=Thai%20%26%20Co&details=a%0Ab")
    }

    func testSplitwiseRefusingAnExpenseSurfacesItsReason() async {
        // Splitwise reports validation problems with a 200 and an `errors` body.
        StubURLProtocol.handler = { _ in (200, Data(#"{"expenses":[],"errors":{"base":["Sum of shares must equal the cost"]}}"#.utf8)) }
        do { _ = try await api().createExpense(fields: [:]); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SplitwiseError, .rejected(["Sum of shares must equal the cost"])) }
    }

    func testFormBodyEscapesEverythingThatCouldBreakTheEncoding() {
        let body = String(data: SplitwiseAPI.formBody(["b": "x+y=z", "a": "é & 100%"]), encoding: .utf8)
        XCTAssertEqual(body, "a=%C3%A9%20%26%20100%25&b=x%2By%3Dz")  // keys sorted, values fully escaped
    }
}

final class SplitwiseSignInTests: XCTestCase {
    func testStatesAreRandomLongAndURLSafe() {
        let a = SplitwiseSignIn.newState(), b = SplitwiseSignIn.newState()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 16)  // the server requires 16...128 of [A-Za-z0-9_-]
        XCTAssertNotNil(a.range(of: "^[A-Za-z0-9_-]{16,128}$", options: .regularExpression))
    }

    func testAMatchingCallbackYieldsTheHandoffCode() {
        let url = URL(string: "fin4u://splitwise/?handoff=abc123&state=S1")!
        XCTAssertEqual(SplitwiseSignIn.parse(callback: url, expectedState: "S1"), .handoff("abc123"))
    }

    func testAWrongStateIsRejectedEvenWithAHandoff() {
        let url = URL(string: "fin4u://splitwise/?handoff=abc123&state=EVIL")!
        XCTAssertEqual(SplitwiseSignIn.parse(callback: url, expectedState: "S1"), .failed("state_mismatch"))
    }

    func testErrorsComeThroughAndHaveFriendlyMessages() {
        let url = URL(string: "fin4u://splitwise/?error=access_denied&state=S1")!
        XCTAssertEqual(SplitwiseSignIn.parse(callback: url, expectedState: "S1"), .failed("access_denied"))
        XCTAssertEqual(SplitwiseSignIn.parse(callback: URL(string: "fin4u://splitwise/?state=S1")!, expectedState: "S1"), .failed("no_handoff"))
        XCTAssertTrue(SplitwiseSignIn.message(forFailure: "not_configured").contains("isn't set up"))
        XCTAssertTrue(SplitwiseSignIn.message(forFailure: "weird").contains("Try again"))
    }
}

final class KeychainTests: XCTestCase {
    private let service = "com.dhana.fin4u.tests.\(UUID().uuidString)"

    override func tearDown() {
        Keychain.delete(service: service, account: "a")
        super.tearDown()
    }

    func testSaveReadReplaceAndDelete() {
        XCTAssertNil(Keychain.read(service: service, account: "a"))
        XCTAssertTrue(Keychain.save("first", service: service, account: "a"))
        XCTAssertEqual(Keychain.read(service: service, account: "a"), "first")
        XCTAssertTrue(Keychain.save("second", service: service, account: "a"))  // replaces, doesn't duplicate
        XCTAssertEqual(Keychain.read(service: service, account: "a"), "second")
        XCTAssertTrue(Keychain.delete(service: service, account: "a"))
        XCTAssertNil(Keychain.read(service: service, account: "a"))
    }
}

@MainActor
final class SplitwisePosterTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Expense.self, ExpenseItem.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func sharedExpense(in context: ModelContext) -> Expense {
        let sam = Participant(id: "sam-local", name: "Sam")
        let draft = ExpenseDraft(
            merchant: "Shoprite",
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!,
            items: [
                DraftItem(name: "Milk", quantity: 1, cents: 429, category: .groceries),
                DraftItem(name: "Vitamins", quantity: 1, cents: 1299, category: .health),
            ],
            taxCents: 120
        )
        draft.plan.isShared = true
        draft.plan.selectOnly(sam)
        draft.setItemize(true)
        draft.setItemShared(true, of: draft.items[0].id)  // milk split 50/50; vitamins stay all yours
        return draft.save(in: context)
    }

    private func api(reply: Data = Data(#"{"expenses":[{"id":555}],"errors":{}}"#.utf8), status: Int = 200) -> SplitwiseAPI {
        StubURLProtocol.handler = { _ in (status, reply) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return SplitwiseAPI(token: { "tok" }, session: URLSession(configuration: configuration))
    }

    func testYouPaidTheWholeBillAndEachOwesTheirShareWithTaxAndAllItemsListed() throws {
        let c = try container()
        let expense = sharedExpense(in: c.mainContext)
        let fields = try SplitwisePoster.fields(for: expense, myUserID: 11, myName: "Dhana", friendUserID: 22, groupID: 0)

        let total = expense.totalCents
        XCTAssertEqual(fields["cost"], Money.plain(total))
        XCTAssertEqual(fields["users__0__user_id"], "11")
        XCTAssertEqual(fields["users__0__paid_share"], Money.plain(total))
        XCTAssertEqual(fields["users__1__user_id"], "22")
        XCTAssertEqual(fields["users__1__paid_share"], "0.00")
        // The two owed shares add up to the cost exactly.
        let owed = ["users__0__owed_share", "users__1__owed_share"].compactMap { fields[$0] }.compactMap(Money.parseCents).reduce(0, +)
        XCTAssertEqual(owed, total)
        // Sam only shares the milk (and its slice of tax): far less than half the bill.
        XCTAssertLessThan(Money.parseCents(fields["users__1__owed_share"]!)!, total / 4)
        XCTAssertEqual(fields["description"], "Shoprite")
        XCTAssertEqual(fields["date"], "2026-10-09T12:00:00Z")
        XCTAssertTrue(fields["details"]!.contains("Milk $4.29  ->  Dhana $2.15 / Sam $2.14"))
        XCTAssertTrue(fields["details"]!.contains("Vitamins $12.99  ->  Dhana $12.99"))
        withExtendedLifetime(c) {}
    }

    func testPostingRecordsTheSplitwiseIdAndRefusesToPostTwice() async throws {
        let c = try container()
        let expense = sharedExpense(in: c.mainContext)
        try await SplitwisePoster.post(expense, api: api(), myUserID: 11, myName: "Dhana", friendUserID: 22, groupID: 5, context: c.mainContext)
        XCTAssertEqual(expense.splitwiseExpenseID, 555)
        XCTAssertNotNil(expense.splitwisePostedAt)
        XCTAssertTrue(String(data: StubURLProtocol.lastBody ?? Data(), encoding: .utf8)!.contains("group_id=5"))

        do {
            try await SplitwisePoster.post(expense, api: api(), myUserID: 11, myName: "Dhana", friendUserID: 22, groupID: 5, context: c.mainContext)
            XCTFail("a second post should be refused")
        } catch { XCTAssertEqual(error as? SplitwisePosterError, .alreadyAdded) }
        withExtendedLifetime(c) {}
    }

    func testARefusedExpenseIsNotMarkedAsAdded() async throws {
        let c = try container()
        let expense = sharedExpense(in: c.mainContext)
        let refusing = api(reply: Data(#"{"expenses":[],"errors":{"base":["nope"]}}"#.utf8))
        do {
            try await SplitwisePoster.post(expense, api: refusing, myUserID: 11, myName: "Dhana", friendUserID: 22, groupID: 0, context: c.mainContext)
            XCTFail("should throw")
        } catch { XCTAssertEqual(error as? SplitwiseError, .rejected(["nope"])) }
        XCTAssertNil(expense.splitwiseExpenseID)  // so it can be retried
        withExtendedLifetime(c) {}
    }

    func testAnUnsharedExpenseCantBeAdded() throws {
        let c = try container()
        let draft = ExpenseDraft(merchant: "Solo", items: [DraftItem(name: "x", quantity: 1, cents: 100, category: .other)])
        let expense = draft.save(in: c.mainContext)
        XCTAssertThrowsError(try SplitwisePoster.fields(for: expense, myUserID: 1, myName: "Me", friendUserID: 2, groupID: 0)) {
            XCTAssertEqual($0 as? SplitwisePosterError, .notShared)
        }
        withExtendedLifetime(c) {}
    }

    func testSavingADraftTwiceUpdatesTheSameExpense() throws {
        let c = try container()
        let draft = ExpenseDraft(merchant: "Once", items: [DraftItem(name: "x", quantity: 1, cents: 100, category: .other)])
        let first = draft.save(in: c.mainContext)
        draft.merchant = "Twice"
        let second = draft.save(in: c.mainContext)
        XCTAssertTrue(first === second)
        XCTAssertEqual(try c.mainContext.fetch(FetchDescriptor<Expense>()).count, 1)
    }
}

@MainActor
final class ManualTotalTests: XCTestCase {
    private func scanned(printedTotal: Int = 0) -> ExpenseDraft {
        ExpenseDraft(
            merchant: "Cafe",
            items: [
                DraftItem(name: "Latte", quantity: 1, cents: 900, category: .dining),
                DraftItem(name: "Bagel", quantity: 1, cents: 350, category: .dining),
            ],
            taxCents: 100, tipCents: 200,
            receiptImage: Data([1]),
            printedSubtotalCents: printedTotal > 0 ? 1250 : 0,
            printedTotalCents: printedTotal
        )
    }

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Expense.self, ExpenseItem.self, Person.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func testWithoutATypedTotalNothingChanges() {
        let d = scanned()
        XCTAssertEqual(d.effectiveAdjustmentCents, 0)
        XCTAssertEqual(d.totalCents, 1250 + 100 + 200)
    }

    func testTypingATotalKeepsTheItemsAndRecordsTheDifference() {
        let d = scanned()
        d.setTotal(1750)  // the receipt says $17.50
        XCTAssertEqual(d.totalCents, 1750)
        XCTAssertEqual(d.subtotalCents, 1250)  // items untouched
        XCTAssertEqual(d.effectiveAdjustmentCents, 200)  // 1750 - (1250 + 100 + 200)
    }

    func testTheAdjustmentShrinksAsItemsAreCorrected() {
        let d = scanned()
        d.setTotal(1750)
        d.items[1].cents = 550  // fixing the misread bagel price
        XCTAssertEqual(d.totalCents, 1750)  // the typed total stays put
        XCTAssertEqual(d.effectiveAdjustmentCents, 0)  // nothing left unexplained
    }

    func testEditingTheNotItemizedAmountDirectlyMovesTheTotal() {
        let d = scanned()
        d.setTotal(1750)
        d.setAdjustment(-50)
        XCTAssertEqual(d.totalCents, 1250 + 100 + 200 - 50)
        d.items[0].cents = 1000  // now the total follows the items again
        XCTAssertEqual(d.totalCents, 1350 + 100 + 200 - 50)
    }

    func testOneTapUsesTheReceiptsPrintedTotal() {
        let d = scanned(printedTotal: 1600)  // items + tax + tip = 1550: off by 50
        XCTAssertTrue(d.canUseReceiptTotal)
        XCTAssertFalse(d.checks.isEmpty)
        d.useReceiptTotal()
        XCTAssertEqual(d.totalCents, 1600)
        XCTAssertFalse(d.canUseReceiptTotal)
        XCTAssertTrue(d.checks.filter { $0.contains("total") }.isEmpty)  // the total warning clears
    }

    func testNoPrintedTotalMeansNothingToOffer() {
        let d = scanned(printedTotal: 0)
        XCTAssertFalse(d.canUseReceiptTotal)
        d.useReceiptTotal()
        XCTAssertEqual(d.totalCents, 1550)  // unchanged
    }

    func testAdjustmentIsSharedOutLikeTaxAndEveryonesPartsAddUpToTheTotal() {
        let sam = Participant(id: "sam", name: "Sam")
        let d = scanned()
        d.plan.isShared = true
        d.plan.selectOnly(sam)
        d.setItemize(true)
        d.setItemShared(true, of: d.items[0].id)  // only the latte is split
        d.setTotal(1801)  // 251 not itemized
        let totals = d.personTotals
        XCTAssertEqual(totals.reduce(0) { $0 + $1.cents }, 1801)
        // Sam carries part of the latte only, so part of the overhead too -- never more than half the latte share.
        XCTAssertGreaterThan(totals.first { $0.id == "sam" }!.cents, 450)
    }

    func testANegativeAdjustmentWorksToo() {
        let d = scanned()
        d.setTotal(1000)  // less than the items (an unlisted discount)
        XCTAssertEqual(d.effectiveAdjustmentCents, 1000 - 1550)
        XCTAssertEqual(d.totalCents, 1000)
    }

    func testTheAdjustmentIsSavedAndReopens() throws {
        let c = try container()
        let d = scanned()
        d.setTotal(1750)
        let expense = d.save(in: c.mainContext)
        XCTAssertEqual(expense.totalCents, 1750)
        XCTAssertEqual(expense.adjustmentCents, 200)

        let reopened = ExpenseDraft(expense: expense)
        XCTAssertEqual(reopened.totalCents, 1750)
        XCTAssertEqual(reopened.effectiveAdjustmentCents, 200)
        withExtendedLifetime(c) {}
    }

    func testCategoryTotalsStillAddUpToYourTotalWithAnAdjustment() throws {
        let c = try container()
        let d = ExpenseDraft(items: [
            DraftItem(name: "Milk", quantity: 1, cents: 3000, category: .groceries),
            DraftItem(name: "Vitamins", quantity: 1, cents: 1000, category: .health),
        ], taxCents: 400)
        d.setTotal(4700)  // 300 not itemized
        let expense = d.save(in: c.mainContext)
        XCTAssertEqual(expense.myCategoryTotals.values.reduce(0, +), 4700)
        XCTAssertEqual(expense.myTotalCents, 4700)
        withExtendedLifetime(c) {}
    }
}

@MainActor
final class ShareSummaryTests: XCTestCase {
    private func sharedDraft() -> ExpenseDraft {
        let sam = Participant(id: "sam", name: "Sam")
        let d = ExpenseDraft(
            merchant: "Thai Garden",
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!,
            items: [
                DraftItem(name: "Pad Thai", quantity: 1, cents: 2400, category: .dining),
                DraftItem(name: "My salad", quantity: 1, cents: 1000, category: .dining),
            ],
            taxCents: 340
        )
        d.plan.isShared = true
        d.plan.selectOnly(sam)
        d.setItemize(true)
        d.setItemShared(true, of: d.items[0].id)  // pad thai 50/50; salad is mine
        return d
    }

    func testTheMessageSaysWhoPaidWhoOwesAndHowItWasSplit() {
        let text = sharedDraft().shareSummary(ownerName: "Dhana")
        XCTAssertTrue(text.hasPrefix("Thai Garden - Oct 2, 2026\nDhana paid $37.40 for this receipt."))
        // Sam carries half the pad thai ($12.00) plus 12/34 of the tax: 340 * 1200/3400 = 120.
        XCTAssertTrue(text.contains("Sam owes Dhana $13.20."))
        XCTAssertTrue(text.contains("Pad Thai $24.00  ->  Dhana $12.00 / Sam $12.00"))
        XCTAssertTrue(text.contains("My salad $10.00  ->  Dhana $10.00"))  // Sam's zero share is left out
        XCTAssertFalse(text.contains("Sam $0.00"))
        XCTAssertTrue(text.contains("Tax $3.40"))
        XCTAssertTrue(text.hasSuffix("Sent from Fin4U"))
    }

    func testWithoutAProfileNameItReadsInTheFirstPerson() {
        let text = sharedDraft().shareSummary(ownerName: "  ")
        XCTAssertTrue(text.contains("I paid $37.40 for this receipt."))
        XCTAssertTrue(text.contains("Sam owes me $13.20."))
        XCTAssertTrue(text.contains("Pad Thai $24.00  ->  Me $12.00 / Sam $12.00"))
    }

    func testANotItemizedAmountIsListedAndExplained() {
        let d = sharedDraft()
        d.setTotal(3900)  // 160 not itemized
        let text = d.shareSummary(ownerName: "Dhana")
        XCTAssertTrue(text.contains("Dhana paid $39.00"))
        XCTAssertTrue(text.contains("Not itemized $1.60"))
        XCTAssertTrue(text.contains("anything not itemized are shared in proportion"))
    }

    func testTheOwedAmountsInTheMessageMatchTheScreensTotals() {
        let d = sharedDraft()
        let sam = d.personTotals.first { $0.id == "sam" }!.cents
        XCTAssertTrue(d.shareSummary(ownerName: "Dhana").contains("Sam owes Dhana \(Money.format(sam, currency: "USD"))."))
    }

    func testNothingToSettleWhenNobodyOwesAnything() {
        let d = sharedDraft()
        d.setItemShared(false, of: d.items[0].id)  // nothing is shared any more
        let text = d.shareSummary(ownerName: "Dhana")
        XCTAssertTrue(text.contains("Nothing to settle."))
        XCTAssertFalse(text.contains("owes"))
    }
}
