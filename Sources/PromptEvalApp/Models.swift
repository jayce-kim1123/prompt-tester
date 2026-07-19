import Foundation
import UniformTypeIdentifiers

enum ProviderKind: String, CaseIterable, Identifiable, Sendable {
    case gemini = "Gemini"
    case openAI = "OpenAI"

    var id: String { rawValue }
}

struct ModelOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct DatasetRow: Identifiable, Codable, Hashable {
    let id: UUID
    var values: [String: String]
    var llmInput: String?
    var output: String?
    var error: String?
    var outputModel: String?
    var latencyMilliseconds: Double?
    var inputTokens: Int?
    var outputTokens: Int?

    init(
        id: UUID = UUID(),
        values: [String: String],
        llmInput: String? = nil,
        output: String? = nil,
        error: String? = nil,
        outputModel: String? = nil,
        latencyMilliseconds: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.id = id
        self.values = values
        self.llmInput = llmInput
        self.output = output
        self.error = error
        self.outputModel = outputModel
        self.latencyMilliseconds = latencyMilliseconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

enum DatasetKind: String, Codable {
    case source
    case evaluation

    var displayName: String {
        switch self {
        case .source: "원본"
        case .evaluation: "LLM 실행"
        }
    }
}

struct SavedPrompt: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var content: String
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, content: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.updatedAt = updatedAt
    }
}

struct SavedDataset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var headers: [String]
    var rows: [DatasetRow]
    var fileExtension: String
    var createdAt: Date
    var updatedAt: Date
    var byteSize: Int
    var kind: DatasetKind
    var sourceDatasetName: String?
    var evaluationPromptName: String?
    var evaluationPrompt: String?
    var evaluationProvider: String?
    var evaluationModel: String?

    init(
        id: UUID = UUID(),
        name: String,
        headers: [String],
        rows: [DatasetRow],
        fileExtension: String,
        kind: DatasetKind = .source,
        sourceDatasetName: String? = nil,
        evaluationPromptName: String? = nil,
        evaluationPrompt: String? = nil,
        evaluationProvider: String? = nil,
        evaluationModel: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.headers = headers
        self.rows = rows
        self.fileExtension = fileExtension.lowercased()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.byteSize = Self.estimatedSize(headers: headers, rows: rows)
        self.kind = kind
        self.sourceDatasetName = sourceDatasetName
        self.evaluationPromptName = evaluationPromptName
        self.evaluationPrompt = evaluationPrompt
        self.evaluationProvider = evaluationProvider
        self.evaluationModel = evaluationModel
    }

    mutating func updateContents(headers: [String], rows: [DatasetRow]) {
        self.headers = headers
        self.rows = rows
        self.updatedAt = Date()
        self.byteSize = Self.estimatedSize(headers: headers, rows: rows)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, headers, rows, fileExtension, createdAt, updatedAt, byteSize
        case kind, sourceDatasetName, evaluationPromptName, evaluationPrompt, evaluationProvider, evaluationModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        headers = try container.decode([String].self, forKey: .headers)
        rows = try container.decode([DatasetRow].self, forKey: .rows)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let inferredExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
            ?? (inferredExtension.isEmpty ? "json" : inferredExtension)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
        byteSize = try container.decodeIfPresent(Int.self, forKey: .byteSize) ?? Self.estimatedSize(headers: headers, rows: rows)
        kind = try container.decodeIfPresent(DatasetKind.self, forKey: .kind) ?? .source
        sourceDatasetName = try container.decodeIfPresent(String.self, forKey: .sourceDatasetName)
        evaluationPromptName = try container.decodeIfPresent(String.self, forKey: .evaluationPromptName)
        evaluationPrompt = try container.decodeIfPresent(String.self, forKey: .evaluationPrompt)
        evaluationProvider = try container.decodeIfPresent(String.self, forKey: .evaluationProvider)
        evaluationModel = try container.decodeIfPresent(String.self, forKey: .evaluationModel)
    }

    private static func estimatedSize(headers: [String], rows: [DatasetRow]) -> Int {
        let headerSize = headers.reduce(0) { $0 + $1.lengthOfBytes(using: .utf8) }
        let rowSize = rows.reduce(0) { total, row in
            total + row.values.reduce(0) { $0 + $1.key.lengthOfBytes(using: .utf8) + $1.value.lengthOfBytes(using: .utf8) }
                + (row.llmInput?.lengthOfBytes(using: .utf8) ?? 0)
                + (row.output?.lengthOfBytes(using: .utf8) ?? 0)
                + (row.error?.lengthOfBytes(using: .utf8) ?? 0)
        }
        return headerSize + rowSize
    }
}

