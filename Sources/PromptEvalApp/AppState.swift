import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

private struct LLMGenerationJob: Sendable {
    let index: Int
    let rowID: UUID
    let llmInput: String
}

private struct LLMGenerationResult: Sendable {
    let index: Int
    let rowID: UUID
    let llmInput: String
    let output: String?
    let error: String?
    let outputModel: String
    let latencyMilliseconds: Double
    let inputTokens: Int?
    let outputTokens: Int?
}

struct AppNotification: Identifiable {
    let id = UUID()
    let message: String
}

private func executeGenerationJob(
    _ job: LLMGenerationJob,
    provider: ProviderKind,
    apiKey: String,
    modelID: String
) async -> LLMGenerationResult {
    let startedAt = Date()
    do {
        let response = try await LLMService.generate(
            provider: provider,
            apiKey: apiKey,
            model: modelID,
            prompt: job.llmInput
        )
        return LLMGenerationResult(
            index: job.index,
            rowID: job.rowID,
            llmInput: job.llmInput,
            output: response.text,
            error: nil,
            outputModel: modelID,
            latencyMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
    } catch {
        return LLMGenerationResult(
            index: job.index,
            rowID: job.rowID,
            llmInput: job.llmInput,
            output: nil,
            error: error.localizedDescription,
            outputModel: modelID,
            latencyMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
            inputTokens: nil,
            outputTokens: nil
        )
    }
}

struct ActiveRunProgress: Identifiable {
    let id: UUID
    let name: String
    let detail: String
    let total: Int
}

@MainActor
final class AppState: ObservableObject {
    private static let knownCodexEvaluationModels = [
        "gpt-5.6-sol",
        "gpt-5.6-luna",
        "gpt-5.6-terra",
        "gpt-5.5",
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.3-codex",
    ]
    private static let defaultEvaluationPrompt = """
    당신은 엄격하고 공정한 LLM 출력 평가자입니다.

    실제 LLM 입력:
    {{llm_input}}

    원본 프롬프트:
    {{original_prompt}}

    데이터셋 값과 기댓값:
    {{dataset_values}}

    저장된 테스트 기준:
    {{test_criteria}}

    모델 출력:
    {{model_output}}

    모델 출력이 원본 프롬프트를 따르고 정확하며 일관되고 유용한지 평가하세요. 저장된 테스트 기준이 있으면 각 기준의 기댓값, 추출 결과, PASS 규칙, 결정적 판정도 함께 검토하세요. 저장된 테스트 기준이 없으면 기준을 임의로 만들지 마세요. 전체 통과 여부와 0~100 점수, 그리고 구체적인 근거를 판단하세요. 모든 근거와 기준별 근거는 한국어로 작성하세요.
    """

    @Published var promptText = ""
    @Published var promptName = "새 프롬프트"
    @Published var savedPrompts: [SavedPrompt] = []
    @Published var selectedPromptID: UUID?
    @Published var datasetName = "불러온 데이터셋 없음"
    @Published var savedDatasets: [SavedDataset] = []
    @Published var selectedDatasetID: UUID?
    @Published var headers: [String] = []
    @Published var rows: [DatasetRow] = []
    @Published var provider: ProviderKind = .gemini {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "lastLLMProvider") }
    }
    @Published var providerAPIKey = ""
    @Published var models: [ModelOption] = []
    @Published var selectedModelID = "" {
        didSet {
            let modelID = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty else { return }
            UserDefaults.standard.set(modelID, forKey: "lastLLMModelID")
        }
    }
    @Published var spreadsheetID = ""
    @Published var spreadsheetRange = "Sheet1!A:ZZ"
    @Published var googleAPIKey = ""
    @Published var runLimit = 20
    @Published var generationConcurrency = 8 {
        didSet { UserDefaults.standard.set(generationConcurrency, forKey: "generationConcurrency") }
    }
    @Published var codexConcurrency = 3 {
        didSet { UserDefaults.standard.set(codexConcurrency, forKey: "codexConcurrency") }
    }
    @Published var codexJudgeLimit = 20 {
        didSet { UserDefaults.standard.set(codexJudgeLimit, forKey: "codexJudgeLimit") }
    }
    @Published var codexEvaluationModel = "gpt-5.5" {
        didSet { UserDefaults.standard.set(codexEvaluationModel, forKey: "codexEvaluationModel") }
    }
    @Published var evaluationPrompt = AppState.defaultEvaluationPrompt {
        didSet { UserDefaults.standard.set(evaluationPrompt, forKey: "evaluationPrompt") }
    }
    // Promptfoo API keys are intentionally memory-only. Evaluation logs must not contain credentials.
    @Published var promptfooAPIKey = ""
    @Published var isLoadingModels = false
    @Published var isRunning = false
    @Published var isEvaluating = false
    @Published var isRecommendingEvaluationPrompt = false
    @Published var isSharingEvaluation = false
    @Published var progress = 0
    @Published var evaluationProgress = 0
    @Published var evaluationTotal = 0
    @Published var status = "프롬프트와 데이터셋을 불러오세요."
    @Published var evaluationBundleURL: URL?
    @Published var evaluationSummary: EvaluationRunSummary?
    @Published var evaluationResults: [EvaluationResultRecord] = []
    @Published var selectedEvaluationResultID: String?
    private var evaluationRetryRowID: String?
    @Published var savedTestCases: [SavedTestCase] = []
    @Published var selectedTestCaseID: UUID?
    @Published var testCaseName = "새 테스트 케이스"
    @Published var testCaseCriteria: [TestCriterionDefinition] = []
    @Published var testCaseDisplayDatasetFields: [String] = []
    @Published var testCaseDisplayOutputPaths: [String] = []
    @Published var sampleOutput: LLMOutputRecord?
    @Published var criteriaPreviewOutputs: [LLMOutputRecord] = []
    @Published private(set) var criteriaPreviewCriteria: [TestCriterionDefinition] = []
    @Published private(set) var criteriaPreviewResults: [UUID: [CriterionRunResult]] = [:]
    @Published var isPreviewingTestCase = false
    @Published var isRunningCriteriaPreview = false
    @Published var criteriaPreviewProgress = 0
    @Published var isRecommendingCriteria = false
    @Published var testRuns: [SavedTestRun] = []
    @Published var selectedTestRunID: UUID?
    @Published var testRunLimit = 0
    @Published var isTestRunning = false
    @Published var activeTestRun: ActiveRunProgress?
    @Published var activeEvaluationRun: ActiveRunProgress?
    @Published var alertMessage: String?
    @Published var notification: AppNotification?

    private var activeTestRunTask: Task<Void, Never>?

    func notify(_ message: String) {
        notification = AppNotification(message: message)
    }

    var promptVariables: [String] { PromptTemplate.variables(in: promptText) }
    var promptOutputSchema: PromptOutputSchema? { PromptOutputSchema.extract(from: promptText) }
    var promptOutputSchemaPaths: [String] { promptOutputSchema?.paths ?? [] }
    var missingVariables: [String] { promptVariables.filter { !headers.contains($0) } }
    var completedCount: Int { rows.filter { $0.output != nil }.count }
    var selectedModelName: String { models.first(where: { $0.id == selectedModelID })?.name ?? selectedModelID }
    var selectedDataset: SavedDataset? { savedDatasets.first(where: { $0.id == selectedDatasetID }) }
    var sourceDatasets: [SavedDataset] { savedDatasets.filter { $0.kind == .source } }
    var isEvaluationDatasetSelected: Bool { selectedDataset?.kind == .evaluation }
    var selectedEvaluationResult: EvaluationResultRecord? {
        evaluationResults.first(where: { $0.id == selectedEvaluationResultID })
    }
    var codexEvaluationModelOptions: [String] {
        let current = codexEvaluationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, !Self.knownCodexEvaluationModels.contains(current) else {
            return Self.knownCodexEvaluationModels
        }
        return [current] + Self.knownCodexEvaluationModels
    }
    var selectedTestCase: SavedTestCase? { savedTestCases.first { $0.id == selectedTestCaseID } }
    var selectedTestRun: SavedTestRun? { testRuns.first { $0.id == selectedTestRunID } }
    var testCaseExpectedFields: [String] { headers.filter { !promptVariables.contains($0) } }
    var sampleOutputPaths: [String] { sampleOutput?.output.map(JSONValueExtractor.paths) ?? [] }
    var criteriaPreviews: [TestCaseCriteriaPreview] {
        criteriaPreviewOutputs.compactMap { output in
            guard let row = rows.first(where: { $0.id == output.rowID }) else { return nil }
            return TestCaseCriteriaPreview(row: row, output: output)
        }
    }

    func arrayObjectFields(at path: String) -> [String] {
        promptOutputSchema?.objectFields(atArrayPath: path) ?? []
    }

    func arrayObjectValues(at path: String, field: String) -> [String] {
        guard let output = sampleOutput?.output else { return [] }
        return JSONValueExtractor.objectValues(atArrayPath: path, field: field, in: output)
    }

    init() {
        if let savedProvider = UserDefaults.standard.string(forKey: "lastLLMProvider"),
           let savedProviderKind = ProviderKind(rawValue: savedProvider) {
            provider = savedProviderKind
        }
        if let savedModel = UserDefaults.standard.string(forKey: "lastLLMModelID"), !savedModel.isEmpty {
            selectedModelID = savedModel
        }
        if UserDefaults.standard.object(forKey: "generationConcurrency") != nil {
            generationConcurrency = min(max(UserDefaults.standard.integer(forKey: "generationConcurrency"), 1), 16)
        }
        if UserDefaults.standard.object(forKey: "codexConcurrency") != nil {
            codexConcurrency = min(max(UserDefaults.standard.integer(forKey: "codexConcurrency"), 2), 8)
        }
        if UserDefaults.standard.object(forKey: "codexJudgeLimit") != nil {
            codexJudgeLimit = max(UserDefaults.standard.integer(forKey: "codexJudgeLimit"), 0)
        }
        if let savedModel = UserDefaults.standard.string(forKey: "codexEvaluationModel"), !savedModel.isEmpty {
            codexEvaluationModel = savedModel
        }
        if let savedEvaluationPrompt = UserDefaults.standard.string(forKey: "evaluationPrompt"), !savedEvaluationPrompt.isEmpty {
            evaluationPrompt = savedEvaluationPrompt
        }
        do {
            let library = try LibraryStore.load()
            savedPrompts = library.prompts.sorted { $0.updatedAt > $1.updatedAt }
            savedDatasets = library.datasets.sorted { $0.updatedAt > $1.updatedAt }
            let recoveredDatasetIDs = try GenerationCheckpointStore.recover(into: &savedDatasets)
            if !recoveredDatasetIDs.isEmpty {
                try LibraryStore.save(SavedLibrary(prompts: savedPrompts, datasets: savedDatasets))
                for datasetID in recoveredDatasetIDs {
                    try? GenerationCheckpointStore.remove(datasetID: datasetID)
                }
            }
            if let prompt = savedPrompts.first {
                selectedPromptID = prompt.id
                promptName = prompt.name
                promptText = prompt.content
            }
            if let dataset = savedDatasets.first(where: { $0.kind == .source }) {
                selectedDatasetID = dataset.id
                datasetName = dataset.name
                headers = dataset.headers
                rows = dataset.rows
            }
            if !recoveredDatasetIDs.isEmpty {
                status = "중단된 LLM 실행 결과를 복구했습니다."
            } else if !savedPrompts.isEmpty || !savedDatasets.isEmpty {
                status = "저장된 프롬프트와 데이터셋 라이브러리를 불러왔습니다."
            }
        } catch {
            status = "저장 라이브러리를 불러오지 못했습니다: \(error.localizedDescription)"
        }
        do {
            savedTestCases = try TestCaseStore.load().sorted { $0.updatedAt > $1.updatedAt }
            testRuns = try TestRunStore.loadAll()
            if let testCase = savedTestCases.first {
                selectTestCase(testCase.id)
            }
            selectedTestRunID = testRuns.first?.id
        } catch {
            status = "테스트 워크플로를 불러오지 못했습니다: \(error.localizedDescription)"
        }
        if let savedProvider = UserDefaults.standard.string(forKey: "lastLLMProvider"),
           let savedProviderKind = ProviderKind(rawValue: savedProvider) {
            provider = savedProviderKind
        }
        if let savedModel = UserDefaults.standard.string(forKey: "lastLLMModelID"), !savedModel.isEmpty {
            selectedModelID = savedModel
        }
        if let savedEvaluationModel = UserDefaults.standard.string(forKey: "codexEvaluationModel"), !savedEvaluationModel.isEmpty {
            codexEvaluationModel = savedEvaluationModel
        }
        if let savedEvaluationPrompt = UserDefaults.standard.string(forKey: "evaluationPrompt"), !savedEvaluationPrompt.isEmpty {
            evaluationPrompt = savedEvaluationPrompt
        }
        refreshEvaluationResults(silent: true)
    }

    func choosePrompt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            registerPrompt(name: url.deletingPathExtension().lastPathComponent, content: content)
            status = "프롬프트를 불러왔습니다: \(url.lastPathComponent)"
            notify(status)
        } catch {
            status = error.localizedDescription
        }
    }

    func newPrompt() {
        selectedPromptID = nil
        promptName = "새 프롬프트"
        promptText = ""
        status = "새 프롬프트를 작성할 수 있습니다."
    }

    func selectPrompt(_ id: UUID?) {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 프롬프트를 변경할 수 있습니다."
            return
        }
        guard let id else { return }
        guard id != selectedPromptID else { return }
        selectedPromptID = id
        guard let prompt = savedPrompts.first(where: { $0.id == id }) else { return }
        promptName = prompt.name
        promptText = prompt.content
        status = "프롬프트를 불러왔습니다: \(prompt.name)"
    }

    func saveCurrentPrompt(silent: Bool = false) {
        let name = promptName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !silent { status = "프롬프트 이름과 내용을 입력하세요." }
            return
        }
        if let id = selectedPromptID, let index = savedPrompts.firstIndex(where: { $0.id == id }) {
            savedPrompts[index].name = name
            savedPrompts[index].content = promptText
            savedPrompts[index].updatedAt = Date()
        } else {
            let prompt = SavedPrompt(name: name, content: promptText)
            savedPrompts.insert(prompt, at: 0)
            selectedPromptID = prompt.id
        }
        persistLibrary()
        if !silent {
            status = "프롬프트를 저장했습니다: \(name)"
            notify(status)
        }
    }

    func duplicateSelectedPrompt() {
        guard let id = selectedPromptID,
              let prompt = savedPrompts.first(where: { $0.id == id }) else {
            return
        }
        let copy = SavedPrompt(name: "\(prompt.name)_copy", content: prompt.content)
        savedPrompts.insert(copy, at: 0)
        selectedPromptID = copy.id
        promptName = copy.name
        promptText = copy.content
        persistLibrary()
        status = "프롬프트를 복제했습니다: \(copy.name)"
        notify(status)
    }

    func deleteSelectedPrompt() {
        guard let id = selectedPromptID else { return }
        savedPrompts.removeAll { $0.id == id }
        selectedPromptID = nil
        promptName = "새 프롬프트"
        promptText = ""
        persistLibrary()
        status = "선택한 프롬프트를 라이브러리에서 삭제했습니다."
        notify(status)
    }

    func chooseDataset() {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 데이터셋을 가져올 수 있습니다."
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv")!, UTType(filenameExtension: "json")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        var importedCount = 0
        var failures: [String] = []
        for url in panel.urls {
            do {
                if url.pathExtension.lowercased() == "json" {
                    let decoded = try DatasetDecoder.json(Data(contentsOf: url))
                    applyDataset(name: url.deletingPathExtension().lastPathComponent, headers: decoded.headers, rows: decoded.rows, fileExtension: "json")
                } else {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw AppError.message("UTF-8 CSV 파일이 아닙니다.")
                    }
                    let decoded = try CSVCodec.decode(text)
                    applyDataset(name: url.deletingPathExtension().lastPathComponent, headers: decoded.headers, rows: decoded.rows, fileExtension: "csv")
                }
                importedCount += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            status = "데이터셋 \(importedCount)개를 가져왔습니다."
            notify(status)
        } else {
            let summary = "성공 \(importedCount)개, 실패 \(failures.count)개\n\n\(failures.joined(separator: "\n"))"
            status = "일부 데이터셋을 가져오지 못했습니다."
            alertMessage = summary
        }
    }

    func selectDataset(_ id: UUID?) {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 데이터셋을 변경할 수 있습니다."
            return
        }
        guard let id else { return }
        guard id != selectedDatasetID else { return }
        evaluationBundleURL = nil
        evaluationSummary = nil
        selectedDatasetID = id
        guard let dataset = savedDatasets.first(where: { $0.id == id }) else { return }
        datasetName = dataset.name
        headers = dataset.headers
        rows = dataset.rows
        status = "데이터셋을 불러왔습니다: \(dataset.name)"
    }

    func saveCurrentDataset(silent: Bool = false) {
        if !silent {
            status = "데이터셋은 읽기 전용입니다. 수정본은 파일을 새로 가져와 등록하세요."
        }
    }

    func newDataset() {
        status = "데이터셋은 CSV 또는 JSON 파일을 가져와 등록하세요."
    }

    func deleteSelectedDataset() {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 데이터셋을 삭제할 수 있습니다."
            return
        }
        guard let id = selectedDatasetID else { return }
        savedDatasets.removeAll { $0.id == id }
        selectedDatasetID = nil
        datasetName = "불러온 데이터셋 없음"
        headers = []
        rows = []
        persistLibrary()
        status = "선택한 데이터셋을 라이브러리에서 삭제했습니다."
        notify(status)
    }

    func loadSpreadsheet() {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 Google Sheet를 불러올 수 있습니다."
            return
        }
        Task {
            do {
                status = "Google Sheet를 불러오는 중..."
                let dataset = try await GoogleSheetsService.load(
                    spreadsheetID: spreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines),
                    range: spreadsheetRange.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                applyDataset(name: "Google Sheet \(spreadsheetID)", headers: dataset.headers, rows: dataset.rows, fileExtension: "gsheet")
                notify(status)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func loadModels() {
        Task {
            do {
                isLoadingModels = true
                status = "\(provider.rawValue) 모델을 불러오는 중..."
                let loaded = try await LLMService.models(provider: provider, apiKey: providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines))
                models = loaded
                if !loaded.contains(where: { $0.id == selectedModelID }) {
                    selectedModelID = loaded.first?.id ?? ""
                }
                status = "모델 \(loaded.count)개를 불러왔습니다."
            } catch {
                status = error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    func newTestCase() {
        selectedTestCaseID = nil
        testCaseName = "새 테스트 케이스"
        testCaseCriteria = []
        testCaseDisplayDatasetFields = []
        testCaseDisplayOutputPaths = []
        sampleOutput = nil
        criteriaPreviewOutputs = []
        criteriaPreviewCriteria = []
        criteriaPreviewResults = [:]
        status = "프롬프트와 원본 데이터셋을 선택해 테스트 케이스를 만드세요."
    }

    func selectTestCase(_ id: UUID?) {
        guard !isTestRunning, let id, let testCase = savedTestCases.first(where: { $0.id == id }) else { return }
        selectedTestCaseID = id
        testCaseName = testCase.name
        testCaseCriteria = testCase.criteria.map { $0.withDefaultArrayAssertions() }
        testCaseDisplayDatasetFields = testCase.displayDatasetFields ?? []
        testCaseDisplayOutputPaths = testCase.displayOutputPaths ?? []
        criteriaPreviewCriteria = testCaseCriteria
        codexEvaluationModel = testCase.recommendationModel
        provider = ProviderKind(rawValue: testCase.provider) ?? .gemini
        selectedModelID = testCase.modelID
        if let prompt = savedPrompts.first(where: { $0.id == testCase.promptID }) {
            selectedPromptID = prompt.id
            promptName = prompt.name
            promptText = prompt.content
        } else {
            selectedPromptID = testCase.promptID
            promptName = testCase.promptName
            promptText = testCase.prompt
        }
        if let dataset = savedDatasets.first(where: { $0.id == testCase.datasetID }) {
            selectedDatasetID = dataset.id
            datasetName = dataset.name
            headers = dataset.headers
            rows = dataset.rows
            testRunLimit = dataset.rows.count
        }
        if let outputID = testCase.sampleOutputID {
            sampleOutput = try? LLMOutputStore.load(id: outputID)
        } else {
            sampleOutput = nil
        }
        criteriaPreviewOutputs = (testCase.samplePreviewOutputIDs ?? []).compactMap {
            try? LLMOutputStore.load(id: $0)
        }
        rebuildCriteriaPreviewResults()
        status = "테스트 케이스를 불러왔습니다: \(testCase.name)"
    }

    func saveCurrentTestCase() {
        guard let promptID = selectedPromptID,
              let prompt = savedPrompts.first(where: { $0.id == promptID }) else {
            status = "저장된 프롬프트를 선택하세요."
            return
        }
        guard let datasetID = selectedDatasetID,
              let dataset = savedDatasets.first(where: { $0.id == datasetID && $0.kind == .source }) else {
            status = "원본 데이터셋을 선택하세요."
            return
        }
        let name = testCaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !selectedModelID.isEmpty else {
            status = "테스트 케이스 이름과 실행 모델을 설정하세요."
            return
        }
        let now = Date()
        if let id = selectedTestCaseID, let index = savedTestCases.firstIndex(where: { $0.id == id }) {
            savedTestCases[index].name = name
            savedTestCases[index].promptID = prompt.id
            savedTestCases[index].promptName = prompt.name
            savedTestCases[index].prompt = prompt.content
            savedTestCases[index].datasetID = dataset.id
            savedTestCases[index].datasetName = dataset.name
            savedTestCases[index].provider = provider.rawValue
            savedTestCases[index].modelID = selectedModelID
            savedTestCases[index].recommendationModel = codexEvaluationModel
            savedTestCases[index].criteria = testCaseCriteria
            savedTestCases[index].displayDatasetFields = testCaseDisplayDatasetFields
            savedTestCases[index].displayOutputPaths = testCaseDisplayOutputPaths
            savedTestCases[index].sampleRowID = rows.first?.id
            savedTestCases[index].sampleOutputID = sampleOutput?.id
            savedTestCases[index].samplePreviewOutputIDs = criteriaPreviewOutputs.isEmpty
                ? nil
                : criteriaPreviewOutputs.map(\.id)
            savedTestCases[index].updatedAt = now
        } else {
            let testCase = SavedTestCase(
                name: name,
                promptID: prompt.id,
                promptName: prompt.name,
                prompt: prompt.content,
                datasetID: dataset.id,
                datasetName: dataset.name,
                provider: provider.rawValue,
                modelID: selectedModelID,
                recommendationModel: codexEvaluationModel,
                criteria: testCaseCriteria,
                displayDatasetFields: testCaseDisplayDatasetFields,
                displayOutputPaths: testCaseDisplayOutputPaths,
                sampleRowID: rows.first?.id,
                sampleOutputID: sampleOutput?.id,
                samplePreviewOutputIDs: criteriaPreviewOutputs.isEmpty ? nil : criteriaPreviewOutputs.map(\.id)
            )
            savedTestCases.insert(testCase, at: 0)
            selectedTestCaseID = testCase.id
        }
        persistTestCases()
        status = "테스트 케이스를 저장했습니다: \(name)"
        notify(status)
    }

    func deleteSelectedTestCase() {
        guard let id = selectedTestCaseID, !isTestRunning else { return }
        savedTestCases.removeAll { $0.id == id }
        persistTestCases()
        newTestCase()
        status = "테스트 케이스를 삭제했습니다."
        notify(status)
    }

    func duplicateSelectedTestCase() {
        guard !isTestRunning,
              let id = selectedTestCaseID,
              let testCase = savedTestCases.first(where: { $0.id == id }) else {
            return
        }
        let copy = SavedTestCase(
            name: "\(testCase.name)_copy",
            promptID: testCase.promptID,
            promptName: testCase.promptName,
            prompt: testCase.prompt,
            datasetID: testCase.datasetID,
            datasetName: testCase.datasetName,
            provider: testCase.provider,
            modelID: testCase.modelID,
            recommendationModel: testCase.recommendationModel,
            criteria: testCase.criteria,
            displayDatasetFields: testCase.displayDatasetFields,
            displayOutputPaths: testCase.displayOutputPaths,
            sampleRowID: testCase.sampleRowID,
            sampleOutputID: testCase.sampleOutputID,
            samplePreviewOutputIDs: testCase.samplePreviewOutputIDs
        )
        savedTestCases.insert(copy, at: 0)
        persistTestCases()
        selectTestCase(copy.id)
        status = "테스트 케이스를 복제했습니다: \(copy.name)"
        notify(status)
    }

    func runTestCasePreview() {
        guard !isPreviewingTestCase,
              let row = rows.first,
              let dataset = selectedDataset,
              dataset.kind == .source else {
            status = "미리 실행할 원본 데이터셋을 선택하세요."
            return
        }
        guard missingVariables.isEmpty, !selectedModelID.isEmpty else {
            status = missingVariables.isEmpty ? "실행 모델을 선택하세요." : "데이터셋에 없는 프롬프트 변수가 있습니다."
            return
        }
        let runPrompt = promptText
        let runProvider = provider
        let apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = selectedModelID
        Task {
            isPreviewingTestCase = true
            defer { isPreviewingTestCase = false }
            do {
                let rendered = try PromptTemplate.render(runPrompt, values: row.values)
                let result = await executeGenerationJob(
                    LLMGenerationJob(index: 0, rowID: row.id, llmInput: rendered),
                    provider: runProvider,
                    apiKey: apiKey,
                    modelID: modelID
                )
                let output = LLMOutputRecord(
                    rowID: row.id,
                    renderedInput: rendered,
                    output: result.output,
                    error: result.error,
                    provider: runProvider.rawValue,
                    modelID: modelID,
                    latencyMilliseconds: result.latencyMilliseconds,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                )
                try LLMOutputStore.save(output)
                sampleOutput = output
                if output.output != nil {
                    guard !promptOutputSchemaPaths.isEmpty else {
                        status = "1행 output을 저장했지만 프롬프트에서 JSON output 스키마를 찾지 못했습니다."
                        return
                    }
                    testCaseCriteria = TestResultEvaluator.recommendCriteria(
                        headers: headers,
                        variableFields: promptVariables,
                        sampleValues: row.values,
                        outputPaths: promptOutputSchemaPaths
                    )
                    status = "1행 output을 별도 저장하고 프롬프트의 output 스키마로 평가 기준 추천값을 만들었습니다."
                } else {
                    status = "미리 실행 실패: \(output.error ?? "알 수 없는 오류")"
                }
            } catch {
                status = "미리 실행 실패: \(error.localizedDescription)"
            }
        }
    }

    func runCriteriaPreview() {
        guard !isRunningCriteriaPreview,
              let dataset = selectedDataset,
              dataset.kind == .source else {
            status = "조건 미리보기에 사용할 원본 데이터셋을 선택하세요."
            return
        }
        guard !testCaseCriteria.isEmpty else {
            status = "먼저 조건을 하나 이상 설정하세요."
            return
        }
        guard missingVariables.isEmpty, !selectedModelID.isEmpty else {
            status = missingVariables.isEmpty ? "실행 모델을 선택하세요." : "데이터셋에 없는 프롬프트 변수가 있습니다."
            return
        }
        let apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = "\(provider.rawValue) API 키를 입력하세요."
            return
        }

        let previewRows = Array(rows.prefix(5))
        guard !previewRows.isEmpty else {
            status = "미리볼 데이터 행이 없습니다."
            return
        }
        let runPrompt = promptText
        let runProvider = provider
        let modelID = selectedModelID
        let concurrency = min(max(generationConcurrency, 1), previewRows.count)
        commitCriteriaPreviewCriteria()

        Task {
            isRunningCriteriaPreview = true
            criteriaPreviewProgress = 0
            defer { isRunningCriteriaPreview = false }

            var recordsByIndex: [Int: LLMOutputRecord] = [:]
            var jobs: [LLMGenerationJob] = []
            for (index, row) in previewRows.enumerated() {
                do {
                    let rendered = try PromptTemplate.render(runPrompt, values: row.values)
                    jobs.append(LLMGenerationJob(index: index, rowID: row.id, llmInput: rendered))
                } catch {
                    recordsByIndex[index] = LLMOutputRecord(
                        rowID: row.id,
                        renderedInput: "",
                        output: nil,
                        error: error.localizedDescription,
                        provider: runProvider.rawValue,
                        modelID: modelID,
                        latencyMilliseconds: 0,
                        inputTokens: nil,
                        outputTokens: nil
                    )
                    criteriaPreviewProgress += 1
                }
            }

            await withTaskGroup(of: LLMGenerationResult.self) { group in
                var nextJobIndex = 0
                for _ in 0..<min(concurrency, jobs.count) {
                    let job = jobs[nextJobIndex]
                    nextJobIndex += 1
                    group.addTask {
                        await executeGenerationJob(job, provider: runProvider, apiKey: apiKey, modelID: modelID)
                    }
                }

                while let result = await group.next() {
                    recordsByIndex[result.index] = LLMOutputRecord(
                        rowID: result.rowID,
                        renderedInput: result.llmInput,
                        output: result.output,
                        error: result.error,
                        provider: runProvider.rawValue,
                        modelID: modelID,
                        latencyMilliseconds: result.latencyMilliseconds,
                        inputTokens: result.inputTokens,
                        outputTokens: result.outputTokens
                    )
                    criteriaPreviewProgress += 1
                    if nextJobIndex < jobs.count {
                        let job = jobs[nextJobIndex]
                        nextJobIndex += 1
                        group.addTask {
                            await executeGenerationJob(job, provider: runProvider, apiKey: apiKey, modelID: modelID)
                        }
                    }
                }
            }

            do {
                let ordered = recordsByIndex.keys.sorted().compactMap { recordsByIndex[$0] }
                for record in ordered {
                    try LLMOutputStore.save(record)
                }
                criteriaPreviewOutputs = ordered
                rebuildCriteriaPreviewResults()
                let failures = ordered.filter { $0.error != nil }.count
                status = failures == 0
                    ? "5행 조건 미리보기를 완료했습니다. 조건 입력을 마치고 포커스를 벗어나면 결과가 갱신됩니다."
                    : "5행 중 \(failures)행의 미리 실행이 실패했습니다."
            } catch {
                status = "조건 미리보기 저장 실패: \(error.localizedDescription)"
            }
        }
    }

    func criterionResults(for preview: TestCaseCriteriaPreview) -> [CriterionRunResult] {
        criteriaPreviewResults[preview.row.id] ?? []
    }

    func commitCriteriaPreviewCriteria() {
        criteriaPreviewCriteria = testCaseCriteria
        rebuildCriteriaPreviewResults()
    }

    private func rebuildCriteriaPreviewResults() {
        let criteria = criteriaPreviewCriteria
        criteriaPreviewResults = Dictionary(uniqueKeysWithValues: criteriaPreviewOutputs.compactMap { output in
            guard let row = rows.first(where: { $0.id == output.rowID }),
                  let text = output.output else {
                return nil
            }
            return (
                output.rowID,
                TestResultEvaluator.evaluate(criteria: criteria, values: row.values, output: text)
            )
        })
    }

    func recommendCriteriaWithCodex() {
        guard !isRecommendingCriteria,
              let row = rows.first,
              let outputSchema = promptOutputSchema else {
            status = "프롬프트에 유효한 JSON output 스키마를 포함하세요."
            return
        }
        let model = codexEvaluationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            status = "추천에 사용할 로컬 agent 모델을 선택하세요."
            return
        }
        let variableFields = promptVariables
        Task {
            isRecommendingCriteria = true
            defer { isRecommendingCriteria = false }
            do {
                let recommended = try await CodexCriterionRecommendationService.recommend(
                    model: model,
                    variableFields: variableFields,
                    rowValues: row.values,
                    outputSchema: outputSchema.json
                )
                guard !recommended.isEmpty else {
                    status = "Codex가 추천 가능한 평가 기준을 찾지 못했습니다."
                    return
                }
                testCaseCriteria = recommended
                status = "\(model)로 평가 기준 \(recommended.count)개를 추천했습니다."
            } catch {
                status = "AI 추천은 실패했지만 기존 추천값은 유지됩니다: \(error.localizedDescription)"
            }
        }
    }

    func addTestCriterion() {
        testCaseCriteria.append(TestCriterionDefinition(
            name: "새 기준",
            expectedField: testCaseExpectedFields.first ?? "",
            expectedMinField: "",
            expectedMaxField: "",
            outputPath: promptOutputSchemaPaths.first ?? "",
            valueType: .text,
            passRule: .exact
        ))
    }

    func removeTestCriterion(id: UUID) {
        testCaseCriteria.removeAll { $0.id == id }
    }

    func addArrayAssertion(to criterionID: UUID, kind: ArrayObjectAssertionKind) {
        guard let index = testCaseCriteria.firstIndex(where: { $0.id == criterionID }) else { return }
        switch kind {
        case .datasetValue:
            testCaseCriteria[index].arrayAssertions.append(.datasetValue(
                field: testCaseExpectedFields.first ?? ""
            ))
        case .objectValueRange:
            let objectField = arrayObjectFields(at: testCaseCriteria[index].outputPath).first ?? ""
            let minimumField = testCaseExpectedFields.first(where: { $0.hasSuffix("_min") }) ?? ""
            let maximumField = testCaseExpectedFields.first(where: { $0.hasSuffix("_max") }) ?? ""
            testCaseCriteria[index].arrayAssertions.append(.objectValueRange(
                objectField: objectField,
                minimumField: minimumField,
                maximumField: maximumField
            ))
        case .objectValueAllowedValues:
            let objectField = arrayObjectFields(at: testCaseCriteria[index].outputPath).first ?? ""
            testCaseCriteria[index].arrayAssertions.append(.objectValueAllowedValues(
                objectField: objectField
            ))
        case .arrayValueRequired:
            let objectField = arrayObjectFields(at: testCaseCriteria[index].outputPath).first ?? ""
            testCaseCriteria[index].arrayAssertions.append(.arrayValueRequired(
                objectField: objectField
            ))
        case .arrayValueForbidden:
            let objectField = arrayObjectFields(at: testCaseCriteria[index].outputPath).first ?? ""
            testCaseCriteria[index].arrayAssertions.append(.arrayValueForbidden(
                objectField: objectField
            ))
        }
    }

    func removeArrayAssertion(from criterionID: UUID, assertionID: UUID) {
        guard let index = testCaseCriteria.firstIndex(where: { $0.id == criterionID }) else { return }
        testCaseCriteria[index].arrayAssertions.removeAll { $0.id == assertionID }
    }

    func startTestRun() {
        guard !isTestRunning, let testCase = selectedTestCase else {
            status = "실행할 테스트 케이스를 선택하세요."
            return
        }
        guard let dataset = savedDatasets.first(where: { $0.id == testCase.datasetID && $0.kind == .source }) else {
            status = "테스트 케이스의 원본 데이터셋을 찾을 수 없습니다."
            return
        }
        guard !dataset.rows.isEmpty else {
            status = "테스트 케이스의 데이터셋이 비어 있습니다."
            return
        }
        guard !providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "\(testCase.provider) API 키를 입력하세요."
            return
        }
        let count = min(max(testRunLimit, 1), dataset.rows.count)
        let startedAt = Date()
        let runID = UUID()
        activeTestRun = ActiveRunProgress(
            id: runID,
            name: testRunName(testCase.name, date: startedAt),
            detail: "\(testCase.datasetName) · \(testCase.modelID)",
            total: count
        )
        isTestRunning = true
        progress = 0
        activeTestRunTask = Task {
            await executeTestRun(
                testCase: testCase,
                dataset: dataset,
                count: count,
                runID: runID,
                startedAt: startedAt
            )
        }
    }

    func cancelTestRun() {
        guard isTestRunning else { return }
        activeTestRunTask?.cancel()
        status = "테스트 취소를 요청했습니다. 완료된 행까지 결과 파일로 저장합니다."
    }

    func retryTestRunRow(_ resultRow: TestRunRowResult, in run: SavedTestRun) {
        guard !isTestRunning, resultRow.error != nil else { return }
        guard !providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "\(run.provider) API 키를 입력하세요."
            return
        }
        guard let sourceDataset = savedDatasets.first(where: { $0.id == run.datasetID }),
              let sourceRow = sourceDataset.rows.first(where: { $0.id == resultRow.rowID }) else {
            status = "오류 행을 재실행할 원본 데이터셋 행을 찾을 수 없습니다."
            return
        }

        let retryID = UUID()
        activeTestRun = ActiveRunProgress(
            id: retryID,
            name: "\(run.testCaseName) 오류 재실행",
            detail: "\(run.datasetName) · \(run.modelID)",
            total: 1
        )
        isTestRunning = true
        progress = 0
        activeTestRunTask = Task {
            defer {
                isTestRunning = false
                activeTestRun = nil
                activeTestRunTask = nil
            }
            do {
                let renderedInput = try PromptTemplate.render(run.prompt, values: sourceRow.values)
                let generation = await executeGenerationJob(
                    LLMGenerationJob(index: 0, rowID: sourceRow.id, llmInput: renderedInput),
                    provider: ProviderKind(rawValue: run.provider) ?? .gemini,
                    apiKey: providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelID: run.modelID
                )
                let outputRecord = LLMOutputRecord(
                    rowID: sourceRow.id,
                    renderedInput: generation.llmInput,
                    output: generation.output,
                    error: generation.error,
                    provider: run.provider,
                    modelID: run.modelID,
                    latencyMilliseconds: generation.latencyMilliseconds,
                    inputTokens: generation.inputTokens,
                    outputTokens: generation.outputTokens
                )
                let criteriaResults = generation.output.map {
                    TestResultEvaluator.evaluate(criteria: run.criteria, values: sourceRow.values, output: $0)
                } ?? []
                let variableFields = PromptTemplate.variables(in: run.prompt)
                let updatedRow = TestRunRowResult(
                    id: outputRecord.id,
                    rowID: sourceRow.id,
                    variables: dictionary(sourceRow.values, keys: variableFields),
                    expectedValues: dictionaryExcluding(sourceRow.values, keys: variableFields),
                    displayDatasetValues: dictionary(sourceRow.values, keys: run.displayDatasetFields ?? []),
                    displayOutputValues: outputDisplayValues(generation.output, paths: run.displayOutputPaths ?? []),
                    criterionResults: criteriaResults,
                    latencyMilliseconds: generation.latencyMilliseconds,
                    inputTokens: generation.inputTokens,
                    outputTokens: generation.outputTokens,
                    modelID: run.modelID,
                    llmOutput: generation.output,
                    error: generation.error
                )
                var updatedRows = run.rows.filter { $0.rowID != sourceRow.id }
                updatedRows.append(updatedRow)
                updatedRows.sort { left, right in
                    let leftIndex = sourceDataset.rows.firstIndex { $0.id == left.rowID } ?? .max
                    let rightIndex = sourceDataset.rows.firstIndex { $0.id == right.rowID } ?? .max
                    return leftIndex < rightIndex
                }
                let updatedRun = SavedTestRun(
                    id: run.id,
                    name: run.name,
                    testCaseID: run.testCaseID,
                    testCaseName: run.testCaseName,
                    datasetID: run.datasetID,
                    datasetName: run.datasetName,
                    promptID: run.promptID,
                    promptName: run.promptName,
                    prompt: run.prompt,
                    provider: run.provider,
                    modelID: run.modelID,
                    criteria: run.criteria,
                    displayDatasetFields: run.displayDatasetFields,
                    displayOutputPaths: run.displayOutputPaths,
                    requestedCount: run.requestedCount,
                    status: .completed,
                    startedAt: run.startedAt,
                    completedAt: Date(),
                    rows: updatedRows
                )
                var updatedOutputs = try TestRunStore.loadOutputs(for: run.id)
                updatedOutputs.removeAll { $0.rowID == sourceRow.id }
                updatedOutputs.append(outputRecord)
                try TestRunStore.save(updatedRun, outputs: updatedOutputs)
                testRuns = try TestRunStore.loadAll()
                selectedTestRunID = run.id
                progress = 1
                status = generation.error == nil
                    ? "오류 테스트 행을 재실행해 기존 결과에 반영했습니다."
                    : "오류 테스트 행 재실행이 다시 실패했습니다."
                notify(status)
            } catch {
                status = "오류 테스트 행 재실행 실패: \(error.localizedDescription)"
            }
        }
    }

    func refreshTestRuns() {
        do {
            let previous = selectedTestRunID
            testRuns = try TestRunStore.loadAll()
            selectedTestRunID = previous.flatMap { id in testRuns.contains(where: { $0.id == id }) ? id : nil }
                ?? testRuns.first?.id
            status = "테스트 결과 \(testRuns.count)개를 불러왔습니다."
        } catch {
            status = "테스트 결과를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    func selectTestRun(_ id: UUID?) {
        selectedTestRunID = id
        evaluationBundleURL = nil
        evaluationSummary = nil
        if let run = selectedTestRun {
            codexJudgeLimit = run.rows.count
            status = "테스트 결과를 선택했습니다: \(run.name)"
        }
    }

    func openSelectedTestRun() {
        guard let run = selectedTestRun, let folder = try? TestRunStore.folderURL(for: run.id) else {
            status = "확인할 테스트 결과를 선택하세요."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func deleteSelectedTestRun() {
        guard !isTestRunning else {
            status = "테스트 실행 중에는 결과를 삭제할 수 없습니다."
            return
        }
        guard let run = selectedTestRun else {
            status = "삭제할 테스트 결과를 선택하세요."
            return
        }
        let alert = NSAlert()
        alert.messageText = "테스트 결과를 삭제할까요?"
        alert.informativeText = "LLM output과 테스트 결과 파일 전체가 삭제됩니다. 이미 생성된 평가 결과는 유지됩니다. 이 작업은 되돌릴 수 없습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try TestRunStore.delete(run)
            if evaluationBundleURL != nil {
                evaluationBundleURL = nil
                evaluationSummary = nil
            }
            selectedTestRunID = nil
            refreshTestRuns()
            status = "테스트 결과를 삭제했습니다: \(run.name)"
            notify(status)
        } catch {
            status = "테스트 결과를 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func run() {
        Task {
            guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = "프롬프트를 먼저 불러오세요."
                return
            }
            guard !rows.isEmpty else {
                status = "데이터셋을 먼저 불러오세요."
                return
            }
            guard missingVariables.isEmpty else {
                status = "데이터셋에 없는 변수입니다: \(missingVariables.joined(separator: ", "))"
                return
            }
            guard !selectedModelID.isEmpty else {
                status = "제공 서비스를 연결하고 모델을 선택하세요."
                return
            }

            let sourceDatasetName = datasetName
            let sourceHeaders = headers
            let sourceRows = rows
            let runCount = runLimit == 0 ? sourceRows.count : min(max(runLimit, 0), sourceRows.count)
            guard runCount > 0 else {
                status = "실행 행 수는 1 이상이거나 전체 실행을 위한 0이어야 합니다."
                return
            }

            let runPrompt = promptText
            let runPromptName = promptName
            let runProvider = provider
            let runAPIKey = providerAPIKey
            let runModelID = selectedModelID
            let runModelName = selectedModelName
            let evaluationRows = sourceRows.prefix(runCount).map { DatasetRow(values: $0.values) }
            let evaluationDataset = SavedDataset(
                name: evaluationDatasetName(source: sourceDatasetName, prompt: runPromptName, model: runModelName),
                headers: sourceHeaders,
                rows: evaluationRows,
                fileExtension: "csv",
                kind: .evaluation,
                sourceDatasetName: sourceDatasetName,
                evaluationPromptName: runPromptName,
                evaluationPrompt: runPrompt,
                evaluationProvider: runProvider.rawValue,
                evaluationModel: runModelName
            )

            do {
                try GenerationCheckpointStore.prepare(datasetID: evaluationDataset.id)
            } catch {
                status = "증분 저장 파일을 준비하지 못했습니다: \(error.localizedDescription)"
                return
            }

            savedDatasets.insert(evaluationDataset, at: 0)
            selectedDatasetID = evaluationDataset.id
            datasetName = evaluationDataset.name
            headers = evaluationDataset.headers
            rows = evaluationDataset.rows
            evaluationBundleURL = nil
            evaluationSummary = nil
            persistLibrary()

            isRunning = true
            progress = 0
            status = "원본을 보존하고 LLM 실행 데이터셋을 생성했습니다. 출력을 생성하는 중..."
            var jobs: [LLMGenerationJob] = []
            var checkpointError: String?
            for index in rows.indices {
                do {
                    let rendered = try PromptTemplate.render(runPrompt, values: rows[index].values)
                    rows[index].llmInput = rendered
                    jobs.append(LLMGenerationJob(index: index, rowID: rows[index].id, llmInput: rendered))
                } catch {
                    rows[index].error = error.localizedDescription
                    rows[index].output = nil
                    progress += 1
                    do {
                        try GenerationCheckpointStore.append(GenerationCheckpointRecord(
                            datasetID: evaluationDataset.id,
                            rowID: rows[index].id,
                            llmInput: nil,
                            output: nil,
                            error: error.localizedDescription,
                            outputModel: runModelID,
                            latencyMilliseconds: nil,
                            inputTokens: nil,
                            outputTokens: nil
                        ))
                    } catch {
                        checkpointError = error.localizedDescription
                    }
                }
            }

            let concurrentRequestCount = min(max(generationConcurrency, 1), max(jobs.count, 1))
            await withTaskGroup(of: LLMGenerationResult.self) { group in
                var nextJobIndex = 0
                for _ in 0..<min(concurrentRequestCount, jobs.count) {
                    let job = jobs[nextJobIndex]
                    nextJobIndex += 1
                    group.addTask {
                        await executeGenerationJob(job, provider: runProvider, apiKey: runAPIKey, modelID: runModelID)
                    }
                }

                while let result = await group.next() {
                    rows[result.index].llmInput = result.llmInput
                    rows[result.index].output = result.output
                    rows[result.index].error = result.error
                    rows[result.index].outputModel = result.outputModel
                    rows[result.index].latencyMilliseconds = result.latencyMilliseconds
                    rows[result.index].inputTokens = result.inputTokens
                    rows[result.index].outputTokens = result.outputTokens
                    progress += 1
                    status = "LLM 출력 생성 중: \(progress) / \(rows.count) · 동시 실행 \(concurrentRequestCount)개"
                    do {
                        try GenerationCheckpointStore.append(GenerationCheckpointRecord(
                            datasetID: evaluationDataset.id,
                            rowID: result.rowID,
                            llmInput: result.llmInput,
                            output: result.output,
                            error: result.error,
                            outputModel: result.outputModel,
                            latencyMilliseconds: result.latencyMilliseconds,
                            inputTokens: result.inputTokens,
                            outputTokens: result.outputTokens
                        ))
                    } catch {
                        checkpointError = error.localizedDescription
                    }

                    if nextJobIndex < jobs.count {
                        let job = jobs[nextJobIndex]
                        nextJobIndex += 1
                        group.addTask {
                            await executeGenerationJob(job, provider: runProvider, apiKey: runAPIKey, modelID: runModelID)
                        }
                    }
                }
            }

            isRunning = false
            updateEvaluationDataset(evaluationDataset.id, persist: false)
            do {
                try LibraryStore.save(SavedLibrary(prompts: savedPrompts, datasets: savedDatasets))
                try GenerationCheckpointStore.remove(datasetID: evaluationDataset.id)
            if let checkpointError {
                status = "출력 생성을 완료했습니다. 일부 증분 저장 경고: \(checkpointError)"
            } else {
                status = "원본을 변경하지 않고 LLM 실행 데이터셋 \(datasetName)에 \(rows.count)건의 출력을 생성했습니다."
            }
            notify(status)
            } catch {
                status = "출력은 생성했지만 최종 저장에 실패했습니다: \(error.localizedDescription)"
            }
        }
    }

    func exportDataset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "prompt-results.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try CSVCodec.encode(headers: headers, rows: rows).write(to: url, atomically: true, encoding: .utf8)
            status = "데이터셋을 \(url.lastPathComponent)으로 내보냈습니다."
        } catch {
            status = error.localizedDescription
        }
    }

    func exportCurrentPrompt() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "내보낼 프롬프트가 없습니다."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!, .plainText]
        let safeName = promptName.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(safeName.isEmpty ? "prompt" : safeName).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try promptText.write(to: url, atomically: true, encoding: .utf8)
            status = "프롬프트를 내보냈습니다: \(url.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }

    func generateEvaluationBundle() {
        do {
            guard !isRunning else {
                status = "출력 생성이 끝난 뒤 평가 번들을 만들 수 있습니다."
                return
            }
            guard let run = selectedTestRun, run.status == .completed else {
                status = "완료된 테스트 결과 파일을 선택하세요."
                return
            }
            let prompt = evaluationPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                status = "평가 프롬프트를 입력하세요."
                return
            }
            let evaluationRows = run.rows.filter { $0.llmOutput != nil }.map { row in
                var values = row.variables.merging(row.expectedValues) { _, expected in expected }
                for (path, value) in row.displayOutputValues ?? [:] {
                    values["display.output.\(path)"] = value
                }
                for result in row.criterionResults {
                    let prefix = "criterion.\(result.name)"
                    values["\(prefix).expected"] = result.expected
                    values["\(prefix).actual"] = result.actual
                    values["\(prefix).rule"] = result.passRule
                    values["\(prefix).pass"] = String(result.passed)
                }
                return DatasetRow(
                    id: row.rowID,
                    values: values,
                    llmInput: try? PromptTemplate.render(run.prompt, values: values),
                    output: row.llmOutput,
                    error: row.error,
                    outputModel: row.modelID,
                    latencyMilliseconds: row.latencyMilliseconds,
                    inputTokens: row.inputTokens,
                    outputTokens: row.outputTokens
                )
            }
            guard !evaluationRows.isEmpty else {
                status = "선택한 테스트 결과에 평가 가능한 LLM output이 없습니다."
                return
            }
            evaluationBundleURL = try EvaluationBundle.write(input: EvaluationInput(
                prompt: run.prompt,
                evaluationPrompt: prompt,
                provider: run.provider,
                model: run.modelID,
                rows: evaluationRows,
                datasetName: run.name,
                sourceDatasetName: run.datasetName,
                promptName: run.promptName,
                testCaseName: run.testCaseName,
                criteria: run.criteria,
                displayDatasetFields: run.displayDatasetFields,
                displayOutputPaths: run.displayOutputPaths
            ))
            evaluationSummary = nil
            evaluationProgress = 0
            evaluationTotal = minEvaluationCount(totalRows: evaluationRows.count)
            selectedEvaluationResultID = evaluationBundleURL?.lastPathComponent
            refreshEvaluationResults(silent: true)
            status = "Promptfoo + Codex 평가 번들을 만들었습니다."
            notify(status)
        } catch {
            status = error.localizedDescription
        }
    }

    func resetEvaluationPrompt() {
        evaluationPrompt = Self.defaultEvaluationPrompt
        status = "기본 평가 프롬프트로 되돌렸습니다."
        notify(status)
    }

    func recommendEvaluationPrompt() {
        guard !isRecommendingEvaluationPrompt,
              let run = selectedTestRun,
              run.status == .completed else {
            status = "완료된 테스트 결과를 선택한 뒤 평가 프롬프트를 추천받으세요."
            return
        }
        let model = codexEvaluationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            status = "추천에 사용할 평가 모델을 선택하세요."
            return
        }

        Task {
            isRecommendingEvaluationPrompt = true
            defer { isRecommendingEvaluationPrompt = false }
            do {
                evaluationPrompt = try await EvaluationPromptRecommendationService.recommend(
                    model: model,
                    originalPrompt: run.prompt,
                    criteria: run.criteria
                )
                status = "\(model)로 평가 프롬프트를 추천했습니다."
                notify(status)
            } catch {
                status = "평가 프롬프트 추천 실패: \(error.localizedDescription)"
            }
        }
    }

    func runEvaluation() {
        guard let evaluationBundleURL else {
            status = "평가 번들을 먼저 만드세요."
            return
        }
        let retryRowID = evaluationRetryRowID
        let evaluationModel = codexEvaluationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evaluationModel.isEmpty else {
            status = "평가에 사용할 Codex 모델을 입력하세요."
            return
        }
        let hasCompletedLog = FileManager.default.fileExists(
            atPath: evaluationBundleURL.appendingPathComponent("results/evaluation-log.json").path
        )
        guard !hasCompletedLog || retryRowID != nil else {
            status = "완료된 평가 로그는 수정할 수 없습니다. 새 평가 번들을 만들어 실행하세요."
            return
        }
        Task {
            do {
                defer { evaluationRetryRowID = nil }
                isEvaluating = true
                evaluationProgress = 0
                let inputURL = evaluationBundleURL.appendingPathComponent("eval-input.json")
                let input = try JSONDecoder().decode(EvaluationInput.self, from: Data(contentsOf: inputURL))
                evaluationTotal = retryRowID == nil ? minEvaluationCount(totalRows: input.rows.count) : 1
                activeEvaluationRun = ActiveRunProgress(
                    id: UUID(),
                    name: input.testCaseName ?? input.promptName ?? input.datasetName ?? "평가 실행",
                    detail: "\(input.sourceDatasetName ?? input.datasetName ?? "데이터셋 정보 없음") · \(evaluationModel)",
                    total: evaluationTotal
                )
                let bundleNodeModules = evaluationBundleURL.appendingPathComponent("node_modules", isDirectory: true)
                if !FileManager.default.fileExists(atPath: bundleNodeModules.path) {
                    let runtime = try EvaluationBundle.prepareSharedRuntime()
                    if runtime.needsInstall {
                        status = "공용 평가 의존성을 처음 한 번 설치하는 중..."
                        try await ProcessRunner.run(
                            command: "pnpm",
                            arguments: ["install", "--ignore-scripts"],
                            workingDirectory: runtime.directory
                        )
                        try EvaluationBundle.markSharedRuntimeReady(at: runtime.directory)
                    }
                    try EvaluationBundle.linkSharedRuntime(from: runtime.directory, to: evaluationBundleURL)
                }

                let judgeLimit = retryRowID == nil ? max(codexJudgeLimit, 0) : 1
                let judgeConcurrency = min(max(codexConcurrency, 2), 8)
                status = retryRowID == nil
                    ? "Promptfoo 검증 후 Codex 평가를 시작합니다."
                    : "오류 행 1개의 Codex 평가를 다시 실행합니다."
                let progressTask = Task {
                    await monitorEvaluationProgress(
                        at: evaluationBundleURL.appendingPathComponent("results/codex-judgements.json")
                    )
                }
                defer { progressTask.cancel() }
                var environment = [
                    "JUDGE_LIMIT": String(judgeLimit),
                    "CODEX_CONCURRENCY": String(judgeConcurrency),
                    "CODEX_MODEL": evaluationModel,
                ]
                if let retryRowID {
                    environment["JUDGE_ROW_IDS"] = retryRowID
                }
                try await ProcessRunner.run(
                    command: "pnpm",
                    arguments: ["run", "eval"],
                    workingDirectory: evaluationBundleURL,
                    environment: environment
                )
                evaluationProgress = evaluationTotal
                try EvaluationBundle.lockCompletedResults(in: evaluationBundleURL)
                let summaryURL = evaluationBundleURL.appendingPathComponent("results/summary.json")
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let summary = try decoder.decode(EvaluationRunSummary.self, from: Data(contentsOf: summaryURL))
                evaluationSummary = summary
                selectedEvaluationResultID = evaluationBundleURL.lastPathComponent
                refreshEvaluationResults(silent: true)
                if retryRowID != nil {
                    status = "오류 평가 행을 재실행해 기존 평가 로그에 반영했습니다."
                } else if summary.codexErrors == 0 {
                    status = "평가를 완료했습니다. Codex 평균 점수: \(formattedScore(summary.codexAverageScore))"
                } else {
                    status = "평가를 완료했지만 Codex 판정 \(summary.codexErrors)건이 실패했습니다."
                }
                notify(status)
            } catch {
                status = error.localizedDescription
            }
            isEvaluating = false
            activeEvaluationRun = nil
        }
    }

    func retryEvaluationJudgement(_ judgement: CodexJudgementRecord, in result: EvaluationResultRecord) {
        guard !isEvaluating, judgement.judge == nil else { return }
        do {
            try EvaluationBundle.unlockCompletedResults(in: result.folderURL)
            evaluationBundleURL = result.folderURL
            evaluationSummary = nil
            evaluationProgress = 0
            evaluationTotal = 1
            selectedEvaluationResultID = result.id
            evaluationRetryRowID = judgement.rowId
            status = "오류 평가 행을 기존 로그에서 재실행합니다."
            runEvaluation()
        } catch {
            status = "오류 행 평가 재실행 준비 실패: \(error.localizedDescription)"
        }
    }

    private func minEvaluationCount(totalRows: Int) -> Int {
        let limit = max(codexJudgeLimit, 0)
        return limit == 0 ? totalRows : min(limit, totalRows)
    }

    private func monitorEvaluationProgress(at judgementsURL: URL) async {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        while !Task.isCancelled {
            if let data = try? Data(contentsOf: judgementsURL),
               let judgements = try? decoder.decode([CodexJudgementRecord].self, from: data) {
                evaluationProgress = min(judgements.count, evaluationTotal)
                status = "Codex 평가 진행 중: \(evaluationProgress)/\(evaluationTotal)"
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    func refreshEvaluationResults(silent: Bool = false) {
        do {
            let previousSelection = selectedEvaluationResultID
            evaluationResults = try EvaluationResultStore.load()
            if let previousSelection, evaluationResults.contains(where: { $0.id == previousSelection }) {
                selectedEvaluationResultID = previousSelection
            } else {
                selectedEvaluationResultID = evaluationResults.first?.id
            }
            if !silent {
                status = "평가 결과 \(evaluationResults.count)개를 불러왔습니다."
            }
        } catch {
            if !silent {
                status = "평가 결과를 불러오지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    func openSelectedEvaluationResult() {
        guard let result = selectedEvaluationResult else {
            status = "확인할 평가 결과를 선택하세요."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([result.folderURL])
    }

    func shareSelectedEvaluationResultToPromptfoo() {
        let apiKey = promptfooAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            status = "Promptfoo API 키를 입력한 뒤 평가 결과를 전송하세요."
            return
        }
        guard let result = selectedEvaluationResult else {
            status = "Promptfoo로 전송할 평가 결과를 선택하세요."
            return
        }
        guard result.isComplete else {
            status = "완료된 평가 결과만 Promptfoo로 전송할 수 있습니다."
            return
        }
        guard result.integrity != .invalid else {
            status = "무결성 검증에 실패한 평가 로그는 Promptfoo로 전송할 수 없습니다."
            return
        }

        Task {
            do {
                isSharingEvaluation = true
                let bundleNodeModules = result.folderURL.appendingPathComponent("node_modules", isDirectory: true)
                if !FileManager.default.fileExists(atPath: bundleNodeModules.path) {
                    let runtime = try EvaluationBundle.prepareSharedRuntime()
                    if runtime.needsInstall {
                        status = "Promptfoo 공유 의존성을 처음 한 번 설치하는 중..."
                        try await ProcessRunner.run(
                            command: "pnpm",
                            arguments: ["install", "--ignore-scripts"],
                            workingDirectory: runtime.directory
                        )
                        try EvaluationBundle.markSharedRuntimeReady(at: runtime.directory)
                    }
                    try EvaluationBundle.linkSharedRuntime(from: runtime.directory, to: result.folderURL)
                }

                status = "저장된 Codex 평가 결과를 Promptfoo 형식으로 준비하는 중..."
                let shareRuntime = try EvaluationBundle.preparePromptfooShareRuntime(for: result.folderURL)
                defer { try? FileManager.default.removeItem(at: shareRuntime.directory) }
                try await ProcessRunner.run(
                    command: "node",
                    arguments: [shareRuntime.scriptURL.lastPathComponent],
                    workingDirectory: shareRuntime.directory,
                    environment: ["PROMPTEVAL_BUNDLE": result.folderURL.path]
                )

                status = "최종 정성 평가 결과를 Promptfoo Cloud로 전송하는 중..."
                try await ProcessRunner.run(
                    command: "pnpm",
                    arguments: ["exec", "promptfoo", "share"],
                    workingDirectory: shareRuntime.directory,
                    environment: ["PROMPTFOO_API_KEY": apiKey]
                )
                status = "최종 Codex 정성 평가 결과를 Promptfoo로 전송했습니다. Promptfoo Cloud에서 공유된 평가를 확인하세요."
            } catch {
                status = "Promptfoo 전송 실패: \(error.localizedDescription)"
            }
            isSharingEvaluation = false
        }
    }

    func deleteSelectedEvaluationResult() {
        guard let result = selectedEvaluationResult else {
            status = "삭제할 평가 결과를 선택하세요."
            return
        }
        let alert = NSAlert()
        alert.messageText = "평가 결과를 삭제할까요?"
        alert.informativeText = "읽기 전용 평가 로그와 내보내기 데이터를 포함한 실행 기록 전체가 삭제됩니다. 이 작업은 되돌릴 수 없습니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try EvaluationBundle.deleteEvaluation(at: result.folderURL)
            if evaluationBundleURL == result.folderURL {
                evaluationBundleURL = nil
                evaluationSummary = nil
            }
            selectedEvaluationResultID = nil
            refreshEvaluationResults(silent: true)
            status = "평가 결과를 삭제했습니다."
            notify(status)
        } catch {
            status = "평가 결과를 삭제하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func exportSelectedEvaluationData(format: EvaluationExportFormat) {
        guard let result = selectedEvaluationResult else {
            status = "내보낼 평가 결과를 선택하세요."
            return
        }
        let sourceURL = format == .csv ? result.evaluatedCSVURL : result.evaluatedJSONURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            status = "이 결과에는 평가 완료 데이터 파일이 없습니다. 새 평가 번들로 다시 실행하세요."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let baseName = result.input.promptName ?? "evaluated-dataset"
        panel.nameFieldStringValue = "\(baseName)-evaluated.\(format.fileExtension)"
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
            status = "평가 완료 데이터를 내보냈습니다: \(destinationURL.lastPathComponent)"
        } catch {
            status = "평가 완료 데이터를 내보내지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func executeTestRun(
        testCase: SavedTestCase,
        dataset: SavedDataset,
        count: Int,
        runID: UUID,
        startedAt: Date
    ) async {
        isTestRunning = true
        progress = 0
        let sourceRows = Array(dataset.rows.prefix(count))
        let runProvider = ProviderKind(rawValue: testCase.provider) ?? .gemini
        let apiKey = providerAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var jobs: [LLMGenerationJob] = []
        var outputRecords: [LLMOutputRecord] = []
        var resultRows: [TestRunRowResult] = []

        for (index, row) in sourceRows.enumerated() {
            do {
                let rendered = try PromptTemplate.render(testCase.prompt, values: row.values)
                jobs.append(LLMGenerationJob(index: index, rowID: row.id, llmInput: rendered))
            } catch {
                resultRows.append(TestRunRowResult(
                    id: UUID(),
                    rowID: row.id,
                    variables: dictionary(row.values, keys: PromptTemplate.variables(in: testCase.prompt)),
                    expectedValues: dictionaryExcluding(row.values, keys: PromptTemplate.variables(in: testCase.prompt)),
                    displayDatasetValues: dictionary(row.values, keys: testCase.displayDatasetFields ?? []),
                    displayOutputValues: [:],
                    criterionResults: [],
                    latencyMilliseconds: 0,
                    inputTokens: nil,
                    outputTokens: nil,
                    modelID: testCase.modelID,
                    llmOutput: nil,
                    error: error.localizedDescription
                ))
                progress += 1
            }
        }

        let concurrency = min(max(generationConcurrency, 1), max(jobs.count, 1))
        await withTaskGroup(of: LLMGenerationResult.self) { group in
            var nextJobIndex = 0
            for _ in 0..<min(concurrency, jobs.count) {
                let job = jobs[nextJobIndex]
                nextJobIndex += 1
                group.addTask {
                    await executeGenerationJob(job, provider: runProvider, apiKey: apiKey, modelID: testCase.modelID)
                }
            }

            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                guard let row = sourceRows.first(where: { $0.id == result.rowID }) else { continue }
                let outputRecord = LLMOutputRecord(
                    rowID: row.id,
                    renderedInput: result.llmInput,
                    output: result.output,
                    error: result.error,
                    provider: testCase.provider,
                    modelID: testCase.modelID,
                    latencyMilliseconds: result.latencyMilliseconds,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens
                )
                outputRecords.append(outputRecord)
                let criteriaResults = result.output.map {
                    TestResultEvaluator.evaluate(criteria: testCase.criteria, values: row.values, output: $0)
                } ?? []
                let variableFields = PromptTemplate.variables(in: testCase.prompt)
                resultRows.append(TestRunRowResult(
                    id: outputRecord.id,
                    rowID: row.id,
                    variables: dictionary(row.values, keys: variableFields),
                    expectedValues: dictionaryExcluding(row.values, keys: variableFields),
                    displayDatasetValues: dictionary(row.values, keys: testCase.displayDatasetFields ?? []),
                    displayOutputValues: outputDisplayValues(result.output, paths: testCase.displayOutputPaths ?? []),
                    criterionResults: criteriaResults,
                    latencyMilliseconds: result.latencyMilliseconds,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens,
                    modelID: testCase.modelID,
                    llmOutput: result.output,
                    error: result.error
                ))
                progress += 1
                status = "테스트 실행 중: \(progress) / \(count) · 동시 실행 \(concurrency)개"

                if nextJobIndex < jobs.count, !Task.isCancelled {
                    let job = jobs[nextJobIndex]
                    nextJobIndex += 1
                    group.addTask {
                        await executeGenerationJob(job, provider: runProvider, apiKey: apiKey, modelID: testCase.modelID)
                    }
                }
            }
        }

        let wasCancelled = Task.isCancelled
        let run = SavedTestRun(
            id: runID,
            name: testRunName(testCase.name, date: startedAt),
            testCaseID: testCase.id,
            testCaseName: testCase.name,
            datasetID: dataset.id,
            datasetName: dataset.name,
            promptID: testCase.promptID,
            promptName: testCase.promptName,
            prompt: testCase.prompt,
            provider: testCase.provider,
            modelID: testCase.modelID,
            criteria: testCase.criteria,
            displayDatasetFields: testCase.displayDatasetFields,
            displayOutputPaths: testCase.displayOutputPaths,
            requestedCount: count,
            status: wasCancelled ? .cancelled : .completed,
            startedAt: startedAt,
            completedAt: Date(),
            rows: resultRows.sorted { left, right in
                let leftIndex = sourceRows.firstIndex { $0.id == left.rowID } ?? .max
                let rightIndex = sourceRows.firstIndex { $0.id == right.rowID } ?? .max
                return leftIndex < rightIndex
            }
        )
        do {
            try TestRunStore.save(run, outputs: outputRecords)
            testRuns = try TestRunStore.loadAll()
            selectedTestRunID = run.id
            status = wasCancelled
                ? "테스트를 취소하고 완료된 \(resultRows.count)개 행을 별도 결과로 저장했습니다."
                : "테스트 \(count)개 행을 완료하고 데이터셋과 분리된 결과 파일로 저장했습니다."
            notify(status)
        } catch {
            status = "테스트 결과 저장 실패: \(error.localizedDescription)"
        }
        isTestRunning = false
        activeTestRun = nil
        activeTestRunTask = nil
    }

    private func applyDataset(name: String, headers: [String], rows: [DatasetRow], fileExtension: String) {
        self.datasetName = name
        self.headers = headers
        self.rows = rows
        let dataset = SavedDataset(name: name, headers: headers, rows: rows, fileExtension: fileExtension)
        savedDatasets.insert(dataset, at: 0)
        selectedDatasetID = dataset.id
        persistLibrary()
        self.status = "\(name)에서 \(rows.count)개 행을 불러왔습니다."
    }

    private func updateEvaluationDataset(_ id: UUID, persist: Bool) {
        guard let index = savedDatasets.firstIndex(where: { $0.id == id }) else { return }
        savedDatasets[index].updateContents(headers: headers, rows: rows)
        if persist {
            persistLibrary()
        }
    }

    private func evaluationDatasetName(source: String, prompt: String, model: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "[LLM 실행] \(source) - \(prompt) - \(model) - \(formatter.string(from: Date()))"
    }

    private func formattedScore(_ score: Double?) -> String {
        guard let score else { return "-" }
        return score.formatted(.number.precision(.fractionLength(1)))
    }

    private func registerPrompt(name: String, content: String) {
        if let index = savedPrompts.firstIndex(where: { $0.name == name }) {
            savedPrompts[index].content = content
            savedPrompts[index].updatedAt = Date()
            selectedPromptID = savedPrompts[index].id
        } else {
            let prompt = SavedPrompt(name: name, content: content)
            savedPrompts.insert(prompt, at: 0)
            selectedPromptID = prompt.id
        }
        promptName = name
        promptText = content
        persistLibrary()
    }

    private func persistLibrary() {
        do {
            try LibraryStore.save(SavedLibrary(prompts: savedPrompts, datasets: savedDatasets))
        } catch {
            status = "라이브러리를 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func persistTestCases() {
        do {
            savedTestCases.sort { $0.updatedAt > $1.updatedAt }
            try TestCaseStore.save(savedTestCases)
        } catch {
            status = "테스트 케이스를 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func dictionary(_ values: [String: String], keys: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: keys.compactMap { key in values[key].map { (key, $0) } })
    }

    private func dictionaryExcluding(_ values: [String: String], keys: [String]) -> [String: String] {
        values.filter { !keys.contains($0.key) }
    }

    private func outputDisplayValues(_ output: String?, paths: [String]) -> [String: String] {
        guard let output, !paths.isEmpty else { return [:] }
        return Dictionary(uniqueKeysWithValues: paths.map { path in
            (path, JSONValueExtractor.value(at: path, in: output) ?? "")
        })
    }

    private func testRunName(_ testCaseName: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "\(testCaseName) - \(formatter.string(from: date))"
    }
}
