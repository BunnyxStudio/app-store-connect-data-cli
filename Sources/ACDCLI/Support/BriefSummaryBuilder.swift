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
import ACDAnalytics
import ACDCore

struct BriefSummaryReport: Codable, Sendable {
    var title: String
    var currentLabel: String
    var compareLabel: String
    var reportingCurrency: String
    var sections: [BriefSummarySection]
    var warnings: [QueryWarning]
}

struct BriefSummarySection: Codable, Sendable {
    var title: String
    var note: String?
    var table: TableModel
}

enum BriefSummaryPeriod: Equatable {
    case daily
    case weekly
    case monthly

    var title: String {
        switch self {
        case .daily:
            return "Last Day Summary"
        case .weekly:
            return "Last Week Summary"
        case .monthly:
            return "Last Month Summary"
        }
    }

    var currentSelection: QueryTimeSelection {
        switch self {
        case .daily:
            return QueryTimeSelection(rangePreset: PTDateRangePreset.lastDay.rawValue)
        case .weekly:
            return QueryTimeSelection(rangePreset: PTDateRangePreset.lastWeek.rawValue)
        case .monthly:
            return QueryTimeSelection(rangePreset: PTDateRangePreset.lastMonth.rawValue)
        }
    }

    var currentWindow: PTDateWindow {
        switch self {
        case .daily:
            return PTDateRangePreset.lastDay.resolve()
        case .weekly:
            return PTDateRangePreset.lastWeek.resolve()
        case .monthly:
            return PTDateRangePreset.lastMonth.resolve()
        }
    }

    var compareMode: QueryCompareMode {
        switch self {
        case .daily:
            return .previousPeriod
        case .weekly:
            return .weekOverWeek
        case .monthly:
            return .monthOverMonth
        }
    }

    var previousWindow: PTDateWindow {
        let calendar = Calendar.pacific
        switch self {
        case .daily:
            let current = currentWindow
            let start = calendar.date(byAdding: .day, value: -1, to: current.startDate) ?? current.startDate
            let end = calendar.date(byAdding: .day, value: -1, to: current.endDate) ?? current.endDate
            return PTDateWindow(startDate: start, endDate: end)
        case .weekly:
            let current = currentWindow
            let start = calendar.date(byAdding: .day, value: -7, to: current.startDate) ?? current.startDate
            let end = calendar.date(byAdding: .day, value: -7, to: current.endDate) ?? current.endDate
            return PTDateWindow(startDate: start, endDate: end)
        case .monthly:
            let current = currentWindow
            let previousMonthEnd = calendar.date(byAdding: .day, value: -1, to: current.startDate) ?? current.startDate
            let previousMonth = calendar.dateInterval(of: .month, for: previousMonthEnd)
            let start = previousMonth?.start ?? previousMonthEnd
            let end = calendar.date(byAdding: .day, value: -1, to: previousMonth?.end ?? current.startDate) ?? previousMonthEnd
            return PTDateWindow(startDate: start, endDate: end)
        }
    }

    var previousSelection: QueryTimeSelection {
        let previous = previousWindow
        return QueryTimeSelection(startDatePT: previous.startDatePT, endDatePT: previous.endDatePT)
    }

    var includesFinance: Bool {
        self == .monthly
    }

    var currentDisplayLabel: String {
        switch self {
        case .daily:
            return "last-day (\(currentWindow.startDatePT))"
        case .weekly:
            return currentWindow.startDatePT + " to " + currentWindow.endDatePT
        case .monthly:
            return currentWindow.startDatePT + " to " + currentWindow.endDatePT
        }
    }

    var compareDisplayLabel: String {
        switch self {
        case .daily:
            return "previous-day (\(previousWindow.startDatePT))"
        case .weekly:
            return previousWindow.startDatePT + " to " + previousWindow.endDatePT
        case .monthly:
            return previousWindow.startDatePT + " to " + previousWindow.endDatePT
        }
    }
}

struct BriefSummaryBuilder {
    let runtime: RuntimeContext
    let offline: Bool
    let refresh: Bool

