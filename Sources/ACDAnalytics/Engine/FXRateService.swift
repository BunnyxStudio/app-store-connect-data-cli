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

public struct FXLookupRequest: Hashable, Codable, Sendable {
    public var dateKey: String
    public var currencyCode: String

    public init(dateKey: String, currencyCode: String) {
        self.dateKey = dateKey
        self.currencyCode = currencyCode
    }

    public var recordKey: String {
        "\(dateKey)|\(currencyCode)"
    }
}

public enum FXRateServiceError: LocalizedError {
    case invalidURL
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to build FX rate request."
        case .provider(let message):
            return message
        }
    }
}

private struct CachedFXRate: Codable {
    var requestDateKey: String
    var sourceDateKey: String
    var sourceCurrencyCode: String
    var targetCurrencyCode: String
    var ratePerUnit: Double
    var fetchedAt: Date

    private enum CodingKeys: String, CodingKey {
        case requestDateKey
        case sourceDateKey
        case sourceCurrencyCode
        case targetCurrencyCode
        case ratePerUnit
        case fetchedAt
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case requestDateKey
        case sourceDateKey
        case currencyCode
        case usdPerUnit
        case fetchedAt
    }

    init(
        requestDateKey: String,
        sourceDateKey: String,
        sourceCurrencyCode: String,
        targetCurrencyCode: String,
        ratePerUnit: Double,
        fetchedAt: Date
    ) {
        self.requestDateKey = requestDateKey
        self.sourceDateKey = sourceDateKey
        self.sourceCurrencyCode = sourceCurrencyCode
        self.targetCurrencyCode = targetCurrencyCode
        self.ratePerUnit = ratePerUnit
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let requestDateKey = try container.decodeIfPresent(String.self, forKey: .requestDateKey),
           let sourceDateKey = try container.decodeIfPresent(String.self, forKey: .sourceDateKey),
           let sourceCurrencyCode = try container.decodeIfPresent(String.self, forKey: .sourceCurrencyCode),
           let targetCurrencyCode = try container.decodeIfPresent(String.self, forKey: .targetCurrencyCode),
           let ratePerUnit = try container.decodeIfPresent(Double.self, forKey: .ratePerUnit),
           let fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) {
            self.init(
                requestDateKey: requestDateKey,
                sourceDateKey: sourceDateKey,
                sourceCurrencyCode: sourceCurrencyCode,
                targetCurrencyCode: targetCurrencyCode,
                ratePerUnit: ratePerUnit,
                fetchedAt: fetchedAt
            )
            return
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.init(
            requestDateKey: try legacy.decode(String.self, forKey: .requestDateKey),
            sourceDateKey: try legacy.decode(String.self, forKey: .sourceDateKey),
            sourceCurrencyCode: try legacy.decode(String.self, forKey: .currencyCode),
            targetCurrencyCode: "USD",
            ratePerUnit: try legacy.decode(Double.self, forKey: .usdPerUnit),
            fetchedAt: try legacy.decode(Date.self, forKey: .fetchedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestDateKey, forKey: .requestDateKey)
        try container.encode(sourceDateKey, forKey: .sourceDateKey)
        try container.encode(sourceCurrencyCode, forKey: .sourceCurrencyCode)
        try container.encode(targetCurrencyCode, forKey: .targetCurrencyCode)
        try container.encode(ratePerUnit, forKey: .ratePerUnit)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    var cacheKey: String {
        "\(requestDateKey)|\(sourceCurrencyCode)|\(targetCurrencyCode)"
    }
}

private struct FetchedFXRate {
    var sourceDateKey: String
    var ratePerUnit: Double
}

private struct FrankfurterRateQuote: Decodable {
    var date: String
    var quote: String
    var rate: Double
}

private struct FrankfurterErrorResponse: Decodable {
    var message: String
}

public actor FXRateService {
    private let cacheURL: URL
    private let session: URLSession
    private let fileManager: FileManager
    private let baseURL = URL(string: "https://api.frankfurter.dev/v2/rates")!

    public init(cacheURL: URL, session: URLSession = .shared, fileManager: FileManager = .default) {
        self.cacheURL = cacheURL
        self.session = session
        self.fileManager = fileManager
    }

    public func resolveRates(
        for requests: Set<FXLookupRequest>,
        targetCurrencyCode: String,
        allowNetwork: Bool
    ) async throws -> [FXLookupRequest: Double] {
        guard requests.isEmpty == false else { return [:] }

        let normalizedTargetCurrency = targetCurrencyCode.normalizedCurrencyCode
        var cached = try loadCache()
        var resolved: [FXLookupRequest: Double] = [:]
        var missingByDate: [String: Set<String>] = [:]

        for request in requests {
            let normalizedCurrency = request.currencyCode.normalizedCurrencyCode
            if normalizedCurrency == normalizedTargetCurrency {
                resolved[request] = 1
                continue
            }
            if normalizedCurrency.isUnknownCurrencyCode {
                continue
            }
            let cacheKey = cacheKey(
                dateKey: request.dateKey,
                sourceCurrencyCode: normalizedCurrency,
                targetCurrencyCode: normalizedTargetCurrency
            )
            if let existing = cached[cacheKey], existing.ratePerUnit > 0 {
                resolved[request] = existing.ratePerUnit
                continue
            }
            if allowNetwork {
                missingByDate[request.dateKey, default: []].insert(normalizedCurrency)
            }
        }

        if allowNetwork, missingByDate.isEmpty == false {
            for (dateKey, currencies) in missingByDate {
                let fetched = try await fetchRates(
                    dateKey: dateKey,
                    currencies: Array(currencies),
                    targetCurrencyCode: normalizedTargetCurrency
                )
                for (currency, payload) in fetched {
                    let rate = CachedFXRate(
                        requestDateKey: dateKey,
                        sourceDateKey: payload.sourceDateKey,
                        sourceCurrencyCode: currency,
                        targetCurrencyCode: normalizedTargetCurrency,
                        ratePerUnit: payload.ratePerUnit,
                        fetchedAt: Date()
                    )
                    cached[rate.cacheKey] = rate
                }
            }
            try saveCache(cached)
        }

        for request in requests {
            let normalizedCurrency = request.currencyCode.normalizedCurrencyCode
            if normalizedCurrency == normalizedTargetCurrency {
                resolved[request] = 1
                continue
            }
            let key = cacheKey(
                dateKey: request.dateKey,
                sourceCurrencyCode: normalizedCurrency,
                targetCurrencyCode: normalizedTargetCurrency
            )
            if let existing = cached[key], existing.ratePerUnit > 0 {
                resolved[request] = existing.ratePerUnit
            }
        }

        return resolved
    }

    private func fetchRates(
        dateKey: String,
        currencies: [String],
        targetCurrencyCode: String
    ) async throws -> [String: FetchedFXRate] {
        guard currencies.isEmpty == false else { return [:] }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "date", value: dateKey),
            URLQueryItem(name: "base", value: targetCurrencyCode),
            URLQueryItem(name: "quotes", value: currencies.sorted().joined(separator: ","))
        ]
        guard let url = components?.url else {
            throw FXRateServiceError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        if let error = try? JSONDecoder().decode(FrankfurterErrorResponse.self, from: data) {
            throw FXRateServiceError.provider("FX provider error: \(error.message)")
        }

        let response = try JSONDecoder().decode([FrankfurterRateQuote].self, from: data)
        var result: [String: FetchedFXRate] = [:]
        for quote in response where quote.rate != 0 {
            result[quote.quote] = FetchedFXRate(
                sourceDateKey: quote.date,
                ratePerUnit: 1 / quote.rate
            )
        }
        return result
    }

    private func loadCache() throws -> [String: CachedFXRate] {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return [:] }
        try LocalFileSecurity.validateOwnerOnlyFile(cacheURL, fileManager: fileManager)
        let data = try Data(contentsOf: cacheURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([String: CachedFXRate].self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.values.map { ($0.cacheKey, $0) })
    }

    private func saveCache(_ cache: [String: CachedFXRate]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)
        try LocalFileSecurity.writePrivateData(data, to: cacheURL, fileManager: fileManager)
    }

    private func cacheKey(
        dateKey: String,
        sourceCurrencyCode: String,
        targetCurrencyCode: String
    ) -> String {
        "\(dateKey)|\(sourceCurrencyCode)|\(targetCurrencyCode)"
    }
}