struct SavedLibrary: Codable {
    var prompts: [SavedPrompt]
    var datasets: [SavedDataset]

    static let empty = SavedLibrary(prompts: [], datasets: [])
}

struct EvaluationInput: Codable {
    let prompt: String
    let evaluationPrompt: String?
    let provider: String
    let model: String
    let rows: [DatasetRow]
    let datasetName: String?
    let sourceDatasetName: String?
    let promptName: String?
    let testCaseName: String?
    let criteria: [TestCriterionDefinition]?

    init(
        prompt: String,
        evaluationPrompt: String? = nil,
        provider: String,
        model: String,
        rows: [DatasetRow],
        datasetName: String? = nil,
        sourceDatasetName: String? = nil,
        promptName: String? = nil,
        testCaseName: String? = nil,
        criteria: [TestCriterionDefinition]? = nil
    ) {
        self.prompt = prompt
        self.evaluationPrompt = evaluationPrompt
        self.provider = provider
        self.model = model
        self.rows = rows
        self.datasetName = datasetName
        self.sourceDatasetName = sourceDatasetName
        self.promptName = promptName
        self.testCaseName = testCaseName
        self.criteria = criteria
    }
}

struct EvaluationRunSummary: Codable {
    let promptfooValidated: Int
    let promptfooPassed: Int
    let promptfooFailed: Int
    let codexRequested: Int
    let codexCompleted: Int
    let codexErrors: Int
    let codexPassed: Int
    let codexAverageScore: Double?
    let evaluationModel: String?
    let executedAt: Date?
    let passRate: Double?
    let averageLatencyMilliseconds: Double?
    let generationInputTokens: Int?
    let generationOutputTokens: Int?
    let evaluationInputTokens: Int?
    let evaluationOutputTokens: Int?
}

struct GenerationCheckpointRecord: Codable, Sendable {
    let datasetID: UUID
    let rowID: UUID
    let llmInput: String?
    let output: String?
    let error: String?
    let outputModel: String?
    let latencyMilliseconds: Double?
    let inputTokens: Int?
    let outputTokens: Int?
}

struct LLMGeneratedResponse: Sendable {
    let text: String
    let inputTokens: Int?
    let outputTokens: Int?
}

struct EvaluationCriterionResult: Codable, Identifiable {
    let name: String
    let expected: String
    let observed: String
    let pass: Bool
    let score: Int
    let reason: String

    var id: String { "\(name)|\(expected)|\(observed)" }
}

struct CodexJudgeResult: Codable {
    let pass: Bool
    let score: Int
    let reasons: [String]
    let criteria: [EvaluationCriterionResult]?
}

struct CodexJudgementRecord: Codable, Identifiable {
    let rowId: String
    let status: String
    let judge: CodexJudgeResult?
    let error: String?
    let evaluationModel: String?
    let evaluationInputTokens: Int?
    let evaluationOutputTokens: Int?
    let evaluatedAt: Date?

    var id: String { rowId }
}

struct EvaluationAuditLog: Codable {
    let schemaVersion: Int
    let evaluationID: String
    let executedAt: Date
    let input: EvaluationInput
    let summary: EvaluationRunSummary
    let judgements: [CodexJudgementRecord]
}

enum EvaluationLogIntegrity: Equatable {
    case verified
    case invalid
    case legacy

    var label: String {
        switch self {
        case .verified: "원본 확인됨"
        case .invalid: "로그 변조 감지"
        case .legacy: "이전 형식"
        }
    }

    var systemImage: String {
        switch self {
        case .verified: "checkmark.shield.fill"
        case .invalid: "exclamationmark.shield.fill"
        case .legacy: "clock.arrow.circlepath"
        }
    }
}

