import Foundation

enum CriterionValueType: String, Codable, CaseIterable, Identifiable {
    case text = "문자열"
    case number = "숫자"
    case boolean = "Boolean"
    case json = "JSON"

    var id: String { rawValue }
}

enum PassRuleType: String, Codable, CaseIterable, Identifiable {
    case exact = "일치"
    case range = "범위"
    case contains = "포함"
    case exists = "값 존재"
    case arrayObjectCondition = "배열 객체 조건"

    static var allCases: [PassRuleType] {
        [.exact, .range, .contains, .exists, .arrayObjectCondition]
    }

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "위험 유형 및 점수 범위" {
            self = .arrayObjectCondition
        } else if let value = Self(rawValue: rawValue) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "알 수 없는 PASS 규칙입니다: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ArrayObjectAssertionKind: String, Codable, CaseIterable, Identifiable {
    case datasetValue = "데이터셋 값"
    case objectValueRange = "요소 값 범위"

    var id: String { rawValue }
}

struct ArrayObjectAssertion: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ArrayObjectAssertionKind
    var datasetField: String
    var expectedValue: String
    var objectField: String
    var minimumField: String
    var maximumField: String

    static func datasetValue(field: String = "", expectedValue: String = "1") -> Self {
        Self(
            kind: .datasetValue,
            datasetField: field,
            expectedValue: expectedValue,
            objectField: "",
            minimumField: "",
            maximumField: ""
        )
    }

    static func objectValueRange(objectField: String = "", minimumField: String = "", maximumField: String = "") -> Self {
        Self(
            kind: .objectValueRange,
            datasetField: "",
            expectedValue: "",
            objectField: objectField,
            minimumField: minimumField,
            maximumField: maximumField
        )
    }
}

struct ArrayObjectAssertionEvaluation: Identifiable {
    let assertion: ArrayObjectAssertion
    let expected: String
    let actual: String
    let passed: Bool

    var id: UUID { assertion.id }
}

struct TestCriterionDefinition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var expectedField: String
    var expectedMinField: String
    var expectedMaxField: String
    var outputPath: String
    var valueType: CriterionValueType
    var passRule: PassRuleType
    var matchField: String?
    var matchValue: String?
    var valueField: String?
    var arrayAssertions: [ArrayObjectAssertion]

    init(
        id: UUID = UUID(),
        name: String,
        expectedField: String,
        expectedMinField: String,
        expectedMaxField: String,
        outputPath: String,
        valueType: CriterionValueType,
        passRule: PassRuleType,
        matchField: String? = nil,
        matchValue: String? = nil,
        valueField: String? = nil,
        arrayAssertions: [ArrayObjectAssertion] = []
    ) {
        self.id = id
        self.name = name
        self.expectedField = expectedField
        self.expectedMinField = expectedMinField
        self.expectedMaxField = expectedMaxField
        self.outputPath = outputPath
        self.valueType = valueType
        self.passRule = passRule
        self.matchField = matchField
        self.matchValue = matchValue
        self.valueField = valueField
        self.arrayAssertions = arrayAssertions
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, expectedField, expectedMinField, expectedMaxField, outputPath
        case valueType, passRule, matchField, matchValue, valueField, arrayAssertions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        expectedField = try container.decode(String.self, forKey: .expectedField)
        expectedMinField = try container.decode(String.self, forKey: .expectedMinField)
        expectedMaxField = try container.decode(String.self, forKey: .expectedMaxField)
        outputPath = try container.decode(String.self, forKey: .outputPath)
        valueType = try container.decode(CriterionValueType.self, forKey: .valueType)
        passRule = try container.decode(PassRuleType.self, forKey: .passRule)
        matchField = try container.decodeIfPresent(String.self, forKey: .matchField)
        matchValue = try container.decodeIfPresent(String.self, forKey: .matchValue)
        valueField = try container.decodeIfPresent(String.self, forKey: .valueField)
        arrayAssertions = try container.decodeIfPresent([ArrayObjectAssertion].self, forKey: .arrayAssertions) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(expectedField, forKey: .expectedField)
        try container.encode(expectedMinField, forKey: .expectedMinField)
        try container.encode(expectedMaxField, forKey: .expectedMaxField)
        try container.encode(outputPath, forKey: .outputPath)
        try container.encode(valueType, forKey: .valueType)
        try container.encode(passRule, forKey: .passRule)
        try container.encodeIfPresent(matchField, forKey: .matchField)
        try container.encodeIfPresent(matchValue, forKey: .matchValue)
        try container.encodeIfPresent(valueField, forKey: .valueField)
        try container.encode(arrayAssertions, forKey: .arrayAssertions)
    }

    func withDefaultArrayAssertions() -> Self {
        guard passRule == .arrayObjectCondition, arrayAssertions.isEmpty else { return self }
        var copy = self
        if !expectedField.isEmpty {
            copy.arrayAssertions.append(.datasetValue(field: expectedField))
        }
        let defaultValueField = valueField.flatMap { $0.isEmpty ? nil : $0 } ?? "risk_score"
        if !expectedMinField.isEmpty, !expectedMaxField.isEmpty {
            copy.arrayAssertions.append(.objectValueRange(
                objectField: defaultValueField,
                minimumField: expectedMinField,
                maximumField: expectedMaxField
            ))
        }
        return copy
    }
}

