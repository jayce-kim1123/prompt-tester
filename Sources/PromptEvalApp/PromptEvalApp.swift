import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringAppToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringAppToFront()
        return true
    }

    private func bringAppToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct PromptEvalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1280, height: 880)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case workspace = "비교 작업공간"
    case prompts = "프롬프트"
    case datasets = "데이터셋"
    case evaluations = "평가 결과"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .workspace: "square.grid.2x2"
        case .prompts: "text.document"
        case .datasets: "tablecells"
        case .evaluations: "chart.bar.doc.horizontal"
        }
    }
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var selectedSection: AppSection = .workspace

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("프롬프트 실험실")
        } detail: {
            switch selectedSection {
            case .workspace:
                workspaceView
            case .prompts:
                promptLibraryView
            case .datasets:
                datasetLibraryView
            case .evaluations:
                evaluationResultsView
            }
        }
        .alert("데이터셋 가져오기 결과", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("확인") { state.alertMessage = nil }
        } message: {
            Text(state.alertMessage ?? "")
        }
    }

    private var workspaceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                workspaceSelectionSection
                providerSection
                runSection
                resultsSection
                evaluationSection
            }
            .padding(24)
        }
    }

    private var promptLibraryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader(title: "프롬프트", subtitle: "프롬프트를 등록하고 편집하거나 파일로 가져오고 내보냅니다.")
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("등록된 프롬프트")
                            .font(.headline)
                        Spacer()
                        Button { state.newPrompt() } label: { Image(systemName: "plus") }
                            .help("새 프롬프트")
                    }
                    List(selection: Binding(
                        get: { state.selectedPromptID },
                        set: { state.selectPrompt($0) }
                    )) {
                        ForEach(state.savedPrompts) { prompt in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(prompt.name)
                                Text(prompt.updatedAt.formatted(date: .numeric, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(prompt.id))
                        }
                    }
                    Button { state.choosePrompt() } label: {
                        Label("파일 가져오기", systemImage: "square.and.arrow.down")
                    }
                }
                .frame(minWidth: 230, idealWidth: 260)
                .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("프롬프트 이름", text: $state.promptName)
                        .font(.title3.weight(.semibold))
                    ScrollablePromptEditor(text: $state.promptText)
                        .frame(minHeight: 420)
                    HStack {
                        Button { state.saveCurrentPrompt() } label: {
                            Label("저장", systemImage: "square.and.arrow.down")
                        }
                        Button { state.exportCurrentPrompt() } label: {
                            Label("내보내기", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { state.deleteSelectedPrompt() } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        .disabled(state.selectedPromptID == nil)
                        Spacer()
                        Text("변수 \(state.promptVariables.count)개")
                            .foregroundStyle(.secondary)
                    }
                    if !state.promptVariables.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(state.promptVariables, id: \.self) { variable in
                                Text("{{\(variable)}}")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(24)
    }

    private var datasetLibraryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader(title: "데이터셋", subtitle: "등록된 데이터셋과 파일 정보를 확인하고 가져오기·수정·내보내기를 관리합니다.")
            HStack {
                Button { state.newDataset() } label: {
                    Label("새 데이터셋", systemImage: "plus")
                }
                .disabled(state.isRunning)
                Button { state.chooseDataset() } label: {
                    Label("파일 가져오기", systemImage: "square.and.arrow.down")
                }
                .disabled(state.isRunning)
                Button { state.exportDataset() } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
                .disabled(state.rows.isEmpty)
                Button(role: .destructive) { state.deleteSelectedDataset() } label: {
                    Label("삭제", systemImage: "trash")
                }
                .disabled(state.selectedDatasetID == nil || state.isRunning)
                Spacer()
                Text("총 \(state.savedDatasets.count)개")
                    .foregroundStyle(.secondary)
            }
            DatasetLibraryTable(
                datasets: state.savedDatasets,
                selection: Binding(
                    get: { state.selectedDatasetID },
                    set: { state.selectDataset($0) }
                )
            )
            .frame(minHeight: 220, idealHeight: 280)

            if state.selectedDatasetID != nil {
                GroupBox("선택한 데이터셋") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("데이터셋 이름", text: $state.datasetName)
                            Button { state.saveCurrentDataset() } label: {
                                Label("변경사항 저장", systemImage: "square.and.arrow.down")
                            }
                            .disabled(state.isRunning)
                            Text("\(state.rows.count)개 행")
                                .foregroundStyle(.secondary)
                        }
                        if !state.rows.isEmpty {
                            DatasetPreview(headers: state.headers, rows: state.rows)
                        } else {
                            ContentUnavailableView("데이터가 없습니다", systemImage: "tablecells", description: Text("CSV 또는 JSON 파일을 가져와 데이터셋을 등록하세요."))
                                .frame(height: 120)
                        }
                    }
                    .padding(.top, 6)
                }
            }

            DisclosureGroup("Google Sheet에서 데이터셋 등록") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("스프레드시트 ID", text: $state.spreadsheetID)
                        TextField("범위", text: $state.spreadsheetRange)
                            .frame(width: 180)
                    }
                    HStack {
                        SecureField("Google Sheets API 키", text: $state.googleAPIKey)
                        Button { pasteClipboard(into: $state.googleAPIKey) } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .help("클립보드에서 API 키 붙여넣기")
                        Button("시트 불러오기") { state.loadSpreadsheet() }
                            .disabled(state.isRunning)
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var evaluationResultsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHeader(title: "평가 결과", subtitle: "Promptfoo 검증과 Codex 판정 이력을 확인합니다.")
            HStack {
                Button { state.refreshEvaluationResults() } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                Button { state.openSelectedEvaluationResult() } label: {
                    Label("Finder에서 보기", systemImage: "folder")
                }
                .disabled(state.selectedEvaluationResult == nil)
                Menu {
                    Button("CSV") { state.exportSelectedEvaluationData(format: .csv) }
                    Button("JSON") { state.exportSelectedEvaluationData(format: .json) }
                } label: {
                    Label("평가 데이터 내보내기", systemImage: "square.and.arrow.up")
                }
                .disabled(state.selectedEvaluationResult?.hasEvaluatedDataset != true)
                Button(role: .destructive) { state.deleteSelectedEvaluationResult() } label: {
                    Label("평가 삭제", systemImage: "trash")
                }
                .disabled(state.selectedEvaluationResult == nil)
                Spacer()
                Text("총 \(state.evaluationResults.count)개")
                    .foregroundStyle(.secondary)
            }

            if state.evaluationResults.isEmpty {
                ContentUnavailableView(
                    "평가 결과가 없습니다",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("비교 작업공간에서 평가 번들을 만들고 평가를 실행하세요.")
                )
            } else {
                HSplitView {
                    List(selection: $state.selectedEvaluationResultID) {
                        ForEach(state.evaluationResults) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.input.promptName ?? result.input.datasetName ?? "평가 실행")
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text("\(result.input.sourceDatasetName ?? result.input.datasetName ?? "-") · \(result.input.model)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if let summary = result.summary {
                                    HStack(spacing: 10) {
                                        Text("평균 \(formatScore(summary.codexAverageScore))")
                                        Text("통과 \(formatPercent(result.passRate))")
                                        Text("\(formatLatency(result.averageLatencyMilliseconds))")
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 5) {
                                    Image(systemName: result.isComplete ? "checkmark.circle.fill" : "clock")
                                    Text(result.isComplete ? "완료" : "미완료")
                                    Text(result.executionDate.formatted(date: .numeric, time: .shortened))
                                    Spacer()
                                    Image(systemName: result.integrity.systemImage)
                                        .help(result.integrity.label)
                                }
                                .font(.caption2)
                                .foregroundStyle(result.integrity == .invalid ? Color.red : (result.isComplete ? Color.green : Color.secondary))
                            }
                            .tag(Optional(result.id))
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 300)

                    evaluationResultDetail
                        .frame(minWidth: 560)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var evaluationResultDetail: some View {
        if let result = state.selectedEvaluationResult {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.input.promptName ?? "이름 없는 프롬프트")
                            .font(.title3.weight(.semibold))
                        Text(result.input.sourceDatasetName ?? result.input.datasetName ?? "데이터셋 정보 없음")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(result.integrity.label, systemImage: result.integrity.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(result.integrity == .invalid ? Color.red : Color.secondary)
                }

                if let summary = result.summary {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 5) {
                        GridRow {
                            Text("출력 모델").foregroundStyle(.secondary)
                            Text(result.input.model)
                            Text("평가 모델").foregroundStyle(.secondary)
                            Text(summary.evaluationModel ?? result.judgements.first?.evaluationModel ?? "-")
                        }
                        GridRow {
                            Text("LLM 실행 데이터").foregroundStyle(.secondary)
                            Text(result.input.datasetName ?? "-").lineLimit(1)
                            Text("실행일").foregroundStyle(.secondary)
                            Text(result.executionDate.formatted(date: .numeric, time: .standard))
                        }
                        GridRow {
                            Text("저장 프롬프트").foregroundStyle(.secondary)
                            Text(result.input.promptName ?? "-").lineLimit(1)
                            Text("제공 서비스").foregroundStyle(.secondary)
                            Text(result.input.provider)
                        }
                    }
                    .font(.caption)

                    Divider()
                    HStack(spacing: 0) {
                        evaluationMetric("평균 점수", formatScore(summary.codexAverageScore))
                        Divider().frame(height: 34)
                        evaluationMetric("통과", "\(summary.codexPassed)/\(summary.codexCompleted) · \(formatPercent(result.passRate))")
                        Divider().frame(height: 34)
                        evaluationMetric("평균 레이턴시", formatLatency(result.averageLatencyMilliseconds))
                        Divider().frame(height: 34)
                        evaluationMetric("생성 토큰", "\(formatTokens(summary.generationInputTokens)) / \(formatTokens(summary.generationOutputTokens))")
                        Divider().frame(height: 34)
                        evaluationMetric("평가 토큰", "\(formatTokens(summary.evaluationInputTokens)) / \(formatTokens(summary.evaluationOutputTokens))")
                    }

                    HStack(spacing: 16) {
                        Label("JSON \(summary.promptfooPassed)/\(summary.promptfooValidated)", systemImage: "curlybraces.square")
                        Label("평가 \(summary.codexCompleted)/\(summary.codexRequested)", systemImage: "checkmark.seal")
                        if summary.codexErrors > 0 {
                            Label("오류 \(summary.codexErrors)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption)

                    Text("행별 Codex 판정")
                        .font(.headline)
                    if result.judgements.isEmpty {
                        ContentUnavailableView("판정 내역이 없습니다", systemImage: "doc.text.magnifyingglass")
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(result.judgements) { judgement in
                                    let row = result.datasetRow(for: judgement)
                                    let title = row?.values["source_data"] ?? "데이터 행"
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(title)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)
                                            Spacer()
                                            if let judge = judgement.judge {
                                                Label("\(judge.score)점", systemImage: judge.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                    .foregroundStyle(judge.pass ? .green : .red)
                                            } else {
                                                Label("오류", systemImage: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(.red)
                                            }
                                        }
                                        if let judge = judgement.judge {
                                            ForEach(judge.reasons, id: \.self) { reason in
                                                Text(reason)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let criteria = judge.criteria, !criteria.isEmpty {
                                                Divider()
                                                ForEach(criteria) { criterion in
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        HStack {
                                                            Label(criterion.name, systemImage: criterion.pass ? "checkmark.circle" : "xmark.circle")
                                                                .font(.caption.weight(.semibold))
                                                                .foregroundStyle(criterion.pass ? .green : .red)
                                                            Spacer()
                                                            Text("\(criterion.score)점")
                                                                .font(.caption.monospacedDigit())
                                                        }
                                                        Text("기대: \(criterion.expected)")
                                                            .font(.caption2)
                                                        Text("결과: \(criterion.observed)")
                                                            .font(.caption2)
                                                        Text(criterion.reason)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.vertical, 3)
                                                }
                                            }
                                        } else if let error = judgement.error {
                                            Text(error)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.red)
                                        }
                                        if let llmInput = result.llmInput(for: row) {
                                            Divider()
                                            HStack {
                                                Text("LLM 입력")
                                                Spacer()
                                                Text("출력 모델 \(row?.outputModel ?? result.input.model) · \(formatLatency(row?.latencyMilliseconds)) · 토큰 \(formatTokens(row?.inputTokens))/\(formatTokens(row?.outputTokens))")
                                            }
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            Text(llmInput)
                                                .font(.caption.monospaced())
                                                .lineLimit(4)
                                                .textSelection(.enabled)
                                        }
                                        if let modelOutput = row?.output {
                                            Text("LLM 출력")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                            Text(modelOutput)
                                                .font(.caption.monospaced())
                                                .lineLimit(4)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "평가가 완료되지 않았습니다",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("비교 작업공간에서 이 평가 번들을 다시 실행하세요.")
                    )
                }

                Text(result.folderURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        } else {
            ContentUnavailableView("평가 결과를 선택하세요", systemImage: "sidebar.left")
        }
    }

    private func evaluationMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
    }

    private func formatScore(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(1))) ?? "-"
    }

    private func formatPercent(_ value: Double?) -> String {
        value?.formatted(.percent.precision(.fractionLength(0))) ?? "-"
    }

    private func formatLatency(_ milliseconds: Double?) -> String {
        guard let milliseconds else { return "-" }
        if milliseconds >= 1_000 {
            return "\((milliseconds / 1_000).formatted(.number.precision(.fractionLength(1))))초"
        }
        return "\(milliseconds.formatted(.number.precision(.fractionLength(0))))ms"
    }

    private func formatTokens(_ value: Int?) -> String {
        value?.formatted(.number.grouping(.automatic)) ?? "-"
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("프롬프트 비교 작업 공간")
                    .font(.title2.weight(.semibold))
                Text(state.status)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isRunning || state.isEvaluating || state.isLoadingModels {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                Text(state.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var workspaceSelectionSection: some View {
        GroupBox("비교 대상") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("프롬프트", selection: Binding(
                        get: { state.selectedPromptID },
                        set: { state.selectPrompt($0) }
                    )) {
                        Text("프롬프트 선택").tag(UUID?.none)
                        ForEach(state.savedPrompts) { prompt in
                            Text(prompt.name).tag(Optional(prompt.id))
                        }
                    }
                    .disabled(state.isRunning)
                    Picker("데이터셋", selection: Binding(
                        get: { state.selectedDatasetID },
                        set: { state.selectDataset($0) }
                    )) {
                        Text("데이터셋 선택").tag(UUID?.none)
                        ForEach(state.savedDatasets) { dataset in
                            Text(dataset.name).tag(Optional(dataset.id))
                        }
                    }
                    .disabled(state.isRunning)
                }
                HStack(spacing: 18) {
                    Label("프롬프트 변수 \(state.promptVariables.count)개", systemImage: "curlybraces")
                    Label("데이터 \(state.rows.count)개 행", systemImage: "tablecells")
                    if !state.missingVariables.isEmpty {
                        Label("누락 변수: \(state.missingVariables.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var providerSection: some View {
        GroupBox("3. 모델 제공 서비스") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("제공 서비스", selection: $state.provider) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .onChange(of: state.provider) { _, _ in
                    state.models = []
                    state.selectedModelID = ""
                }

                HStack {
                    SecureField("\(state.provider.rawValue) API 키", text: $state.providerAPIKey)
                        .contextMenu {
                            Button("붙여넣기") { pasteClipboard(into: $state.providerAPIKey) }
                        }
                    Button { pasteClipboard(into: $state.providerAPIKey) } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("클립보드에서 API 키 붙여넣기")
                    Button { state.loadModels() } label: {
                        Label("모델 불러오기", systemImage: "arrow.clockwise")
                    }
                    .disabled(state.providerAPIKey.isEmpty || state.isLoadingModels)
                }

                if !state.models.isEmpty {
                    Picker("모델", selection: $state.selectedModelID) {
                        ForEach(state.models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                }
                Text("API 키는 이 앱 세션 동안에만 메모리에 보관됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var runSection: some View {
        GroupBox("4. LLM 실행 데이터셋 생성") {
            HStack(spacing: 12) {
                Text("실행 행 수")
                TextField("0", value: $state.runLimit, format: .number)
                    .frame(width: 72)
                Text(state.runLimit == 0 ? "0은 모든 행을 실행합니다" : "전체 실행 전에 작은 표본으로 확인하세요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(
                    "LLM 동시 요청 \(state.generationConcurrency)개",
                    value: $state.generationConcurrency,
                    in: 1...16
                )
                .frame(width: 190)
                .disabled(state.isRunning)
                Spacer()
                if state.isRunning {
                    ProgressView(value: Double(state.progress), total: Double(max(state.rows.count, 1)))
                        .frame(width: 150)
                }
                Button { state.run() } label: {
                    Label(state.isRunning ? "실행 중" : "LLM 실행 데이터셋 생성", systemImage: "play.fill")
                }
                .disabled(state.isRunning || state.rows.isEmpty || state.promptText.isEmpty || state.selectedModelID.isEmpty)
            }
            .padding(.top, 6)
        }
    }

    private var resultsSection: some View {
        GroupBox("5. 생성된 LLM 실행 데이터셋") {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.isEvaluationDatasetSelected
                     ? "\(state.completedCount) / \(state.rows.count)개 행에 모델 출력이 있습니다. 원본 데이터셋은 변경되지 않습니다."
                     : "출력을 생성하면 원본과 분리된 LLM 실행 데이터셋이 새로 만들어집니다.")
                    .foregroundStyle(.secondary)
                if let dataset = state.selectedDataset, dataset.kind == .evaluation {
                    HStack(spacing: 16) {
                        Label(dataset.sourceDatasetName ?? "-", systemImage: "tablecells")
                        Label(dataset.evaluationPromptName ?? "-", systemImage: "text.quote")
                        Label(dataset.evaluationModel ?? "-", systemImage: "cpu")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ResultsPreview(rows: state.rows)
            }
            .padding(.top, 6)
        }
    }

    private var evaluationSection: some View {
        GroupBox("6. Promptfoo + Codex 평가") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Promptfoo로 출력 JSON을 검증하고, 로컬 인증된 Codex SDK로 제한된 정성 평가를 수행하는 Node 번들을 만듭니다.")
                    .foregroundStyle(.secondary)
                HStack {
                    Text("평가 모델")
                    Picker("평가 모델", selection: $state.codexEvaluationModel) {
                        ForEach(state.codexEvaluationModelOptions, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                        .frame(width: 220)
                        .disabled(state.isEvaluating)
                    TextField("모델 ID 직접 입력", text: $state.codexEvaluationModel)
                        .frame(width: 190)
                        .disabled(state.isEvaluating)
                    Text("선택한 모델 ID는 평가 로그에 기록됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 18) {
                    Text("Codex 평가 행 수")
                    TextField("0", value: $state.codexJudgeLimit, format: .number)
                        .frame(width: 72)
                    Text("0은 출력이 있는 모든 행")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "Codex 동시 실행 \(state.codexConcurrency)개",
                        value: $state.codexConcurrency,
                        in: 2...4
                    )
                    .frame(width: 200)
                    .disabled(state.isEvaluating)
                    Spacer()
                }
                HStack {
                    Button { state.generateEvaluationBundle() } label: {
                        Label("평가 번들 만들기", systemImage: "folder.badge.plus")
                    }
                    .disabled(state.completedCount == 0 || state.isRunning || !state.isEvaluationDatasetSelected)
                    Button { state.runEvaluation() } label: {
                        Label("평가 실행", systemImage: "checkmark.seal")
                    }
                    .disabled(state.evaluationBundleURL == nil || state.isEvaluating || state.isRunning)
                    if let url = state.evaluationBundleURL {
                        Text(url.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Button { selectedSection = .evaluations } label: {
                    Label("평가 결과 보기", systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(state.evaluationResults.isEmpty)
                Text("평가 의존성은 공용 런타임에 한 번만 설치됩니다. Node, pnpm, 로컬 Codex 로그인이 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private func pasteClipboard(into binding: Binding<String>) {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            state.status = "클립보드에 붙여넣을 텍스트가 없습니다."
            return
        }
        binding.wrappedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        state.status = "API 키를 클립보드에서 붙여넣었습니다."
    }
}

private struct DatasetLibraryTable: View {
    let datasets: [SavedDataset]
    @Binding var selection: UUID?

    var body: some View {
        Table(datasets, selection: $selection) {
            TableColumn("데이터셋") { dataset in
                Text(dataset.name)
                    .fontWeight(.medium)
            }
            TableColumn("유형") { dataset in
                Text(dataset.kind.displayName)
            }
            .width(min: 60, ideal: 70)
            TableColumn("파일 확장자") { dataset in
                Text(dataset.fileExtension.uppercased())
            }
            .width(min: 90, ideal: 110)
            TableColumn("등록일") { dataset in
                Text(dataset.createdAt.formatted(date: .numeric, time: .shortened))
            }
            .width(min: 150, ideal: 180)
            TableColumn("용량") { dataset in
                Text(ByteCountFormatter.string(fromByteCount: Int64(dataset.byteSize), countStyle: .file))
            }
            .width(min: 90, ideal: 110)
        }
    }
}

private struct DatasetPreview: View {
    let headers: [String]
    let rows: [DatasetRow]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                GridRow {
                    ForEach(headers, id: \.self) { header in
                        Text(header).font(.caption.weight(.semibold)).frame(minWidth: 120, alignment: .leading)
                    }
                }
                ForEach(rows.prefix(8)) { row in
                    GridRow {
                        ForEach(headers, id: \.self) { header in
                            Text(row.values[header] ?? "")
                                .font(.caption)
                                .lineLimit(2)
                                .frame(width: 160, alignment: .leading)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 220)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ResultsPreview: View {
    let rows: [DatasetRow]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(rows.filter { $0.output != nil || $0.error != nil }.prefix(8)) { row in
                    let rowTitle = row.values["source_data"] ?? row.values.values.first ?? "데이터셋 행"
                    let rowContent = row.output ?? row.error ?? ""
                    let isError = row.error != nil
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rowTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let llmInput = row.llmInput {
                            Text("LLM 입력")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(llmInput)
                                .font(.caption.monospaced())
                                .lineLimit(3)
                        }
                        Text(isError ? "생성 오류" : "LLM 출력")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(rowContent)
                            .font(.caption.monospaced())
                            .lineLimit(4)
                            .foregroundStyle(isError ? .red : .primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxHeight: 260)
    }
}

private struct ScrollablePromptEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