struct EvaluationResultRecord: Identifiable {
    let id: String
    let folderURL: URL
    let createdAt: Date
    let input: EvaluationInput
    let summary: EvaluationRunSummary?
    let judgements: [CodexJudgementRecord]
    let integrity: EvaluationLogIntegrity

    var isComplete: Bool { summary != nil }
    var executionDate: Date { summary?.executedAt ?? createdAt }
    var passRate: Double? {
        summary?.passRate ?? summary.flatMap { value in
            value.codexCompleted > 0 ? Double(value.codexPassed) / Double(value.codexCompleted) : nil
        }
    }
    var averageLatencyMilliseconds: Double? {
        summary?.averageLatencyMilliseconds ?? {
            let values = input.rows.compactMap(\.latencyMilliseconds)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }()
    }
    var evaluatedCSVURL: URL { folderURL.appendingPathComponent("results/evaluated-dataset.csv") }
    var evaluatedJSONURL: URL { folderURL.appendingPathComponent("results/evaluated-dataset.json") }
    var hasEvaluatedDataset: Bool {
        FileManager.default.fileExists(atPath: evaluatedCSVURL.path)
            && FileManager.default.fileExists(atPath: evaluatedJSONURL.path)
    }

    func datasetRow(for judgement: CodexJudgementRecord) -> DatasetRow? {
        input.rows.first { $0.id.uuidString.caseInsensitiveCompare(judgement.rowId) == .orderedSame }
    }

    func llmInput(for row: DatasetRow?) -> String? {
        guard let row else { return nil }
        if let llmInput = row.llmInput { return llmInput }
        return try? PromptTemplate.render(input.prompt, values: row.values)
    }
}

enum EvaluationExportFormat: Equatable {
    case csv
    case json

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .json: "json"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .json: .json
        }
    }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

enum PromptTemplate {
    private static let expression = try! NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}"#)

    static func variables(in prompt: String) -> [String] {
        let range = NSRange(prompt.startIndex..., in: prompt)
        let names = expression.matches(in: prompt, range: range).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: prompt) else { return nil }
            return String(prompt[range])
        }
        return Array(Set(names)).sorted()
    }

    static func render(_ prompt: String, values: [String: String]) throws -> String {
        let names = variables(in: prompt)
        let missing = names.filter { values[$0] == nil }
        guard missing.isEmpty else {
            throw AppError.message("데이터셋에 없는 변수입니다: \(missing.joined(separator: ", "))")
        }

        var output = prompt
        let range = NSRange(prompt.startIndex..., in: prompt)
        for match in expression.matches(in: prompt, range: range).reversed() {
            guard let fullRange = Range(match.range, in: output),
                  let nameRange = Range(match.range(at: 1), in: prompt) else { continue }
            output.replaceSubrange(fullRange, with: values[String(prompt[nameRange])] ?? "")
        }
        return output
    }
}

