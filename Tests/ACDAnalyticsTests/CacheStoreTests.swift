import XCTest
import Foundation
@testable import ACDAnalytics
@testable import ACDCore

final class CacheStoreTests: XCTestCase {
    func testRecordReportsBatchDeduplicatesByLatestRecord() throws {
        let cacheStore = try makeCacheStore()
        let firstURL = cacheStore.reportsDirectory.appendingPathComponent("first.tsv")
        let secondURL = cacheStore.reportsDirectory.appendingPathComponent("second.tsv")
        let thirdURL = cacheStore.reportsDirectory.appendingPathComponent("third.tsv")
        try LocalFileSecurity.writePrivateData(Data("first".utf8), to: firstURL)
        try LocalFileSecurity.writePrivateData(Data("second".utf8), to: secondURL)
        try LocalFileSecurity.writePrivateData(Data("third".utf8), to: thirdURL)

        let reports = [
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: firstURL,
                rawText: "first"
            ),
            DownloadedReport(
                source: .sales,
                reportType: "SALES",
                reportSubType: "SUMMARY",
                queryHash: "duplicate",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: secondURL,
                rawText: "second"
            ),
            DownloadedReport(
                source: .sales,
                reportType: "SUBSCRIPTION",
                reportSubType: "SUMMARY",
                queryHash: "unique",
                reportDateKey: "2026-02-18",
                vendorNumber: "TEST_VENDOR",
                fileURL: thirdURL,
                rawText: "third"
            )
        ]

        let recorded = try cacheStore.record(reports: reports)
        let manifest = try cacheStore.loadManifest()

        XCTAssertEqual(recorded.count, 3)
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(
            manifest.first(where: { $0.queryHash == "duplicate" })?.filePath,
            secondURL.path
        )
    }

    private func makeCacheStore() throws -> CacheStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(".app-connect-data-cli/cache", isDirectory: true)
        let cacheStore = CacheStore(rootDirectory: root)
        try cacheStore.prepare()
        return cacheStore
    }
}
