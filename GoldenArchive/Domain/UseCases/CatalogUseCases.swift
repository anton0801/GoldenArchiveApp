//
//  CatalogUseCases.swift
//  GoldenArchive
//
//  Domain layer — compares catalog suggestions with what the user entered.
//  The result describes metadata agreement only; the user always decides.
//

import Foundation

struct AssessedCandidate: Identifiable, Hashable {
    var candidate: CatalogCandidate
    var assessment: CandidateAssessment
    var id: String { candidate.id }
}

struct MetadataMatcher {
    private static let countryAliases: [String: String] = [
        "usa": "united states", "us": "united states", "u.s.": "united states", "u.s.a.": "united states",
        "united states of america": "united states", "america": "united states",
        "uk": "united kingdom", "great britain": "united kingdom", "britain": "united kingdom",
        "england": "united kingdom", "gb": "united kingdom",
        "euro area": "eurozone", "euro zone": "eurozone", "european union": "eurozone", "eu": "eurozone",
        "rsa": "south africa", "deutschland": "germany", "suisse": "switzerland", "schweiz": "switzerland",
        "ussr": "soviet union", "cccp": "soviet union"
    ]

    private static let numberWords: [String: String] = [
        "one": "1", "two": "2", "three": "3", "five": "5", "ten": "10", "twenty": "20", "fifty": "50",
        "half": "1/2", "quarter": "25"
    ]

    static func canonicalCountry(_ value: String) -> String {
        let key = value.normalizedKey
        return countryAliases[key] ?? key
    }

    static func countriesMatch(_ a: String, _ b: String) -> Bool {
        let ca = canonicalCountry(a), cb = canonicalCountry(b)
        guard !ca.isEmpty, !cb.isEmpty else { return false }
        return ca == cb || ca.contains(cb) || cb.contains(ca)
    }

    static func denominationTokens(_ value: String) -> (numbers: Set<String>, words: Set<String>) {
        var text: String = value.normalizedKey
        let symbols: [(String, String)] = [("$", " dollar "), ("€", " euro "), ("£", " pound "), ("¢", " cent "), ("(", " "), (")", " ")]
        for (symbol, replacement) in symbols {
            text = text.replacingOccurrences(of: symbol, with: replacement)
        }
        var numbers = Set<String>()
        var words = Set<String>()
        for raw in text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "-" }) {
            let token = String(raw)
            if let mapped = numberWords[token] { numbers.insert(mapped); continue }
            if token.first?.isNumber == true {
                let digits = token.prefix { $0.isNumber || $0 == "." || $0 == "/" }
                numbers.insert(String(digits))
                let rest = token.dropFirst(digits.count)
                if rest.count >= 3 { words.insert(String(rest.prefix(4))) }
            } else if token.count >= 3 {
                words.insert(String(token.prefix(4)))
            }
        }
        return (numbers, words)
    }

    static func denominationsMatch(_ a: String, _ b: String) -> Bool {
        let ta = denominationTokens(a), tb = denominationTokens(b)
        let numbersAgree = ta.numbers.isEmpty || tb.numbers.isEmpty || !ta.numbers.isDisjoint(with: tb.numbers)
        let wordsAgree = ta.words.isEmpty || tb.words.isEmpty || !ta.words.isDisjoint(with: tb.words)
        return numbersAgree && wordsAgree && !(ta.numbers.isEmpty && ta.words.isEmpty)
    }

    static func assess(_ candidate: CatalogCandidate, against query: CatalogQuery) -> CandidateAssessment {
        var matched: [String] = []
        var differences: [AttributeDifference] = []

        if !query.country.isBlank, !candidate.country.isBlank {
            if countriesMatch(query.country, candidate.country) { matched.append("Country") }
            else { differences.append(AttributeDifference(field: "Country", entered: query.country, reference: candidate.country)) }
        }
        if let year = query.year, candidate.minYear != nil || candidate.maxYear != nil {
            let low = candidate.minYear ?? Int.min, high = candidate.maxYear ?? Int.max
            if (low...high).contains(year) { matched.append("Year") }
            else { differences.append(AttributeDifference(field: "Year", entered: YearText.display(year), reference: candidate.yearRangeText)) }
        }
        if !query.denomination.isBlank, !candidate.denomination.isBlank {
            if denominationsMatch(query.denomination, candidate.denomination) { matched.append("Denomination") }
            else { differences.append(AttributeDifference(field: "Denomination", entered: query.denomination, reference: candidate.denomination)) }
        }
        if !query.mint.isBlank, !candidate.mints.isEmpty {
            let key = query.mint.normalizedKey
            if candidate.mints.contains(where: { $0.normalizedKey.contains(key) || key.contains($0.normalizedKey) }) { matched.append("Mint mark") }
            else { differences.append(AttributeDifference(field: "Mint mark", entered: query.mint, reference: candidate.mints.joined(separator: ", "))) }
        }
        if !query.material.isBlank, !candidate.material.isBlank {
            let words = query.material.normalizedKey.split(separator: " ").map(String.init).filter { $0.count >= 3 }
            let reference = candidate.material.normalizedKey
            if words.contains(where: { reference.contains($0) }) { matched.append("Material") }
            else { differences.append(AttributeDifference(field: "Material", entered: query.material, reference: candidate.material)) }
        }

        var textScore = 0.0
        let terms = query.text.normalizedKey.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        if !terms.isEmpty {
            let title = candidate.title.normalizedKey
            textScore = Double(terms.filter { title.contains($0) }.count) / Double(terms.count)
        }

        let keyConflict = differences.contains { $0.field == "Country" || $0.field == "Year" }
        let strength: MatchStrength
        if matched.count >= 3 && !keyConflict { strength = .strong }
        else if matched.count >= 1 || textScore >= 0.5 { strength = keyConflict && matched.count < 2 ? .weak : .partial }
        else { strength = .weak }

        let score = Double(matched.count) * 2 - Double(differences.count) * 1.5 + textScore * 2
        return CandidateAssessment(strength: strength, matchedFields: matched, differences: differences, score: score)
    }
}

struct SearchCatalogUseCase {
    let catalog: CatalogRepository

    func execute(_ query: CatalogQuery) async -> (candidates: [AssessedCandidate], result: CatalogSearchResult) {
        let result = await catalog.search(query)
        let assessed = result.candidates
            .map { AssessedCandidate(candidate: $0, assessment: MetadataMatcher.assess($0, against: query)) }
            .sorted { $0.assessment.score > $1.assessment.score }
        return (assessed, result)
    }

    func details(for candidate: CatalogCandidate) async throws -> CatalogCandidate {
        guard !candidate.hasDetails else { return candidate }
        return try await catalog.details(for: candidate)
    }

    static func reference(for assessed: AssessedCandidate, at date: Date) -> CatalogReference {
        CatalogReference(
            sourceName: assessed.candidate.sourceName,
            externalID: assessed.candidate.externalID,
            title: assessed.candidate.title,
            url: assessed.candidate.pageURL?.absoluteString,
            retrievedAt: date,
            matchLabel: assessed.assessment.strength.label
        )
    }
}
