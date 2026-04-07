// Copyright 2026 BunnyxStudio
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import ACDCore

public struct SyncSummary: Codable, Sendable {
    public var records: [CachedReportRecord]
    public var reviewCount: Int

    public init(records: [CachedReportRecord] = [], reviewCount: Int = 0) {
        self.records = records
        self.reviewCount = reviewCount
    }
}

public final class SyncService {
    private let cacheStore: CacheStore
    private let downloader: ReportDownloader
    private let client: ASCClient

    public init(
        cacheStore: CacheStore,
        downloader: ReportDownloader,
        client: ASCClient
    ) {
        self.cacheStore = cacheStore
        self.downloader = downloader
        self.client = client
    }

    public func syncSales(
        dates: [Date],
        monthlyFiscalMonths: [String],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for date in dates {
            try await appendIfAvailable(&records) {
                try await downloader.fetchSalesDaily(datePT: date, cachePolicy: policy)
            }
        }
        for fiscalMonth in monthlyFiscalMonths {
            try await appendIfAvailable(&records) {
                try await downloader.fetchSalesMonthly(fiscalMonth: fiscalMonth, cachePolicy: policy)
            }
        }
        return SyncSummary(records: records)
    }

    public func syncSales(
        window: PTDateWindow,
        force: Bool
    ) async throws -> SyncSummary {
        try await syncSales(
            dates: ptDates(in: window, excludingFullMonths: true),
            monthlyFiscalMonths: fullFiscalMonthsContained(in: window),
            force: force
        )
    }

    public func syncSalesReports(
        window: PTDateWindow,
        reportFamilies: [SalesReportFamily],
        force: Bool
    ) async throws -> SyncSummary {
        let requested = reportFamilies.isEmpty ? [SalesReportFamily.summarySales] : reportFamilies
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        var records: [CachedReportRecord] = []

        if requested.contains(.summarySales) {
            let summary = try await syncSales(window: window, force: force)
            records.append(contentsOf: summary.records)
        }

        let dates = ptDates(in: window)
        for date in dates {
            if requested.contains(.subscription) {
                try await appendIfAvailable(&records) {
                    try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriptionEvent) {
                try await appendIfAvailable(&records) {
                    try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriber) {
                try await appendIfAvailable(&records) {
                    try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.preOrder) {
                try await appendIfAvailable(&records) {
                    try await downloader.fetchPreOrderDaily(datePT: date, cachePolicy: policy)
                }
            }
            if requested.contains(.subscriptionOfferRedemption) {
                try await appendIfAvailable(&records) {
                    try await downloader.fetchSubscriptionOfferCodeRedemptionDaily(datePT: date, cachePolicy: policy)
                }
            }
        }

        return SyncSummary(records: records)
    }

    public func syncSubscriptions(
        dates: [Date],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for date in dates {
            try await appendIfAvailable(&records) {
                try await downloader.fetchSubscriptionDaily(datePT: date, cachePolicy: policy)
            }
            try await appendIfAvailable(&records) {
                try await downloader.fetchSubscriptionEventDaily(datePT: date, cachePolicy: policy)
            }
            try await appendIfAvailable(&records) {
                try await downloader.fetchSubscriberDaily(datePT: date, cachePolicy: policy)
            }
        }
        return SyncSummary(records: records)
    }

    public func syncSubscriptions(
        window: PTDateWindow,
        force: Bool
    ) async throws -> SyncSummary {
        try await syncSubscriptions(dates: ptDates(in: window), force: force)
    }

    public func syncFinance(
        fiscalMonths: [String],
        regionCodes: [String],
        reportTypes: [FinanceReportType],
        force: Bool
    ) async throws -> SyncSummary {
        var records: [CachedReportRecord] = []
        let policy: ReportCachePolicy = force ? .reloadIgnoringCache : .useCached
        for fiscalMonth in fiscalMonths {
            for reportType in reportTypes {
                for regionCode in regionCodes {
                    try await appendIfAvailable(&records) {
                        try await downloader.fetchFinanceMonth(
                            fiscalMonth: fiscalMonth,
                            reportType: reportType,
                            regionCode: regionCode,
                            cachePolicy: policy
                        )
                    }
                }
            }
        }
        return SyncSummary(records: records)
    }

    public func syncFinance(
        window: PTDateWindow,
        regionCodes: [String],
        reportTypes: [FinanceReportType],
        force: Bool
    ) async throws -> SyncSummary {
        try await syncFinance(
            fiscalMonths: fiscalMonthsOverlapping(window: window),
            regionCodes: regionCodes,
            reportTypes: reportTypes,
            force: force
        )
    }

    public func syncReviews(
        maxApps: Int?,
        perAppLimit: Int?,
        totalLimit: Int?,
        query: ASCCustomerReviewQuery
    ) async throws -> SyncSummary {
        let reviews = try await client.fetchLatestCustomerReviews(
            maxApps: maxApps,
            perAppLimit: perAppLimit,
            totalLimit: totalLimit,
            appPageLimit: 200,
            pageLimit: 200,
            query: query
        )
        try cacheStore.saveReviews(CachedReviewsPayload(fetchedAt: Date(), reviews: reviews))
        return SyncSummary(records: [], reviewCount: reviews.count)
    }

    private func appendIfAvailable(
        _ records: inout [CachedReportRecord],
        load: () async throws -> DownloadedReport
    ) async throws {
        do {
            let report = try await load()
            records.append(try cacheStore.record(report: report))
        } catch ASCClientError.reportNotAvailableYet {
        }
    }
}