struct SavedTestCase: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var promptID: UUID
    var promptName: String
    var prompt: String
    var datasetID: UUID
    var datasetName: String
    var provider: String
    var modelID: String
    var recommendationModel: String
    var criteria: [TestCriterionDefinition]
    var sampleRowID: UUID?
    var sampleOutputID: UUID?
    var samplePreviewOutputIDs: [UUID]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        promptID: UUID,
        promptName: String,
        prompt: String,
        datasetID: UUID,
        datasetName: String,
        provider: String,
        modelID: String,
        recommendationModel: String,
        criteria: [TestCriterionDefinition] = [],
        sampleRowID: UUID? = nil,
        sampleOutputID: UUID? = nil,
        samplePreviewOutputIDs: [UUID]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.promptID = promptID
        self.promptName = promptName
        self.prompt = prompt
        self.datasetID = datasetID
        self.datasetName = datasetName
        self.provider = provider
        self.modelID = modelID
        self.recommendationModel = recommendationModel
        self.criteria = criteria
        self.sampleRowID = sampleRowID
        self.sampleOutputID = sampleOutputID
        self.samplePreviewOutputIDs = samplePreviewOutputIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LLMOutputRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let rowID: UUID
    let renderedInput: String
    let output: String?
    let error: String?
    let provider: String
    let modelID: String
    let latencyMilliseconds: Double
    let inputTokens: Int?
    let outputTokens: Int?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        rowID: UUID,
        renderedInput: String,
        output: String?,
        error: String?,
        provider: String,
        modelID: String,
        latencyMilliseconds: Double,
        inputTokens: Int?,
        outputTokens: Int?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rowID = rowID
        self.renderedInput = renderedInput
        self.output = output
        self.error = error
        self.provider = provider
        self.modelID = modelID
        self.latencyMilliseconds = latencyMilliseconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.createdAt = createdAt
    }
}

struct TestCaseCriteriaPreview: Identifiable {
    let row: DatasetRow
    let output: LLMOutputRecord

    var id: UUID { output.id }
}

struct CriterionRunResult: Identifiable, Codable, Hashable {
    let criterionID: UUID
    let name: String
    let expected: String
    let outputPath: String
    let actual: String
    let passRule: String
    let passed: Bool

    var id: UUID { criterionID }
}

struct TestRunRowResult: Identifiable, Codable, Hashable {
    let id: UUID
    let rowID: UUID
    let variables: [String: String]
    let expectedValues: [String: String]
    let criterionResults: [CriterionRunResult]
    let latencyMilliseconds: Double
    let inputTokens: Int?
    let outputTokens: Int?
    let modelID: String
    let llmOutput: String?
    let error: String?
}

enum TestRunStatus: String, Codable {
    case completed
    case cancelled
    case failed

    var displayName: String {
        switch self {
        case .completed: "완료"
        case .cancelled: "취소됨"
        case .failed: "실패"
        }
    }
}

