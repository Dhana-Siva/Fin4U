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
