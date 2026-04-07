import XCTest
@testable import ACDCore

final class SalesReportQueryTests: XCTestCase {
    func testSummarySalesDailyUsesVersionOneZero() {
        let query = SalesReportQuery.summarySales(vendorNumber: "12345678", reportDate: "2026-04-06")

        XCTAssertEqual(query.frequency, "DAILY")
        XCTAssertEqual(query.reportType, "SALES")
        XCTAssertEqual(query.reportSubType, "SUMMARY")
        XCTAssertEqual(query.version, "1_0")
    }
}