struct SavedTestRun: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let testCaseID: UUID
    let testCaseName: String
    let datasetID: UUID
    let datasetName: String
    let promptID: UUID
    let promptName: String
    let prompt: String
    let provider: String
    let modelID: String
    let criteria: [TestCriterionDefinition]
    let requestedCount: Int
    let status: TestRunStatus
    let startedAt: Date
    let completedAt: Date
    let rows: [TestRunRowResult]

    var completedCount: Int { rows.filter { $0.error == nil }.count }
    var hasDeterministicCriteria: Bool { !criteria.isEmpty }
    var passedCount: Int {
        guard hasDeterministicCriteria else { return 0 }
        return rows.filter { row in
            row.error == nil
                && !row.criterionResults.isEmpty
                && row.criterionResults.allSatisfy(\.passed)
        }.count
    }
    var averageLatencyMilliseconds: Double? {
        let values = rows.filter { $0.error == nil }.map(\.latencyMilliseconds)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

enum TestCaseStore {
    static func load() throws -> [SavedTestCase] {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SavedTestCase].self, from: Data(contentsOf: url))
    }

    static func save(_ testCases: [SavedTestCase]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(testCases).write(to: fileURL(), options: .atomic)
    }

    private static func fileURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("test-cases.json")
    }
}

enum LLMOutputStore {
    static func save(_ output: LLMOutputRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(output).write(
            to: try directoryURL().appendingPathComponent("\(output.id.uuidString).json"),
            options: .atomic
        )
    }