    func build(period: BriefSummaryPeriod) async throws -> BriefSummaryReport {
        try await prefetch(period: period)

        let salesOverview = try await executeQuery(
            dataset: .sales,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: []
        )
        let reviewsOverview = try await executeQuery(
            dataset: .reviews,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(),
            groupBy: []
        )
        let financeOverview = try await loadFinanceOverview(period: period)

        let salesByTerritory = try await executeQuery(
            dataset: .sales,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: [.territory]
        )
        let salesByDevice = try await executeQuery(
            dataset: .sales,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: [.device]
        )
        let salesByVersion = try await executeQuery(
            dataset: .sales,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: [.version]
        )
        let salesByCurrency = try await executeQuery(
            dataset: .sales,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: [.currency]
        )
        let reviewsByRating = try await executeQuery(
            dataset: .reviews,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(),
            groupBy: [.rating]
        )
        let reviewsByTerritory = try await executeQuery(
            dataset: .reviews,
            operation: .compare,
            time: period.currentSelection,
            compare: period.compareMode,
            filters: QueryFilterSet(),
            groupBy: [.territory]
        )
        let financeByTerritory = try await loadFinanceBreakdown(period: period, groupBy: .territory)
        let financeByCurrency = try await loadFinanceBreakdown(period: period, groupBy: .currency)

        let currentSummarySales = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.currentSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: []
        ).data.records
        let previousSummarySales = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.previousSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["summary-sales"]),
            groupBy: []
        ).data.records

        let currentSubscriptions = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.currentSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["subscription"]),
            groupBy: []
        ).data.records
        let previousSubscriptions = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.previousSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["subscription"]),
            groupBy: []
        ).data.records

        let currentEvents = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.currentSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["subscription-event"]),
            groupBy: []
        ).data.records
        let previousEvents = try await executeQuery(
            dataset: .sales,
            operation: .records,
            time: period.previousSelection,
            compare: nil,
            filters: QueryFilterSet(sourceReport: ["subscription-event"]),
            groupBy: []
        ).data.records

        let currentReviews = try await executeQuery(
            dataset: .reviews,
            operation: .records,
            time: period.currentSelection,
            compare: nil,
            filters: QueryFilterSet(),
            groupBy: []
        ).data.records
        let previousReviews = try await executeQuery(
            dataset: .reviews,
            operation: .records,
            time: period.previousSelection,
            compare: nil,
            filters: QueryFilterSet(),
            groupBy: []
        ).data.records

        let currentFinance = try await loadFinanceRecords(period: period)

        var sections: [BriefSummarySection] = []

        sections.append(
            makeOverviewSection(
                period: period,
                salesOverview: salesOverview,
                reviewsOverview: reviewsOverview,
                financeOverview: financeOverview,
                currentSubscriptions: currentSubscriptions,
                previousSubscriptions: previousSubscriptions
            )
        )

        if let section = makeTopProductsSection(current: currentSummarySales, previous: previousSummarySales) {
            sections.append(section)
        }

        sections.append(
            makeComparisonSection(
                title: "Sales by Territory",
                note: nil,
                result: salesByTerritory,
                groupKey: "territory",
                sortMetric: "proceeds",
                columns: ["territory", "proceeds", "change", "units", "purchases", "installs"],
                limit: 8
            )
        )
        sections.append(
            makeComparisonSection(
                title: "Sales by Device",
                note: nil,
                result: salesByDevice,
                groupKey: "device",
                sortMetric: "proceeds",
                columns: ["device", "proceeds", "change", "units", "purchases", "installs"],
                limit: 8
            )
        )
        sections.append(
            makeComparisonSection(
                title: "Sales by Version",
                note: nil,
                result: salesByVersion,
                groupKey: "version",
                sortMetric: "proceeds",
                columns: ["version", "proceeds", "change", "units", "purchases", "installs"],
                limit: 8
            )
        )
        sections.append(
            makeComparisonSection(
                title: "Sales by Currency",
                note: "Source currency rows are shown in \(reportingCurrency) after normalization.",
                result: salesByCurrency,
                groupKey: "currency",
                sortMetric: "proceeds",
                columns: ["currency", "proceeds", "change", "units", "purchases", "installs"],
                limit: 8
            )
        )

        if let section = makePlanMixSection(current: currentSubscriptions, previous: previousSubscriptions) {
            sections.append(section)
        }
        if let section = makeSubscriptionSnapshotSection(
            title: "Subscriptions by Territory",
            note: "Latest subscription snapshot inside each range.",
            current: currentSubscriptions,
            previous: previousSubscriptions,
            keyName: "territory"
        ) {
            sections.append(section)
        }
        if let section = makeSubscriptionSnapshotSection(
            title: "Subscriptions by Device",
            note: "Latest subscription snapshot inside each range.",
            current: currentSubscriptions,
            previous: previousSubscriptions,
            keyName: "device"
        ) {
            sections.append(section)
        }

        if let section = makeEventMixSection(current: currentEvents, previous: previousEvents) {
            sections.append(section)
        }
        if let section = makeCancelReasonSection(current: currentEvents, previous: previousEvents) {
            sections.append(section)
        }

        sections.append(
            makeComparisonSection(
                title: "Reviews by Rating",
                note: nil,
                result: reviewsByRating,
                groupKey: "rating",
                sortMetric: "count",
                columns: ["rating", "count", "change", "averageRating", "repliedRate"],
                limit: 5
            )
        )
        sections.append(
            makeComparisonSection(
                title: "Reviews by Territory",
                note: nil,
                result: reviewsByTerritory,
                groupKey: "territory",
                sortMetric: "count",
                columns: ["territory", "count", "change", "averageRating", "repliedRate"],
                limit: 8
            )
        )

        if let financeByTerritory {
            sections.append(
                makeComparisonSection(
                    title: "Finance by Territory",
                    note: "Finance uses \(period.currentWindow.endDate.fiscalMonthString) vs \(period.previousWindow.endDate.fiscalMonthString).",
                    result: financeByTerritory,
                    groupKey: "territory",
                    sortMetric: "proceeds",
                    columns: ["territory", "proceeds", "change", "amount", "units"],
                    limit: 8
                )
            )
        }
        if let financeByCurrency {
            sections.append(
                makeComparisonSection(
                    title: "Finance by Currency",
                    note: "Finance uses \(period.currentWindow.endDate.fiscalMonthString) vs \(period.previousWindow.endDate.fiscalMonthString).",
                    result: financeByCurrency,
                    groupKey: "currency",
                    sortMetric: "proceeds",
                    columns: ["currency", "proceeds", "change", "amount", "units"],
                    limit: 8
                )
            )
        }

        sections.append(
            makeDataHealthSection(
                period: period,
                currentSales: currentSummarySales,
                currentSubscriptions: currentSubscriptions,
                currentReviews: currentReviews,
                previousReviews: previousReviews,
                currentFinance: currentFinance
            )
        )

        let warningSources = [
            salesOverview,
            reviewsOverview,
            salesByTerritory,
            salesByDevice,
            salesByVersion,
            salesByCurrency,
            reviewsByRating,
            reviewsByTerritory,
            financeOverview,
            financeByTerritory,
            financeByCurrency
        ]
        let warnings = deduplicatedWarnings(
            warningSources.compactMap { $0 }.flatMap(\.warnings)
        )

        let currentLabel = period.currentDisplayLabel
        let compareLabel = period.compareDisplayLabel

        return BriefSummaryReport(
            title: period.title,
            currentLabel: currentLabel,
            compareLabel: compareLabel,
            reportingCurrency: reportingCurrency,
            sections: sections.filter { $0.table.rows.isEmpty == false },
            warnings: warnings
        )
    }

    private var reportingCurrency: String {
        (runtime.config.reportingCurrency ?? "USD").normalizedCurrencyCode
    }

    private func prefetch(period: BriefSummaryPeriod) async throws {
        guard offline == false, let syncService = runtime.syncService else { return }

        let unionWindow = PTDateWindow(
            startDate: min(period.currentWindow.startDate, period.previousWindow.startDate),
            endDate: max(period.currentWindow.endDate, period.previousWindow.endDate)
        )
        _ = try await syncService.syncSalesReports(
            window: unionWindow,
            reportFamilies: [.summarySales, .subscription, .subscriptionEvent],
            force: refresh
        )
        if period.includesFinance {
            _ = try await syncService.syncFinance(
                fiscalMonths: Array(
                    Set([
                        period.currentWindow.endDate.fiscalMonthString,
                        period.previousWindow.endDate.fiscalMonthString,
                    ])
                ).sorted(),
                regionCodes: ["ZZ", "Z1"],
                reportTypes: [.financial, .financeDetail],
                force: refresh
            )
        }
        let reviewQuery = ASCCustomerReviewQuery(sort: .newest)
        _ = try await syncService.syncReviews(
            maxApps: nil,
            perAppLimit: nil,
            totalLimit: nil,
            query: reviewQuery
        )
    }

    private func loadFinanceOverview(period: BriefSummaryPeriod) async throws -> QueryResult? {
        guard period.includesFinance else { return nil }
        return try await executeQuery(
            dataset: .finance,
            operation: .compare,
            time: QueryTimeSelection(fiscalMonth: period.currentWindow.endDate.fiscalMonthString),
            compare: .monthOverMonth,
            filters: QueryFilterSet(),
            groupBy: []
        )
    }

    private func loadFinanceBreakdown(period: BriefSummaryPeriod, groupBy: QueryGroupBy) async throws -> QueryResult? {
        guard period.includesFinance else { return nil }
        return try await executeQuery(
            dataset: .finance,
            operation: .compare,
            time: QueryTimeSelection(fiscalMonth: period.currentWindow.endDate.fiscalMonthString),
            compare: .monthOverMonth,
            filters: QueryFilterSet(),
            groupBy: [groupBy]
        )
    }

    private func loadFinanceRecords(period: BriefSummaryPeriod) async throws -> [QueryRecord] {
        guard period.includesFinance else { return [] }
        return try await executeQuery(
            dataset: .finance,
            operation: .records,
            time: QueryTimeSelection(fiscalMonth: period.currentWindow.endDate.fiscalMonthString),
            compare: nil,
            filters: QueryFilterSet(),
            groupBy: []
        ).data.records
    }

    private func executeQuery(
        dataset: QueryDataset,
        operation: QueryOperation,
        time: QueryTimeSelection,
        compare: QueryCompareMode?,
        filters: QueryFilterSet,
        groupBy: [QueryGroupBy]
    ) async throws -> QueryResult {
        try await runtime.analytics.execute(
            spec: DataQuerySpec(
                dataset: dataset,
                operation: operation,
                time: time,
                compare: compare,
                filters: filters,
                groupBy: groupBy
            ),
            offline: queryShouldUseOffline(dataset: dataset),
            refresh: false
        )
    }

    private func queryShouldUseOffline(dataset: QueryDataset) -> Bool {
        if offline {
            return true
        }
        switch dataset {
        case .reviews:
            return true
        default:
            return false
        }
    }

    private func makeOverviewSection(
        period: BriefSummaryPeriod,
        salesOverview: QueryResult,
        reviewsOverview: QueryResult,
        financeOverview: QueryResult?,
        currentSubscriptions: [QueryRecord],
        previousSubscriptions: [QueryRecord]
    ) -> BriefSummarySection {
        let sales = salesOverview.data.comparisons.first?.metrics ?? [:]
        let reviews = reviewsOverview.data.comparisons.first?.metrics ?? [:]
        let finance = financeOverview?.data.comparisons.first?.metrics ?? [:]

        let currentLatestSubscriptions = latestSnapshotRows(currentSubscriptions)
        let previousLatestSubscriptions = latestSnapshotRows(previousSubscriptions)
        let currentActiveSubscriptions = sumMetric(currentLatestSubscriptions, "activeSubscriptions")
        let previousActiveSubscriptions = sumMetric(previousLatestSubscriptions, "activeSubscriptions")
        let currentBillingRetry = sumMetric(currentLatestSubscriptions, "billingRetry")
        let previousBillingRetry = sumMetric(previousLatestSubscriptions, "billingRetry")
        let currentGracePeriod = sumMetric(currentLatestSubscriptions, "gracePeriod")
        let previousGracePeriod = sumMetric(previousLatestSubscriptions, "gracePeriod")
        let currentRetryRate = ratio(currentBillingRetry, currentActiveSubscriptions)
        let previousRetryRate = ratio(previousBillingRetry, previousActiveSubscriptions)
        let currentGraceRate = ratio(currentGracePeriod, currentActiveSubscriptions)
        let previousGraceRate = ratio(previousGracePeriod, previousActiveSubscriptions)

        let currentSalesProceeds = sales["proceeds"]?.current ?? 0
        let currentFinanceProceeds = finance["proceeds"]?.current ?? 0
        let previousSalesProceeds = sales["proceeds"]?.previous ?? 0
        let previousFinanceProceeds = finance["proceeds"]?.previous ?? 0

        var rows = [
            overviewRow("Sales Proceeds", currentSalesProceeds, previousSalesProceeds, .currency),
            overviewRow("Install Units", sales["installs"]?.current ?? 0, sales["installs"]?.previous ?? 0, .number),
            overviewRow("Purchase Units", sales["purchases"]?.current ?? 0, sales["purchases"]?.previous ?? 0, .number),
            overviewRow("Purchase Rate", ratio(sales["purchases"]?.current ?? 0, sales["installs"]?.current ?? 0), ratio(sales["purchases"]?.previous ?? 0, sales["installs"]?.previous ?? 0), .percentage),
            overviewRow("Refund Units", sales["refunds"]?.current ?? 0, sales["refunds"]?.previous ?? 0, .number),
            overviewRow("Qualified Conversions", sales["qualifiedConversions"]?.current ?? 0, sales["qualifiedConversions"]?.previous ?? 0, .number),
            overviewRow("Active Subs", currentActiveSubscriptions, previousActiveSubscriptions, .number),
            overviewRow("Billing Retry Rate", currentRetryRate, previousRetryRate, .percentage),
            overviewRow("Grace Rate", currentGraceRate, previousGraceRate, .percentage),
            overviewRow("Review Count", reviews["count"]?.current ?? 0, reviews["count"]?.previous ?? 0, .number),
            overviewRow("Average Rating", reviews["averageRating"]?.current ?? 0, reviews["averageRating"]?.previous ?? 0, .decimal),
            overviewRow("Reply Rate", reviews["repliedRate"]?.current ?? 0, reviews["repliedRate"]?.previous ?? 0, .percentage),
        ]

        var note = "Subscription metrics use the latest snapshot inside each range."
        if period.includesFinance {
            rows.insert(overviewRow("Sales-Finance Gap", currentSalesProceeds - currentFinanceProceeds, previousSalesProceeds - previousFinanceProceeds, .currency), at: 1)
            rows.insert(overviewRow("Finance Proceeds", currentFinanceProceeds, previousFinanceProceeds, .currency), at: 1)
            note = "Finance compares fiscal months. Subscription metrics use the latest snapshot inside each range."
        }

        return BriefSummarySection(
            title: "Overview",
            note: note,
            table: TableModel(
                columns: ["metric", "current", "compare", "change"],
                rows: rows
            )
        )
    }

    private func makeTopProductsSection(current: [QueryRecord], previous: [QueryRecord]) -> BriefSummarySection? {
        let currentMetrics = productMetrics(records: current)
        let previousMetrics = productMetrics(records: previous)
        let keys = Array(Set(currentMetrics.keys).union(previousMetrics.keys))
            .sorted { (currentMetrics[$0]?.proceeds ?? 0) > (currentMetrics[$1]?.proceeds ?? 0) }
            .prefix(10)

        let rows = keys.map { key -> [String] in
            let currentItem = currentMetrics[key] ?? ProductMetrics(name: key, sku: "", proceeds: 0, units: 0, purchases: 0)
            let previousItem = previousMetrics[key] ?? ProductMetrics(name: currentItem.name, sku: currentItem.sku, proceeds: 0, units: 0, purchases: 0)
            return [
                currentItem.name,
                currentItem.sku.isEmpty ? "-" : currentItem.sku,
                formatCurrency(currentItem.proceeds),
                formatDeltaPercent(current: currentItem.proceeds, previous: previousItem.proceeds),
                formatNumber(currentItem.units),
                formatNumber(currentItem.purchases),
            ]
        }

        guard rows.isEmpty == false else { return nil }
        return BriefSummarySection(
            title: "Top Products",
            note: "Ranked by current-period proceeds.",
            table: TableModel(
                columns: ["product", "sku", "proceeds", "change", "units", "purchases"],
                rows: rows
            )
        )
    }

    private func makePlanMixSection(current: [QueryRecord], previous: [QueryRecord]) -> BriefSummarySection? {
        let currentRows = latestSnapshotRows(current)
        let previousRows = latestSnapshotRows(previous)
        let currentGroups = subscriptionSnapshotMetrics(rows: currentRows, keyName: "plan")
        let previousGroups = subscriptionSnapshotMetrics(rows: previousRows, keyName: "plan")
        let order = ["Monthly", "Yearly", "Lifetime", "Other"]
        let rows = order.compactMap { key -> [String]? in
            let currentItem = currentGroups[key] ?? SubscriptionSnapshotMetrics()
            let previousItem = previousGroups[key] ?? SubscriptionSnapshotMetrics()
            guard currentItem.activeSubscriptions != 0 || previousItem.activeSubscriptions != 0 else { return nil }
            return [
                key,
                formatNumber(currentItem.activeSubscriptions),
                formatDeltaPercent(current: currentItem.activeSubscriptions, previous: previousItem.activeSubscriptions),
                formatPercent(ratio(currentItem.activeSubscriptions, totalActiveSubscriptions(currentRows))),
                formatPercent(ratio(currentItem.billingRetry, currentItem.activeSubscriptions)),
                formatPercent(ratio(currentItem.gracePeriod, currentItem.activeSubscriptions)),
            ]
        }
        guard rows.isEmpty == false else { return nil }
        return BriefSummarySection(
            title: "Subscription Plan Mix",
            note: "Latest subscription snapshot inside each range.",
            table: TableModel(
                columns: ["plan", "active", "change", "share", "retryRate", "graceRate"],
                rows: rows
            )
        )
    }

    private func makeSubscriptionSnapshotSection(
        title: String,
        note: String?,
        current: [QueryRecord],
        previous: [QueryRecord],
        keyName: String
    ) -> BriefSummarySection? {
        let currentGroups = subscriptionSnapshotMetrics(rows: latestSnapshotRows(current), keyName: keyName)
        let previousGroups = subscriptionSnapshotMetrics(rows: latestSnapshotRows(previous), keyName: keyName)
        let keys = Array(Set(currentGroups.keys).union(previousGroups.keys))
            .sorted { (currentGroups[$0]?.activeSubscriptions ?? 0) > (currentGroups[$1]?.activeSubscriptions ?? 0) }
            .prefix(8)

        let rows = keys.compactMap { key -> [String]? in
            let currentItem = currentGroups[key] ?? SubscriptionSnapshotMetrics()
            let previousItem = previousGroups[key] ?? SubscriptionSnapshotMetrics()
            guard currentItem.activeSubscriptions != 0 || previousItem.activeSubscriptions != 0 else { return nil }
            return [
                key,
                formatNumber(currentItem.activeSubscriptions),
                formatDeltaPercent(current: currentItem.activeSubscriptions, previous: previousItem.activeSubscriptions),
                formatPercent(ratio(currentItem.billingRetry, currentItem.activeSubscriptions)),
                formatPercent(ratio(currentItem.gracePeriod, currentItem.activeSubscriptions)),
            ]
        }
        guard rows.isEmpty == false else { return nil }
        return BriefSummarySection(
            title: title,
            note: note,
            table: TableModel(
                columns: [keyName, "active", "change", "retryRate", "graceRate"],
                rows: rows
            )
        )
    }

    private func makeEventMixSection(current: [QueryRecord], previous: [QueryRecord]) -> BriefSummarySection? {
        let currentMix = eventMix(records: current)
        let previousMix = eventMix(records: previous)
        let order = ["Renew", "Cancel", "Retry", "Other"]
        let rows = order.compactMap { key -> [String]? in
            let currentValue = currentMix[key] ?? 0
            let previousValue = previousMix[key] ?? 0
            guard currentValue != 0 || previousValue != 0 else { return nil }
            return [
                key,
                formatNumber(currentValue),
                formatDeltaPercent(current: currentValue, previous: previousValue),
                formatPercent(ratio(currentValue, currentMix.values.reduce(0, +))),
            ]
        }
        guard rows.isEmpty == false else { return nil }
        return BriefSummarySection(
            title: "Subscription Event Mix",
            note: nil,
            table: TableModel(
                columns: ["event", "count", "change", "share"],
                rows: rows
            )
        )
    }

    private func makeCancelReasonSection(current: [QueryRecord], previous: [QueryRecord]) -> BriefSummarySection? {
        let currentReasons = cancelReasons(records: current)
        let previousReasons = cancelReasons(records: previous)
        let keys = Array(Set(currentReasons.keys).union(previousReasons.keys))
            .sorted { (currentReasons[$0] ?? 0) > (currentReasons[$1] ?? 0) }
            .prefix(8)

        let rows = keys.compactMap { key -> [String]? in
            let currentValue = currentReasons[key] ?? 0
            let previousValue = previousReasons[key] ?? 0
            guard currentValue != 0 || previousValue != 0 else { return nil }
            return [
                key,
                formatNumber(currentValue),
                formatDeltaPercent(current: currentValue, previous: previousValue),
            ]
        }
        guard rows.isEmpty == false else { return nil }
        return BriefSummarySection(
            title: "Cancel Reasons",
            note: "Derived from subscription-event names.",
            table: TableModel(
                columns: ["reason", "count", "change"],
                rows: rows
            )
        )
    }

    private func makeComparisonSection(
        title: String,
        note: String?,
        result: QueryResult,
        groupKey: String,
        sortMetric: String,
        columns: [String],
        limit: Int
    ) -> BriefSummarySection {
        let rows = result.data.comparisons
            .sorted { ($0.metrics[sortMetric]?.current ?? 0) > ($1.metrics[sortMetric]?.current ?? 0) }
            .prefix(limit)
            .filter { row in
                shouldIncludeComparisonRow(row, columns: columns, sortMetric: sortMetric)
            }
            .map { row in
                columns.map { column in
                    formattedComparisonCell(column: column, row: row, groupKey: groupKey)
                }
            }

        return BriefSummarySection(
            title: title,
            note: note,
            table: TableModel(columns: columns, rows: rows)
        )
    }

    private func makeDataHealthSection(
        period: BriefSummaryPeriod,
        currentSales: [QueryRecord],
        currentSubscriptions: [QueryRecord],
        currentReviews: [QueryRecord],
        previousReviews: [QueryRecord],
        currentFinance: [QueryRecord]
    ) -> BriefSummarySection {
        let rows = [
            ["reportingCurrency", reportingCurrency],
            ["currentRange", period.currentWindow.startDatePT + " to " + period.currentWindow.endDatePT],
            ["compareRange", period.previousWindow.startDatePT + " to " + period.previousWindow.endDatePT],
            ["salesAsOf", salesAsOfValue(period: period, currentSales: currentSales)],
            ["subscriptionAsOf", maxDateString(currentSubscriptions)],
            ["reviewsAsOf", maxDateString(currentReviews)],
            ["salesCoverageDays", String(salesCoverageDays(period: period, currentSales: currentSales))],
            ["subscriptionCoverageDays", String(distinctDates(currentSubscriptions).count)],
            ["reviewCoverageDays", String(max(distinctDates(currentReviews).count, distinctDates(previousReviews).count))],
        ] + financeHealthRows(period: period, currentFinance: currentFinance)

        return BriefSummarySection(
            title: "Data Health",
            note: nil,
            table: TableModel(columns: ["item", "value"], rows: rows)
        )
    }

    private func deduplicatedWarnings(_ warnings: [QueryWarning]) -> [QueryWarning] {
        var seen: Set<String> = []
        return warnings.filter { warning in
            seen.insert("\(warning.code)|\(warning.message)").inserted
        }
    }

    private func shouldIncludeComparisonRow(
        _ row: QueryComparisonRow,
        columns: [String],
        sortMetric: String
    ) -> Bool {
        if (row.metrics[sortMetric]?.current ?? 0) != 0 || (row.metrics[sortMetric]?.previous ?? 0) != 0 {
            return true
        }

        let displayedMetrics = columns.compactMap(metricName(for:))
        return displayedMetrics.contains { metric in
            (row.metrics[metric]?.current ?? 0) != 0
        }
    }

    private func metricName(for column: String) -> String? {
        switch column {
        case "change":
            return nil
        case "averageRating":
            return "averageRating"
        case "repliedRate":
            return "repliedRate"
        default:
            return column
        }
    }

    private func financeHealthRows(period: BriefSummaryPeriod, currentFinance: [QueryRecord]) -> [[String]] {
        guard period.includesFinance else { return [] }
        return [
            ["financeFiscalMonth", period.currentWindow.endDate.fiscalMonthString],
            ["financeRows", String(currentFinance.count)],
        ]
    }

    private func salesAsOfValue(period: BriefSummaryPeriod, currentSales: [QueryRecord]) -> String {
        if period == .monthly, currentSales.isEmpty == false {
            return period.currentWindow.endDatePT
        }
        return maxDateString(currentSales)
    }

    private func salesCoverageDays(period: BriefSummaryPeriod, currentSales: [QueryRecord]) -> Int {
        if period == .monthly, currentSales.isEmpty == false {
            let days = Calendar.pacific.dateComponents([.day], from: period.currentWindow.startDate, to: period.currentWindow.endDate).day ?? 0
            return days + 1
        }
        return distinctDates(currentSales).count
    }

    private func latestSnapshotRows(_ records: [QueryRecord]) -> [QueryRecord] {
        guard let latestDate = records.compactMap({ $0.dimensions["date"] }).max() else { return [] }
        return records.filter { $0.dimensions["date"] == latestDate }
    }

    private func maxDateString(_ records: [QueryRecord]) -> String {
        records.compactMap { $0.dimensions["date"] }.max() ?? "-"
    }

    private func distinctDates(_ records: [QueryRecord]) -> Set<String> {
        Set(records.compactMap { $0.dimensions["date"] })
    }

    private func sumMetric(_ records: [QueryRecord], _ name: String) -> Double {
        records.reduce(0) { $0 + ($1.metrics[name] ?? 0) }
    }

    private func totalActiveSubscriptions(_ records: [QueryRecord]) -> Double {
        sumMetric(records, "activeSubscriptions")
    }

    private func productMetrics(records: [QueryRecord]) -> [String: ProductMetrics] {
        records.reduce(into: [String: ProductMetrics]()) { partial, record in
            let name = record.dimensions["name"] ?? record.dimensions["sku"] ?? "Unknown"
            let sku = record.dimensions["sku"] ?? ""
            let key = sku.isEmpty ? name : sku
            var item = partial[key] ?? ProductMetrics(name: name, sku: sku, proceeds: 0, units: 0, purchases: 0)
            item.name = item.name.isEmpty ? name : item.name
            item.sku = item.sku.isEmpty ? sku : item.sku
            item.proceeds += record.metrics["proceeds"] ?? 0
            item.units += record.metrics["units"] ?? 0
            item.purchases += record.metrics["purchases"] ?? 0
            partial[key] = item
        }
    }

    private func subscriptionSnapshotMetrics(rows: [QueryRecord], keyName: String) -> [String: SubscriptionSnapshotMetrics] {
        rows.reduce(into: [String: SubscriptionSnapshotMetrics]()) { partial, record in
            let key: String
            if keyName == "plan" {
                key = classifyPlan(
                    title: record.dimensions["subscription"] ?? "",
                    sku: record.dimensions["subscriptionDuration"] ?? record.dimensions["sku"] ?? ""
                )
            } else {
                key = (record.dimensions[keyName] ?? "").isEmpty ? "Unknown" : (record.dimensions[keyName] ?? "")
            }
            var value = partial[key] ?? SubscriptionSnapshotMetrics()
            value.activeSubscriptions += record.metrics["activeSubscriptions"] ?? 0
            value.billingRetry += record.metrics["billingRetry"] ?? 0
            value.gracePeriod += record.metrics["gracePeriod"] ?? 0
            value.subscribers += record.metrics["subscribers"] ?? 0
            value.proceeds += record.metrics["proceeds"] ?? 0
            partial[key] = value
        }
    }

    private func eventMix(records: [QueryRecord]) -> [String: Double] {
        records.reduce(into: [String: Double]()) { partial, record in
            let eventName = record.dimensions["eventName"] ?? ""
            let key = categorizeEvent(eventName)
            partial[key, default: 0] += abs(record.metrics["eventCount"] ?? record.metrics["units"] ?? 0)
        }
    }

    private func cancelReasons(records: [QueryRecord]) -> [String: Double] {
        records.reduce(into: [String: Double]()) { partial, record in
            let eventName = record.dimensions["eventName"] ?? ""
            guard categorizeEvent(eventName) == "Cancel" else { return }
            let key = eventName.isEmpty ? "Cancel" : eventName
            partial[key, default: 0] += abs(record.metrics["eventCount"] ?? record.metrics["units"] ?? 0)
        }
    }

    private func categorizeEvent(_ raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("renewal from billing retry") {
            return "Renew"
        }
        if value.contains("renew") || value.contains("reactivate") || value.contains("resubscribe") {
            return "Renew"
        }
        if value.contains("subscribe") && !value.contains("unsubscribe") {
            return "Renew"
        }
        if value.contains("start") || value.contains("upgrade") || value.contains("downgrade") {
            return "Renew"
        }
        if value.contains("cancel") || value.contains("unsubscribe") || value.contains("expire") || value.contains("refund") {
            return "Cancel"
        }
        if value.contains("retry") || value.contains("billing") || value.contains("grace") || value.contains("recover") || value.contains("win-back") {
            return "Retry"
        }
        return "Other"
    }

    private func classifyPlan(title: String, sku: String) -> String {
        let normalizedSKU = sku.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let lifeTokens = ["lifetime", "forever", "life", "one-time", "onetime", "buyout", "终身", "永久", "买断"]
        if lifeTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return "Lifetime"
        }

        let yearlyTokens = ["annually", "annual", "yearly", "year", "yr", "p1y", "1y", "12m", "年", "年度"]
        if yearlyTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return "Yearly"
        }

        let monthlyTokens = ["monthlly", "monthly", "month", "p1m", "1m", "月", "月度"]
        if monthlyTokens.contains(where: { normalizedSKU.contains($0) || normalizedTitle.contains($0) }) {
            return "Monthly"
        }

        return "Other"
    }

    private func overviewRow(_ metric: String, _ current: Double, _ previous: Double, _ style: BriefValueStyle) -> [String] {
        [
            metric,
            formatValue(current, style: style),
            formatValue(previous, style: style),
            formatDeltaPercent(current: current, previous: previous),
        ]
    }

    private func formattedComparisonCell(column: String, row: QueryComparisonRow, groupKey: String) -> String {
        if column == groupKey {
            let raw = row.group[groupKey] ?? ""
            return raw.isEmpty ? "Unknown" : raw
        }

        switch column {
        case "change":
            let metric = row.metrics["proceeds"] ?? row.metrics["count"] ?? row.metrics["activeSubscriptions"] ?? row.metrics["amount"] ?? row.metrics["units"]
            return metric.flatMap { formatPercent($0.deltaPercent) } ?? "-"
        case "averageRating":
            return formatDecimal(row.metrics["averageRating"]?.current ?? 0)
        case "repliedRate":
            return formatPercent(row.metrics["repliedRate"]?.current)
        case "proceeds":
            return formatCurrency(row.metrics["proceeds"]?.current ?? 0)
        case "amount":
            return formatCurrency(row.metrics["amount"]?.current ?? 0)
        case "count":
            return formatNumber(row.metrics["count"]?.current ?? 0)
        default:
            return formatValue(row.metrics[column]?.current ?? 0, style: styleForColumn(column))
        }
    }

    private func styleForColumn(_ column: String) -> BriefValueStyle {
        switch column {
        case "proceeds", "amount":
            return .currency
        case "averageRating":
            return .decimal
        case "repliedRate":
            return .percentage
        default:
            return .number
        }
    }

    private func formatValue(_ value: Double, style: BriefValueStyle) -> String {
        switch style {
        case .currency:
            return formatCurrency(value)
        case .number:
            return formatNumber(value)
        case .decimal:
            return formatDecimal(value)
        case .percentage:
            return formatPercent(value)
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        "\(reportingCurrency) " + String(format: "%.2f", value)
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private func formatDecimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f%%", value * 100)
    }

    private func formatDeltaPercent(current: Double, previous: Double) -> String {
        if previous == 0 {
            return current == 0 ? "0.00%" : "-"
        }
        return formatPercent((current - previous) / previous)
    }

    private func ratio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator != 0 else { return 0 }
        return numerator / denominator
    }
}

private enum BriefValueStyle {
    case currency
    case number
    case decimal
    case percentage
}

private struct ProductMetrics {
    var name: String
    var sku: String
    var proceeds: Double
    var units: Double
    var purchases: Double
}

private struct SubscriptionSnapshotMetrics {
    var activeSubscriptions: Double = 0
    var billingRetry: Double = 0
    var gracePeriod: Double = 0
    var subscribers: Double = 0
    var proceeds: Double = 0
}
