//
//  OfflineReferenceCatalog.swift
//  GoldenArchive
//
//  Data layer — a small built-in list of widely documented circulation and
//  bullion types, so the review step works without a network or API key.
//  It carries no images and no prices.
//

import Foundation

final class OfflineReferenceCatalog: CatalogSource {
    let name = "Offline reference"

    private struct Entry {
        var id: String
        var title: String
        var country: String
        var minYear: Int
        var maxYear: Int?
        var denomination: String
        var mints: [String]
        var material: String
        var diameterMM: Double?
        var weightGrams: Double?
        var edge: String
        var kind: ItemKind = .coin
        var keywords: String = ""
    }

    private let entries: [Entry] = [
        Entry(id: "us-cent-shield", title: "Lincoln Cent — Union Shield reverse", country: "United States", minYear: 2010, maxYear: nil,
              denomination: "1 cent", mints: ["P", "D", "S"], material: "Copper-plated zinc", diameterMM: 19.05, weightGrams: 2.5, edge: "Plain", keywords: "penny lincoln"),
        Entry(id: "us-nickel-jefferson", title: "Jefferson Nickel", country: "United States", minYear: 1938, maxYear: nil,
              denomination: "5 cents", mints: ["P", "D", "S"], material: "Copper-nickel (75% Cu, 25% Ni)", diameterMM: 21.21, weightGrams: 5.0, edge: "Plain", keywords: "nickel jefferson"),
        Entry(id: "us-dime-roosevelt", title: "Roosevelt Dime (clad)", country: "United States", minYear: 1965, maxYear: nil,
              denomination: "10 cents", mints: ["P", "D", "S"], material: "Copper-nickel clad copper", diameterMM: 17.91, weightGrams: 2.268, edge: "Reeded", keywords: "dime roosevelt"),
        Entry(id: "us-quarter-washington", title: "Washington Quarter (clad)", country: "United States", minYear: 1965, maxYear: 1998,
              denomination: "25 cents", mints: ["P", "D", "S"], material: "Copper-nickel clad copper", diameterMM: 24.26, weightGrams: 5.67, edge: "Reeded", keywords: "quarter washington"),
        Entry(id: "us-quarter-states", title: "50 State Quarters program", country: "United States", minYear: 1999, maxYear: 2008,
              denomination: "25 cents", mints: ["P", "D", "S"], material: "Copper-nickel clad copper", diameterMM: 24.26, weightGrams: 5.67, edge: "Reeded", keywords: "quarter state"),
        Entry(id: "us-half-kennedy", title: "Kennedy Half Dollar (clad)", country: "United States", minYear: 1971, maxYear: nil,
              denomination: "50 cents", mints: ["P", "D", "S"], material: "Copper-nickel clad copper", diameterMM: 30.61, weightGrams: 11.34, edge: "Reeded", keywords: "half dollar kennedy"),
        Entry(id: "us-dollar-morgan", title: "Morgan Dollar", country: "United States", minYear: 1878, maxYear: 1921,
              denomination: "1 dollar", mints: ["P", "O", "S", "CC", "D"], material: "Silver .900", diameterMM: 38.1, weightGrams: 26.73, edge: "Reeded", keywords: "morgan silver dollar"),
        Entry(id: "us-dollar-peace", title: "Peace Dollar", country: "United States", minYear: 1921, maxYear: 1935,
              denomination: "1 dollar", mints: ["P", "D", "S"], material: "Silver .900", diameterMM: 38.1, weightGrams: 26.73, edge: "Reeded", keywords: "peace silver dollar"),
        Entry(id: "us-silver-eagle", title: "American Silver Eagle", country: "United States", minYear: 1986, maxYear: nil,
              denomination: "1 dollar", mints: ["P", "S", "W"], material: "Silver .999", diameterMM: 40.6, weightGrams: 31.103, edge: "Reeded", keywords: "eagle bullion walking liberty"),
        Entry(id: "ca-silver-maple", title: "Silver Maple Leaf", country: "Canada", minYear: 1988, maxYear: nil,
              denomination: "5 dollars", mints: [], material: "Silver .9999", diameterMM: 38.0, weightGrams: 31.11, edge: "Reeded", keywords: "maple leaf bullion"),
        Entry(id: "za-krugerrand", title: "Krugerrand (1 oz)", country: "South Africa", minYear: 1967, maxYear: nil,
              denomination: "1 oz (no face value)", mints: [], material: "Gold .9167", diameterMM: 32.77, weightGrams: 33.93, edge: "Reeded", keywords: "krugerrand springbok bullion"),
        Entry(id: "ch-5-francs", title: "5 Francs — Alpine herdsman", country: "Switzerland", minYear: 1968, maxYear: nil,
              denomination: "5 francs", mints: ["B"], material: "Copper-nickel", diameterMM: 31.45, weightGrams: 13.2, edge: "Lettered", keywords: "franken franc helvetia"),
        Entry(id: "gb-pound-12", title: "£1 — twelve-sided", country: "United Kingdom", minYear: 2016, maxYear: nil,
              denomination: "1 pound", mints: [], material: "Bimetallic: nickel-brass ring, nickel-plated alloy centre", diameterMM: 23.43, weightGrams: 8.75, edge: "Alternating milled and plain sections", keywords: "pound sterling"),
        Entry(id: "gb-2-pounds", title: "£2 — bimetallic", country: "United Kingdom", minYear: 1997, maxYear: nil,
              denomination: "2 pounds", mints: [], material: "Bimetallic: nickel-brass ring, copper-nickel centre", diameterMM: 28.4, weightGrams: 12.0, edge: "Lettered (varies by issue)", keywords: "two pounds sterling"),
        Entry(id: "eu-1c", title: "1 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "1 cent", mints: [], material: "Copper-covered steel", diameterMM: 16.25, weightGrams: 2.3, edge: "Smooth", keywords: "euro cent"),
        Entry(id: "eu-2c", title: "2 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "2 cent", mints: [], material: "Copper-covered steel", diameterMM: 18.75, weightGrams: 3.06, edge: "Smooth with a groove", keywords: "euro cent"),
        Entry(id: "eu-5c", title: "5 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "5 cent", mints: [], material: "Copper-covered steel", diameterMM: 21.25, weightGrams: 3.92, edge: "Smooth", keywords: "euro cent"),
        Entry(id: "eu-10c", title: "10 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "10 cent", mints: [], material: "Nordic gold", diameterMM: 19.75, weightGrams: 4.1, edge: "Shaped with fine scallops", keywords: "euro cent"),
        Entry(id: "eu-20c", title: "20 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "20 cent", mints: [], material: "Nordic gold", diameterMM: 22.25, weightGrams: 5.74, edge: "Plain with seven indents", keywords: "euro cent"),
        Entry(id: "eu-50c", title: "50 euro cent", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "50 cent", mints: [], material: "Nordic gold", diameterMM: 24.25, weightGrams: 7.8, edge: "Shaped with fine scallops", keywords: "euro cent"),
        Entry(id: "eu-1e", title: "1 euro", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "1 euro", mints: [], material: "Bimetallic: nickel-brass ring, copper-nickel centre", diameterMM: 23.25, weightGrams: 7.5, edge: "Interrupted milling", keywords: "euro"),
        Entry(id: "eu-2e", title: "2 euro", country: "Eurozone", minYear: 1999, maxYear: nil,
              denomination: "2 euro", mints: [], material: "Bimetallic: copper-nickel ring, nickel-brass centre", diameterMM: 25.75, weightGrams: 8.5, edge: "Fine milling with lettering (varies by country)", keywords: "euro commemorative")
    ]

    func search(_ query: CatalogQuery) async throws -> [CatalogCandidate] {
        let text = query.text.normalizedKey
        let terms = text.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        let matches = entries.filter { entry in
            if query.kind != entry.kind { return false }
            var signals = 0
            var conflicts = 0
            if !query.country.isBlank {
                if MetadataMatcher.countriesMatch(query.country, entry.country)
                    || (entry.country == "Eurozone" && !["united states", "united kingdom", "canada", "south africa", "switzerland"].contains(MetadataMatcher.canonicalCountry(query.country))) {
                    signals += 1
                } else {
                    conflicts += 1
                }
            }
            if let year = query.year {
                if year >= entry.minYear && year <= (entry.maxYear ?? Int.max) { signals += 1 } else { conflicts += 1 }
            }
            if !query.denomination.isBlank {
                if MetadataMatcher.denominationsMatch(query.denomination, entry.denomination) { signals += 1 } else { conflicts += 1 }
            }
            if !terms.isEmpty {
                let haystack = "\(entry.title) \(entry.country) \(entry.denomination) \(entry.keywords) \(entry.material)".normalizedKey
                if terms.contains(where: { haystack.contains($0) }) { signals += 1 }
            }
            return signals > 0 && conflicts <= 1
        }
        return matches.prefix(12).map { entry in
            CatalogCandidate(
                id: "\(name):\(entry.id)",
                sourceName: name,
                externalID: entry.id,
                title: entry.title,
                country: entry.country,
                minYear: entry.minYear,
                maxYear: entry.maxYear,
                denomination: entry.denomination,
                mints: entry.mints,
                material: entry.material,
                diameterMM: entry.diameterMM,
                weightGrams: entry.weightGrams,
                edge: entry.edge,
                imageURL: nil,
                imageCredit: nil,
                pageURL: nil,
                hasDetails: true
            )
        }
    }

    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate { candidate }
}

/// Queries every enabled source and keeps each source's error separate, so
/// one failing source never hides the others or blocks manual entry.
final class CompositeCatalogRepository: CatalogRepository {
    private let offline: CatalogSource
    private let numista: NumistaCatalogSource
    private let settings: SettingsRepository
    private let credentials: CredentialStore

    init(offline: CatalogSource, numista: NumistaCatalogSource, settings: SettingsRepository, credentials: CredentialStore) {
        self.offline = offline
        self.numista = numista
        self.settings = settings
        self.credentials = credentials
    }

    @MainActor private func enabledSources() -> [CatalogSource] {
        let current = settings.settings()
        numista.language = current.catalogLanguage
        var sources: [CatalogSource] = []
        if current.offlineReferenceEnabled { sources.append(offline) }
        if current.numistaEnabled { sources.append(numista) }
        return sources
    }

    var activeSourceNames: [String] {
        let current = settings.settings()
        var names: [String] = []
        if current.offlineReferenceEnabled { names.append(offline.name) }
        if current.numistaEnabled { names.append(numista.name) }
        return names
    }

    func search(_ query: CatalogQuery) async -> CatalogSearchResult {
        let sources = await enabledSources()
        guard !sources.isEmpty else { return .empty }
        var candidates: [CatalogCandidate] = []
        var errors: [String: String] = [:]
        await withTaskGroup(of: (String, Result<[CatalogCandidate], Error>).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source.name, .success(try await source.search(query))) }
                    catch { return (source.name, .failure(error)) }
                }
            }
            for await (name, result) in group {
                switch result {
                case .success(let found): candidates.append(contentsOf: found)
                case .failure(let error): errors[name] = error.localizedDescription
                }
            }
        }
        return CatalogSearchResult(candidates: candidates, sourcesQueried: sources.map(\.name), sourceErrors: errors)
    }

    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate {
        if candidate.sourceName == numista.name { return try await numista.details(for: candidate) }
        return try await offline.details(for: candidate)
    }
}