    static func load(id: UUID) throws -> LLMOutputRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            LLMOutputRecord.self,
            from: Data(contentsOf: try directoryURL().appendingPathComponent("\(id.uuidString).json"))
        )
    }

    private static func directoryURL() throws -> URL {
        let directory = try appSupportDirectory().appendingPathComponent("llm-outputs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum TestRunStore {
    static func save(_ run: SavedTestRun, outputs: [LLMOutputRecord]) throws {
        let folder = try folderURL(for: run.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let resultURL = folder.appendingPathComponent("test-result.json")
        let outputURL = folder.appendingPathComponent("llm-outputs.json")
        let csvURL = folder.appendingPathComponent("test-result.csv")
        try encoder.encode(run).write(to: resultURL, options: .atomic)
        try encoder.encode(outputs).write(to: outputURL, options: .atomic)
        try csv(run).write(to: csvURL, atomically: true, encoding: .utf8)

        if run.status == .completed {
            for url in [resultURL, outputURL, csvURL] {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o444, .immutable: true],
                    ofItemAtPath: url.path
                )
            }
        }
    }

    static func loadAll() throws -> [SavedTestRun] {
        let root = try rootURL()
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder in
            try? decoder.decode(
                SavedTestRun.self,
                from: Data(contentsOf: folder.appendingPathComponent("test-result.json"))
            )
        }
        .sorted { $0.completedAt > $1.completedAt }
    }

    static func folderURL(for id: UUID) throws -> URL {
        try rootURL().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func delete(_ run: SavedTestRun) throws {
        let folder = try folderURL(for: run.id)
        for name in ["test-result.json", "llm-outputs.json", "test-result.csv"] {
            let url = folder.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.setAttributes(
                [.immutable: false, .posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
        }
        try FileManager.default.removeItem(at: folder)
    }

    private static func rootURL() throws -> URL {
        let directory = try appSupportDirectory().appendingPathComponent("test-runs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func csv(_ run: SavedTestRun) -> String {
        let variableHeaders = Array(Set(run.rows.flatMap { $0.variables.keys })).sorted()
        let expectedHeaders = Array(Set(run.rows.flatMap { $0.expectedValues.keys })).sorted()
        let criterionHeaders = run.criteria.flatMap { criterion in
            ["criterion.\(criterion.name).expected", "criterion.\(criterion.name).actual", "criterion.\(criterion.name).pass"]
        }
        let fixedHeaders = ["latency_ms", "input_tokens", "output_tokens", "test_model", "llm_output", "error"]
        let headers = variableHeaders + expectedHeaders + criterionHeaders + fixedHeaders
        let lines = [headers] + run.rows.map { row in
            let criterionByID = Dictionary(uniqueKeysWithValues: row.criterionResults.map { ($0.criterionID, $0) })
            var values = variableHeaders.map { row.variables[$0] ?? "" }
            values += expectedHeaders.map { row.expectedValues[$0] ?? "" }
            for criterion in run.criteria {
                let result = criterionByID[criterion.id]
                values += [result?.expected ?? "", result?.actual ?? "", result.map { String($0.passed) } ?? ""]
            }
            values += [
                String(format: "%.1f", row.latencyMilliseconds),
                row.inputTokens.map(String.init) ?? "",
                row.outputTokens.map(String.init) ?? "",
                row.modelID,
                row.llmOutput ?? "",
                row.error ?? "",
            ]
            return values
        }
        return lines.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum TestResultEvaluator {
    static func recommendCriteria(
        headers: [String],
        variableFields: [String],
        sampleValues: [String: String],
        output: String
    ) -> [TestCriterionDefinition] {
        let expectedFields = headers.filter { !variableFields.contains($0) }
        let outputPaths = JSONValueExtractor.paths(in: output)
        var consumed = Set(["expected_risk_count"])
        var criteria: [TestCriterionDefinition] = []

        for field in expectedFields where !consumed.contains(field) {
            if field.hasPrefix("has_") {
                let riskType = String(field.dropFirst(4))
                let minimumField = "\(riskType)_score_min"
                let maximumField = "\(riskType)_score_max"
                if expectedFields.contains(minimumField), expectedFields.contains(maximumField) {
                    consumed.formUnion([field, minimumField, maximumField])
                    criteria.append(TestCriterionDefinition(
                        name: "\(displayName(for: riskType)) 유형 및 점수",
                        expectedField: field,
                        expectedMinField: minimumField,
                        expectedMaxField: maximumField,
                        outputPath: riskArrayPath(in: outputPaths),
                        valueType: .json,
                        passRule: .arrayObjectCondition,
                        matchField: "risk_type",
                        matchValue: riskType,
                        valueField: "risk_score",
                        arrayAssertions: [
                            .datasetValue(field: field),
                            .objectValueRange(
                                objectField: "risk_score",
                                minimumField: minimumField,
                                maximumField: maximumField
                            ),
                        ]
                    ))
                    continue
                }
            }
            if field.hasSuffix("_min") {
                let base = String(field.dropLast(4))
                let maxField = "\(base)_max"
                if expectedFields.contains(maxField) {
                    consumed.formUnion([field, maxField])
                    criteria.append(TestCriterionDefinition(
                        name: displayName(for: base),
                        expectedField: "",
                        expectedMinField: field,
                        expectedMaxField: maxField,
                        outputPath: bestPath(for: base, in: outputPaths),
                        valueType: .number,
                        passRule: .range
                    ))
                    continue
                }
            }
            if field.hasSuffix("_max") { continue }

            consumed.insert(field)
            let expectedValue = sampleValues[field] ?? ""
            let normalized = field.replacingOccurrences(of: "expected_", with: "")
            let isKeyword = normalized.contains("keyword")
            let valueType: CriterionValueType = Double(expectedValue) != nil ? .number : .text
            criteria.append(TestCriterionDefinition(
                name: displayName(for: normalized),
                expectedField: field,
                expectedMinField: "",
                expectedMaxField: "",
                outputPath: bestPath(for: normalized, in: outputPaths),
                valueType: valueType,
                passRule: isKeyword ? .contains : .exact
            ))
        }
        return criteria
    }

    static func evaluate(
        criteria: [TestCriterionDefinition],
        values: [String: String],
        output: String
    ) -> [CriterionRunResult] {
        criteria.map { criterion in
            var actual = JSONValueExtractor.value(at: criterion.outputPath, in: output) ?? ""
            let expected: String
            let passed: Bool
            switch criterion.passRule {
            case .arrayObjectCondition:
                let assertions = criterion.arrayAssertions.isEmpty
                    ? criterion.withDefaultArrayAssertions().arrayAssertions
                    : criterion.arrayAssertions
                if assertions.isEmpty {
                    expected = "하위 조건을 하나 이상 설정하세요"
                    actual = "설정된 조건 없음"
                    passed = false
                } else {
                    let evaluations = evaluateArrayAssertions(
                        criterion: criterion,
                        assertions: assertions,
                        values: values,
                        output: output
                    )
                    expected = evaluations.map(\.expected).joined(separator: " / ")
                    actual = evaluations.map(\.actual).joined(separator: " / ")
                    passed = evaluations.allSatisfy(\.passed)
                }
            case .range:
                let minimum = Double(values[criterion.expectedMinField] ?? "")
                let maximum = Double(values[criterion.expectedMaxField] ?? "")
                let actualNumber = Double(actual)
                expected = "\(values[criterion.expectedMinField] ?? "-") ~ \(values[criterion.expectedMaxField] ?? "-")"
                passed = minimum != nil && maximum != nil && actualNumber != nil
                    && actualNumber! >= minimum! && actualNumber! <= maximum!
            case .contains:
                expected = values[criterion.expectedField] ?? ""
                passed = !expected.isEmpty && actual.localizedCaseInsensitiveContains(expected)
            case .exists:
                expected = "값 존재"
                passed = !actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .exact:
                expected = values[criterion.expectedField] ?? ""
                if criterion.valueType == .number, let expectedNumber = Double(expected), let actualNumber = Double(actual) {
                    passed = expectedNumber == actualNumber
                } else {
                    passed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(actual.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                }
            }
            return CriterionRunResult(
                criterionID: criterion.id,
                name: criterion.name,
                expected: expected,
                outputPath: criterion.outputPath,
                actual: actual,
                passRule: criterion.passRule.rawValue,
                passed: passed
            )
        }
    }

    static func evaluateArrayAssertions(
        criterion: TestCriterionDefinition,
        assertions: [ArrayObjectAssertion]? = nil,
        values: [String: String],
        output: String
    ) -> [ArrayObjectAssertionEvaluation] {
        let activeAssertions = assertions ?? criterion.arrayAssertions
        guard !activeAssertions.isEmpty else { return [] }

        let matchField = criterion.matchField ?? "risk_type"
        let matchValue = criterion.matchValue ?? ""
        let defaultValueField = criterion.valueField ?? "risk_score"
        let match = JSONValueExtractor.objectMatch(
            arrayPath: criterion.outputPath,
            matchField: matchField,
            matchValue: matchValue,
            valueField: defaultValueField,
            in: output
        )
        let presenceAssertions = activeAssertions.filter { $0.kind == .datasetValue }
        let absenceExpected = presenceAssertions.contains { assertion in
            values[assertion.datasetField] != assertion.expectedValue
        }

        return activeAssertions.map { assertion in
            switch assertion.kind {
            case .datasetValue:
                let datasetValue = values[assertion.datasetField] ?? ""
                let shouldExist = datasetValue == assertion.expectedValue
                return ArrayObjectAssertionEvaluation(
                    assertion: assertion,
                    expected: "데이터셋의 \(assertion.datasetField)는 값이 \(assertion.expectedValue)이어야 합니다.",
                    actual: "데이터셋 값 \(datasetValue.isEmpty ? "-" : datasetValue) · 요소 \(match == nil ? "없음" : "있음")",
                    passed: shouldExist ? match != nil : match == nil
                )
            case .objectValueRange:
                let minimum = Double(values[assertion.minimumField] ?? "")
                let maximum = Double(values[assertion.maximumField] ?? "")
                let valueField = assertion.objectField.isEmpty ? defaultValueField : assertion.objectField
                let measured = JSONValueExtractor.objectMatch(
                    arrayPath: criterion.outputPath,
                    matchField: matchField,
                    matchValue: matchValue,
                    valueField: valueField,
                    in: output
                )
                let expected = "해당 요소의 \(valueField)는 \(assertion.minimumField) 이상 \(assertion.maximumField) 이하여야 합니다."
                if measured == nil, absenceExpected {
                    return ArrayObjectAssertionEvaluation(
                        assertion: assertion,
                        expected: expected,
                        actual: "요소 없음 · 범위 검사 제외",
                        passed: true
                    )
                }
                let passed = measured?.numericValue != nil && minimum != nil && maximum != nil
                    && measured!.numericValue! >= minimum! && measured!.numericValue! <= maximum!
                return ArrayObjectAssertionEvaluation(
                    assertion: assertion,
                    expected: expected,
                    actual: measured?.display ?? "요소 없음",
                    passed: passed
                )
            }
        }
    }

    private static func riskArrayPath(in paths: [String]) -> String {
        guard let riskTypePath = paths.first(where: { $0.hasSuffix(".risk_type") }),
              let suffixRange = riskTypePath.range(
                of: #"\[\d+\]\.risk_type$"#,
                options: .regularExpression
              ) else {
            return "risk_detection.detected_risks"
        }
        return String(riskTypePath[..<suffixRange.lowerBound])
    }

    private static func bestPath(for field: String, in paths: [String]) -> String {
        let normalized = field
            .replacingOccurrences(of: "expected_", with: "")
            .replacingOccurrences(of: "_keyword", with: "")
            .replacingOccurrences(of: "_min", with: "")
            .replacingOccurrences(of: "_max", with: "")
        return paths.first { $0.split(separator: ".").last.map(String.init) == normalized }
            ?? paths.first { $0.localizedCaseInsensitiveContains(normalized) }
            ?? normalized
    }

    private static func displayName(for field: String) -> String {
        field.replacingOccurrences(of: "expected_", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }
}

enum JSONValueExtractor {
    static func paths(in output: String) -> [String] {
        guard let object = parse(output) else { return [] }
        var result: [String] = []
        collectPaths(object, prefix: "", into: &result)
        return result.sorted()
    }

    static func value(at path: String, in output: String) -> String? {
        guard let current = rawValue(at: path, in: output) else { return nil }
        return stringify(current)
    }

    static func objectFields(atArrayPath path: String, in output: String) -> [String] {
        guard let objects = rawValue(at: path, in: output) as? [[String: Any]] else { return [] }
        return Array(Set(objects.flatMap(\.keys))).sorted()
    }

    static func objectValues(atArrayPath path: String, field: String, in output: String) -> [String] {
        guard !field.isEmpty, let objects = rawValue(at: path, in: output) as? [[String: Any]] else { return [] }
        return Array(Set(objects.compactMap { $0[field].map(stringify) })).sorted()
    }

    static func objectMatch(
        arrayPath: String,
        matchField: String,
        matchValue: String,
        valueField: String,
        in output: String
    ) -> (numericValue: Double?, display: String)? {
        guard let objects = rawValue(at: arrayPath, in: output) as? [[String: Any]],
              let object = objects.first(where: {
                  ($0[matchField].map(stringify) ?? "")
                      .caseInsensitiveCompare(matchValue) == .orderedSame
              }) else {
            return nil
        }
        let measuredValue = object[valueField].map(stringify) ?? ""
        return (
            numericValue: Double(measuredValue),
            display: "\(matchField)=\(matchValue) · \(valueField)=\(measuredValue.isEmpty ? "-" : measuredValue)"
        )
    }

    private static func rawValue(at path: String, in output: String) -> Any? {
        guard !path.isEmpty, var current = parse(output) else { return nil }
        for component in path.split(separator: ".").map(String.init) {
            if let open = component.firstIndex(of: "["), component.hasSuffix("]") {
                let key = String(component[..<open])
                let indexText = component[component.index(after: open)..<component.index(before: component.endIndex)]
                if !key.isEmpty {
                    guard let dictionary = current as? [String: Any], let next = dictionary[key] else { return nil }
                    current = next
                }
                guard let index = Int(indexText), let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            } else {
                guard let dictionary = current as? [String: Any], let next = dictionary[component] else { return nil }
                current = next
            }
        }
        return current
    }

    private static func parse(_ output: String) -> Any? {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```(?:json)?\s*"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
        }
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func collectPaths(_ value: Any, prefix: String, into result: inout [String]) {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                collectPaths(dictionary[key] as Any, prefix: path, into: &result)
            }
        } else if let array = value as? [Any] {
            if !prefix.isEmpty {
                result.append(prefix)
            }
            if let first = array.first {
                collectPaths(first, prefix: "\(prefix)[0]", into: &result)
            }
        } else if !prefix.isEmpty {
            result.append(prefix)
        }
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}

private func appSupportDirectory() throws -> URL {
    let root = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    ).appendingPathComponent("PromptEvalApp", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
