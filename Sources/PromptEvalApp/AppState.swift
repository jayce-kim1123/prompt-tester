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

    @Published var promptText = ""
    @Published var promptName = "새 프롬프트"
    @Published var savedPrompts: [SavedPrompt] = []
    @Published var selectedPromptID: UUID?
    @Published var datasetName = "불러온 데이터셋 없음"
    @Published var savedDatasets: [SavedDataset] = []
    @Published var selectedDatasetID: UUID?
    @Published var headers: [String] = []
    @Published var rows: [DatasetRow] = []
    @Published var provider: ProviderKind = .gemini
    @Published var providerAPIKey = ""
    @Published var models: [ModelOption] = []
    @Published var selectedModelID = ""
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
    @Published var isLoadingModels = false
    @Published var isRunning = false
    @Published var isEvaluating = false
    @Published var progress = 0
    @Published var status = "프롬프트와 데이터셋을 불러오세요."
    @Published var evaluationBundleURL: URL?
    @Published var evaluationSummary: EvaluationRunSummary?
    @Published var evaluationResults: [EvaluationResultRecord] = []
    @Published var selectedEvaluationResultID: String?
    @Published var alertMessage: String?

    var promptVariables: [String] { PromptTemplate.variables(in: promptText) }
    var missingVariables: [String] { promptVariables.filter { !headers.contains($0) } }
    var completedCount: Int { rows.filter { $0.output != nil }.count }
    var selectedModelName: String { models.first(where: { $0.id == selectedModelID })?.name ?? selectedModelID }
    var selectedDataset: SavedDataset? { savedDatasets.first(where: { $0.id == selectedDatasetID }) }
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

    init() {
        if UserDefaults.standard.object(forKey: "generationConcurrency") != nil {
            generationConcurrency = min(max(UserDefaults.standard.integer(forKey: "generationConcurrency"), 1), 16)
        }
        if UserDefaults.standard.object(forKey: "codexConcurrency") != nil {
            codexConcurrency = min(max(UserDefaults.standard.integer(forKey: "codexConcurrency"), 2), 4)
        }
        if UserDefaults.standard.object(forKey: "codexJudgeLimit") != nil {
            codexJudgeLimit = max(UserDefaults.standard.integer(forKey: "codexJudgeLimit"), 0)
        }
        if let savedModel = UserDefaults.standard.string(forKey: "codexEvaluationModel"), !savedModel.isEmpty {
            codexEvaluationModel = savedModel
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
            if let dataset = savedDatasets.first {
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
        } catch {
            status = error.localizedDescription
        }
    }

    func newPrompt() {
        saveCurrentPrompt(silent: true)
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
        saveCurrentPrompt(silent: true)
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
        if !silent { status = "프롬프트를 저장했습니다: \(name)" }
    }

    func deleteSelectedPrompt() {
        guard let id = selectedPromptID else { return }
        savedPrompts.removeAll { $0.id == id }
        selectedPromptID = nil
        promptName = "새 프롬프트"
        promptText = ""
        persistLibrary()
        status = "선택한 프롬프트를 라이브러리에서 삭제했습니다."
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
        if selectedDatasetID != nil {
            saveCurrentDataset(silent: true)
        }
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
        guard !isRunning else {
            if !silent { status = "출력 생성이 끝난 뒤 데이터셋을 저장할 수 있습니다." }
            return
        }
        let name = datasetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            if !silent { status = "데이터셋 이름을 입력하세요." }
            return
        }
        if let id = selectedDatasetID, let index = savedDatasets.firstIndex(where: { $0.id == id }) {
            savedDatasets[index].name = name
            savedDatasets[index].updateContents(headers: headers, rows: rows)
        } else {
            let dataset = SavedDataset(name: name, headers: headers, rows: rows, fileExtension: "json")
            savedDatasets.insert(dataset, at: 0)
            selectedDatasetID = dataset.id
        }
        persistLibrary()
        if !silent { status = "데이터셋을 저장했습니다: \(name)" }
    }

    func newDataset() {
        guard !isRunning else {
            status = "출력 생성이 끝난 뒤 새 데이터셋을 만들 수 있습니다."
            return
        }
        if selectedDatasetID != nil {
            saveCurrentDataset(silent: true)
        }
        let dataset = SavedDataset(name: "새 데이터셋", headers: [], rows: [], fileExtension: "json")
        savedDatasets.insert(dataset, at: 0)
        selectedDatasetID = dataset.id
        datasetName = dataset.name
        headers = []
        rows = []
        persistLibrary()
        status = "새 데이터셋을 만들었습니다. 파일을 가져오거나 이름을 변경할 수 있습니다."
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
                selectedModelID = loaded.first?.id ?? ""
                status = "모델 \(loaded.count)개를 불러왔습니다."
            } catch {
                status = error.localizedDescription
            }
            isLoadingModels = false
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
            guard let dataset = selectedDataset, dataset.kind == .evaluation else {
                status = "출력 생성으로 만든 LLM 실행 데이터셋을 선택하세요."
                return
            }
            guard completedCount > 0 else {
                status = "평가 번들을 만들기 전에 모델 출력을 생성하세요."
                return
            }
            evaluationBundleURL = try EvaluationBundle.write(input: EvaluationInput(
                prompt: dataset.evaluationPrompt ?? promptText,
                provider: dataset.evaluationProvider ?? provider.rawValue,
                model: rows.compactMap(\.outputModel).first ?? dataset.evaluationModel ?? selectedModelName,
                rows: rows,
                datasetName: dataset.name,
                sourceDatasetName: dataset.sourceDatasetName,
                promptName: dataset.evaluationPromptName
            ))
            evaluationSummary = nil
            selectedEvaluationResultID = evaluationBundleURL?.lastPathComponent
            refreshEvaluationResults(silent: true)
            status = "Promptfoo + Codex 평가 번들을 만들었습니다."
        } catch {
            status = error.localizedDescription
        }
    }

    func runEvaluation() {
        guard let evaluationBundleURL else {
            status = "평가 번들을 먼저 만드세요."
            return
        }
        let evaluationModel = codexEvaluationModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evaluationModel.isEmpty else {
            status = "평가에 사용할 Codex 모델을 입력하세요."
            return
        }
        guard !FileManager.default.fileExists(
            atPath: evaluationBundleURL.appendingPathComponent("results/evaluation-log.json").path
        ) else {
            status = "완료된 평가 로그는 수정할 수 없습니다. 새 평가 번들을 만들어 실행하세요."
            return
        }
        Task {
            do {
                isEvaluating = true
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

                let judgeLimit = max(codexJudgeLimit, 0)
                let judgeConcurrency = min(max(codexConcurrency, 2), 4)
                status = "Promptfoo와 Codex 평가를 실행하는 중: Codex 동시 실행 \(judgeConcurrency)개"
                try await ProcessRunner.run(
                    command: "pnpm",
                    arguments: ["run", "eval"],
                    workingDirectory: evaluationBundleURL,
                    environment: [
                        "JUDGE_LIMIT": String(judgeLimit),
                        "CODEX_CONCURRENCY": String(judgeConcurrency),
                        "CODEX_MODEL": evaluationModel,
                    ]
                )
                try EvaluationBundle.lockCompletedResults(in: evaluationBundleURL)
                let summaryURL = evaluationBundleURL.appendingPathComponent("results/summary.json")
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let summary = try decoder.decode(EvaluationRunSummary.self, from: Data(contentsOf: summaryURL))
                evaluationSummary = summary
                selectedEvaluationResultID = evaluationBundleURL.lastPathComponent
                refreshEvaluationResults(silent: true)
                if summary.codexErrors == 0 {
                    status = "평가를 완료했습니다. Codex 평균 점수: \(formattedScore(summary.codexAverageScore))"
                } else {
                    status = "평가를 완료했지만 Codex 판정 \(summary.codexErrors)건이 실패했습니다."
                }
            } catch {
                status = error.localizedDescription
            }
            isEvaluating = false
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

    private func applyDataset(name: String, headers: [String], rows: [DatasetRow], fileExtension: String) {
        self.datasetName = name
        self.headers = headers
        self.rows = rows
        if let index = savedDatasets.firstIndex(where: { $0.name == name }) {
            savedDatasets[index].fileExtension = fileExtension
            savedDatasets[index].updateContents(headers: headers, rows: rows)
            selectedDatasetID = savedDatasets[index].id
        } else {
            let dataset = SavedDataset(name: name, headers: headers, rows: rows, fileExtension: fileExtension)
            savedDatasets.insert(dataset, at: 0)
            selectedDatasetID = dataset.id
        }
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
}