enum CSVCodec {
    static func decode(_ text: String) throws -> (headers: [String], rows: [DatasetRow]) {
        let records = try parse(text)
        guard let rawHeaders = records.first, !rawHeaders.isEmpty else {
            throw AppError.message("CSV에 헤더 행이 없습니다.")
        }

        let headers = rawHeaders.enumerated().map { index, value in
            var header = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0 {
                header = header.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            }
            return header
        }
        let emptyColumns = headers.enumerated().compactMap { index, header in
            header.isEmpty ? String(index + 1) : nil
        }
        let duplicateHeaders = Dictionary(grouping: headers, by: { $0 })
            .filter { !$0.key.isEmpty && $0.value.count > 1 }
            .map(\.key)
            .sorted()
        guard emptyColumns.isEmpty, duplicateHeaders.isEmpty else {
            var problems: [String] = []
            if !emptyColumns.isEmpty {
                problems.append("빈 열: \(emptyColumns.joined(separator: ", "))")
            }
            if !duplicateHeaders.isEmpty {
                problems.append("중복 헤더: \(duplicateHeaders.joined(separator: ", "))")
            }
            throw AppError.message("CSV 헤더를 확인해 주세요. \(problems.joined(separator: " / "))")
        }

        let rows = records.dropFirst().filter { !$0.allSatisfy { $0.isEmpty } }.map { record in
            var values: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                values[header] = index < record.count ? record[index] : ""
            }
            return DatasetRow(values: values)
        }
        return (headers, rows)
    }

    static func encode(headers: [String], rows: [DatasetRow]) -> String {
        var generatedHeaders: [String] = []
        if rows.contains(where: { $0.llmInput != nil }) && !headers.contains("llm_input") {
            generatedHeaders.append("llm_input")
        }
        if rows.contains(where: { $0.output != nil }) && !headers.contains("model_output") {
            generatedHeaders.append("model_output")
        }
        if rows.contains(where: { $0.error != nil }) && !headers.contains("generation_error") {
            generatedHeaders.append("generation_error")
        }
        if rows.contains(where: { $0.outputModel != nil }) && !headers.contains("output_model") {
            generatedHeaders.append("output_model")
        }
        if rows.contains(where: { $0.latencyMilliseconds != nil }) && !headers.contains("latency_ms") {
            generatedHeaders.append("latency_ms")
        }
        if rows.contains(where: { $0.inputTokens != nil }) && !headers.contains("input_tokens") {
            generatedHeaders.append("input_tokens")
        }
        if rows.contains(where: { $0.outputTokens != nil }) && !headers.contains("output_tokens") {
            generatedHeaders.append("output_tokens")
        }
        let allHeaders = headers + generatedHeaders
        let lines = [allHeaders] + rows.map { row in
            allHeaders.map { header in
                switch header {
                case "llm_input": row.llmInput ?? row.values[header] ?? ""
                case "model_output": row.output ?? row.values[header] ?? ""
                case "generation_error": row.error ?? row.values[header] ?? ""
                case "output_model": row.outputModel ?? row.values[header] ?? ""
                case "latency_ms": row.latencyMilliseconds.map { String(format: "%.1f", $0) } ?? row.values[header] ?? ""
                case "input_tokens": row.inputTokens.map(String.init) ?? row.values[header] ?? ""
                case "output_tokens": row.outputTokens.map(String.init) ?? row.values[header] ?? ""
                default: row.values[header] ?? ""
                }
            }
        }
        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parse(_ source: String) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        // Swift Character는 CRLF를 하나의 자소로 취급할 수 있으므로 스칼라 단위로 읽는다.
        let scalars = Array(source.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x22 {
                if quoted, index + 1 < scalars.count, scalars[index + 1].value == 0x22 {
                    field.append("\"")
                    index += 2
                    continue
                }
                quoted.toggle()
            } else if scalar.value == 0x2C, !quoted {
                record.append(field)
                field = ""
            } else if scalar.value == 0x0A, !quoted {
                record.append(field)
                records.append(record)
                record = []
                field = ""
            } else if scalar.value != 0x0D {
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }

        guard !quoted else {
            throw AppError.message("CSV의 따옴표가 닫히지 않았습니다.")
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

enum DatasetDecoder {
    static func json(_ data: Data) throws -> (headers: [String], rows: [DatasetRow]) {
        let object = try JSONSerialization.jsonObject(with: data)
        let records: [[String: Any]]
        if let array = object as? [[String: Any]] {
            records = array
        } else if let dictionary = object as? [String: Any], let array = dictionary["data"] as? [[String: Any]] {
            records = array
        } else {
            throw AppError.message("JSON은 객체 배열 또는 data 배열을 가진 객체여야 합니다.")
        }

        let headers = Array(Set(records.flatMap(\.keys))).sorted()
        let rows = records.map { record in
            DatasetRow(values: Dictionary(uniqueKeysWithValues: record.map { key, value in
                (key, stringify(value))
            }))
        }
        return (headers, rows)
    }

    static func rows(headers: [String], values: [[String]]) throws -> [DatasetRow] {
        guard !headers.isEmpty else { throw AppError.message("스프레드시트에 헤더 행이 없습니다.") }
        guard Set(headers).count == headers.count else { throw AppError.message("스프레드시트 헤더는 서로 달라야 합니다.") }
        return values.map { valueRow in
            var values: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                values[header] = index < valueRow.count ? valueRow[index] : ""
            }
            return DatasetRow(values: values)
        }
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }
}
