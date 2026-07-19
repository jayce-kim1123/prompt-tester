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
    case prompts = "프롬프트"
    case datasets = "데이터셋"
    case testCases = "테스트 케이스"
    case testRuns = "테스트"
    case evaluation = "평가"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .prompts: "text.document"
        case .datasets: "tablecells"
        case .testCases: "checklist"
        case .testRuns: "play.rectangle"
        case .evaluation: "checkmark.seal"
        }
    }
}

private enum EvaluationJudgementSort: String, CaseIterable, Identifiable {
    case tokens = "소모 토큰"
    case latency = "레이턴시"
    case score = "점수"

    var id: String { rawValue }
}

private enum EvaluationPassFilter: String, CaseIterable, Identifiable {
    case all = "전체"
    case passed = "통과"
    case failed = "실패"
    case error = "오류"

    var id: String { rawValue }
}

private enum TestResultRowSort: String, CaseIterable, Identifiable {
    case tokens = "소모 토큰"
    case latency = "레이턴시"
    case pass = "통과 여부"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var selectedSection: AppSection = .testCases
    @State private var judgementSort: EvaluationJudgementSort = .score
    @State private var judgementSortDescending = true
    @State private var judgementPassFilter: EvaluationPassFilter = .all
    @State private var minimumTokenFilter = ""
    @State private var maximumTokenFilter = ""
    @State private var minimumLatencyFilter = ""
    @State private var maximumLatencyFilter = ""
    @State private var minimumScoreFilter = ""
    @State private var maximumScoreFilter = ""
    @State private var testResultSort: TestResultRowSort = .latency
    @State private var testResultSortDescending = true
    @State private var testResultPassFilter: EvaluationPassFilter = .all
    @State private var minimumTestTokenFilter = ""
    @State private var maximumTestTokenFilter = ""
    @State private var minimumTestLatencyFilter = ""
    @State private var maximumTestLatencyFilter = ""
    @State private var isTestExecutionExpanded = true
    @State private var isEvaluationExecutionExpanded = true

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
            case .prompts:
                promptLibraryView
            case .datasets:
                datasetLibraryView
            case .testCases:
                testCaseView
            case .testRuns:
                testRunView
            case .evaluation:
                evaluationView
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
            pageHeader(title: "데이터셋", subtitle: "등록된 원본 데이터셋을 확인하고 가져오기·내보내기·삭제를 관리합니다. 데이터셋 내용은 읽기 전용입니다.")
            HStack {
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
                Text("총 \(state.sourceDatasets.count)개")
                    .foregroundStyle(.secondary)
            }
            DatasetLibraryTable(
                datasets: state.sourceDatasets,
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
                            Text(state.datasetName)
                                .font(.headline)
                            Text("\(state.rows.count)개 행")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("읽기 전용")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !state.rows.isEmpty {
                            DatasetPreview(headers: state.headers, rows: state.rows)
                                .id(state.selectedDatasetID)
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

    private var testCaseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pageHeader(title: "테스트 케이스", subtitle: "프롬프트와 원본 데이터셋을 연결하고 output 추출 기준과 PASS 규칙을 저장합니다.")

                HStack {
                    Picker("저장된 테스트 케이스", selection: Binding(
                        get: { state.selectedTestCaseID },
                        set: { state.selectTestCase($0) }
                    )) {
                        Text("새 테스트 케이스").tag(UUID?.none)
                        ForEach(state.savedTestCases) { testCase in
                            Text(testCase.name).tag(Optional(testCase.id))
                        }
                    }
                    .frame(maxWidth: 420)
                    Button { state.newTestCase() } label: {
                        Label("새로 만들기", systemImage: "plus")
                    }
                    Button { state.saveCurrentTestCase() } label: {
                        Label("저장", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) { state.deleteSelectedTestCase() } label: {
                        Label("삭제", systemImage: "trash")
                    }
                    .disabled(state.selectedTestCaseID == nil)
                    Spacer()
                }

                GroupBox("1. 입력과 실행 모델") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("테스트 케이스 이름", text: $state.testCaseName)
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
                            Picker("원본 데이터셋", selection: Binding(
                                get: { state.selectedDatasetID },
                                set: { state.selectDataset($0) }
                            )) {
                                Text("데이터셋 선택").tag(UUID?.none)
                                ForEach(state.sourceDatasets) { dataset in
                                    Text(dataset.name).tag(Optional(dataset.id))
                                }
                            }
                        }
                        HStack {
                            Picker("제공 서비스", selection: $state.provider) {
                                ForEach(ProviderKind.allCases) { provider in
                                    Text(provider.rawValue).tag(provider)
                                }
                            }
                            .frame(width: 230)
                            SecureField("API 키", text: $state.providerAPIKey)
                            Button { pasteClipboard(into: $state.providerAPIKey) } label: {
                                Image(systemName: "doc.on.clipboard")
                            }
                            .help("클립보드에서 API 키 붙여넣기")
                            Button { state.loadModels() } label: {
                                Label("모델 연결", systemImage: "arrow.clockwise")
                            }
                            .disabled(state.providerAPIKey.isEmpty || state.isLoadingModels)
                        }
                        HStack {
                            if !state.models.isEmpty {
                                Picker("실행 모델", selection: $state.selectedModelID) {
                                    ForEach(state.models) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .frame(maxWidth: 420)
                            }
                            TextField("실행 모델 ID", text: $state.selectedModelID)
                                .frame(maxWidth: 320)
                            Spacer()
                            Label("변수 \(state.promptVariables.count)개", systemImage: "curlybraces")
                            Label("기댓값 필드 \(state.testCaseExpectedFields.count)개", systemImage: "target")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("2. LLM output 구조 추출") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Button { state.runTestCasePreview() } label: {
                                Label(state.isPreviewingTestCase ? "추출 중" : "첫 행 output 추출", systemImage: "play.fill")
                            }
                            .disabled(state.isPreviewingTestCase || state.rows.isEmpty || state.promptText.isEmpty || state.selectedModelID.isEmpty)
                            if let output = state.sampleOutput {
                                Text("\(formatLatency(output.latencyMilliseconds)) · 토큰 \(formatTokens(output.inputTokens))/\(formatTokens(output.outputTokens)) · \(output.modelID)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        if let output = state.sampleOutput?.output {
                            ScrollView {
                                Text(output)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 120, maxHeight: 210)
                        } else {
                            Text("첫 번째 데이터 행의 LLM output을 가져와 선택 가능한 JSON 필드를 만듭니다.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("3. 평가 기준 매핑과 PASS 범위") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("추천 모델")
                            Picker("추천 모델", selection: $state.codexEvaluationModel) {
                                ForEach(state.codexEvaluationModelOptions, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                            Button { state.recommendCriteriaWithCodex() } label: {
                                Label(state.isRecommendingCriteria ? "추천 중" : "AI로 다시 추천", systemImage: "wand.and.stars")
                            }
                            .disabled(state.sampleOutput?.output == nil || state.isRecommendingCriteria)
                            Button { state.addTestCriterion() } label: {
                                Label("기준 추가", systemImage: "plus")
                            }
                            Spacer()
                        }

                        if state.testCaseCriteria.isEmpty {
                            Text("정량 평가 기준은 선택사항입니다. 기준 없이 저장하면 Codex가 원본 프롬프트와 전체 output을 정성 평가합니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($state.testCaseCriteria) { $criterion in
                                let outputPathOptions = Array(Set(state.sampleOutputPaths + [criterion.outputPath]))
                                    .filter { !$0.isEmpty }
                                    .sorted()
                                let objectFieldOptions = Array(Set(
                                    state.arrayObjectFields(at: criterion.outputPath) + [criterion.matchField ?? "", criterion.valueField ?? ""]
                                ))
                                .filter { !$0.isEmpty }
                                .sorted()
                                let matchValueOptions = Array(Set(
                                    state.arrayObjectValues(
                                        at: criterion.outputPath,
                                        field: criterion.matchField ?? ""
                                    ) + [criterion.matchValue ?? ""]
                                ))
                                .filter { !$0.isEmpty }
                                .sorted()
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        TextField("기준 이름", text: $criterion.name)
                                            .frame(width: 170)
                                        Picker("값 타입", selection: $criterion.valueType) {
                                            ForEach(CriterionValueType.allCases) { type in
                                                Text(type.rawValue).tag(type)
                                            }
                                        }
                                        .frame(width: 150)
                                        .onChange(of: criterion.valueType) { _, type in
                                            if type == .number,
                                               !criterion.expectedMinField.isEmpty,
                                               !criterion.expectedMaxField.isEmpty {
                                                criterion.passRule = .range
                                            } else if criterion.passRule == .range {
                                                criterion.passRule = .exact
                                            }
                                        }
                                        Picker("PASS 규칙", selection: $criterion.passRule) {
                                            ForEach(PassRuleType.allCases) { rule in
                                                Text(rule.rawValue).tag(rule)
                                            }
                                        }
                                        .frame(width: 150)
                                        Spacer()
                                        Button(role: .destructive) { state.removeTestCriterion(id: criterion.id) } label: {
                                            Image(systemName: "trash")
                                        }
                                        .help("평가 기준 삭제")
                                    }
                                    if criterion.passRule == .arrayObjectCondition {
                                        HStack(spacing: 6) {
                                            Text("만약")
                                            Picker("배열", selection: $criterion.outputPath) {
                                                Text("선택").tag("")
                                                ForEach(outputPathOptions, id: \.self) { path in
                                                    Text(path).tag(path)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(width: 270)
                                            Text("에")
                                            Picker("일치 필드", selection: Binding(
                                                get: { criterion.matchField ?? "" },
                                                set: { criterion.matchField = $0 }
                                            )) {
                                                Text("선택").tag("")
                                                ForEach(objectFieldOptions, id: \.self) { field in
                                                    Text(field).tag(field)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(width: 150)
                                            Text("값이")
                                            Picker("일치 값", selection: Binding(
                                                get: { criterion.matchValue ?? "" },
                                                set: { criterion.matchValue = $0 }
                                            )) {
                                                Text("선택").tag("")
                                                ForEach(matchValueOptions, id: \.self) { value in
                                                    Text(value).tag(value)
                                                }
                                            }
                                            .labelsHidden()
                                            .frame(width: 170)
                                            Text("인 요소가 있다면")
                                            Spacer()
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach($criterion.arrayAssertions) { $assertion in
                                                HStack(spacing: 6) {
                                                    Text("•")
                                                        .foregroundStyle(.secondary)
                                                    switch assertion.kind {
                                                    case .datasetValue:
                                                        Text("데이터셋의")
                                                        Picker("필드", selection: $assertion.datasetField) {
                                                            Text("선택").tag("")
                                                            ForEach(state.testCaseExpectedFields, id: \.self) { field in
                                                                Text(field).tag(field)
                                                            }
                                                        }
                                                        .labelsHidden()
                                                        .frame(width: 220)
                                                        Text("는 값이")
                                                        Picker("값", selection: $assertion.expectedValue) {
                                                            Text("1").tag("1")
                                                            Text("0").tag("0")
                                                        }
                                                        .labelsHidden()
                                                        .frame(width: 70)
                                                        Text("이어야 합니다.")
                                                    case .objectValueRange:
                                                        Text("해당 요소의")
                                                        Picker("측정 필드", selection: $assertion.objectField) {
                                                            Text("선택").tag("")
                                                            ForEach(objectFieldOptions, id: \.self) { field in
                                                                Text(field).tag(field)
                                                            }
                                                        }
                                                        .labelsHidden()
                                                        .frame(width: 170)
                                                        Text("는")
                                                        Picker("최솟값 필드", selection: $assertion.minimumField) {
                                                            Text("선택").tag("")
                                                            ForEach(state.testCaseExpectedFields, id: \.self) { field in
                                                                Text(field).tag(field)
                                                            }
                                                        }
                                                        .labelsHidden()
                                                        .frame(width: 210)
                                                        Text("이상")
                                                        Picker("최댓값 필드", selection: $assertion.maximumField) {
                                                            Text("선택").tag("")
                                                            ForEach(state.testCaseExpectedFields, id: \.self) { field in
                                                                Text(field).tag(field)
                                                            }
                                                        }
                                                        .labelsHidden()
                                                        .frame(width: 210)
                                                        Text("이하여야 합니다.")
                                                    }
                                                    Spacer()
                                                    Button(role: .destructive) {
                                                        state.removeArrayAssertion(
                                                            from: criterion.id,
                                                            assertionID: assertion.id
                                                        )
                                                    } label: {
                                                        Image(systemName: "minus.circle")
                                                    }
                                                    .help("하위 조건 삭제")
                                                }
                                                .font(.caption)
                                            }

                                            Menu {
                                                Button("데이터셋 값 조건") {
                                                    state.addArrayAssertion(to: criterion.id, kind: .datasetValue)
                                                }
                                                Button("요소 값 범위") {
                                                    state.addArrayAssertion(to: criterion.id, kind: .objectValueRange)
                                                }
                                            } label: {
                                                Label("하위 조건 추가", systemImage: "plus")
                                            }
                                            .font(.caption)
                                        }
                                        .padding(.leading, 10)
                                    } else {
                                        HStack {
                                            if criterion.passRule == .range {
                                                Picker("최솟값 필드", selection: $criterion.expectedMinField) {
                                                    Text("선택").tag("")
                                                    ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                }
                                                Picker("최댓값 필드", selection: $criterion.expectedMaxField) {
                                                    Text("선택").tag("")
                                                    ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                }
                                            } else if criterion.passRule != .exists {
                                                Picker("기댓값 필드", selection: $criterion.expectedField) {
                                                    Text("선택").tag("")
                                                    ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                }
                                            }
                                            Picker("Output 필드", selection: $criterion.outputPath) {
                                                Text("선택").tag("")
                                                ForEach(outputPathOptions, id: \.self) { path in
                                                    Text(path).tag(path)
                                                }
                                            }
                                            .frame(maxWidth: 340)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                GroupBox("4. 5행 조건 미리보기") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button { state.runCriteriaPreview() } label: {
                                Label(
                                    state.isRunningCriteriaPreview ? "실행 중" : "5개 행 조건 미리보기 실행",
                                    systemImage: "checklist"
                                )
                            }
                            .disabled(
                                state.isRunningCriteriaPreview
                                    || state.testCaseCriteria.isEmpty
                                    || state.rows.isEmpty
                                    || state.promptText.isEmpty
                                    || state.selectedModelID.isEmpty
                            )
                            if state.isRunningCriteriaPreview {
                                ProgressView(
                                    value: Double(state.criteriaPreviewProgress),
                                    total: Double(max(min(state.rows.count, 5), 1))
                                )
                                .frame(width: 130)
                                Text("\(state.criteriaPreviewProgress)/\(min(state.rows.count, 5))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if state.criteriaPreviews.isEmpty {
                            Text("조건을 설정한 뒤 5개 행을 실행하면, 조건을 수정할 때마다 여기서 PASS/FAIL이 즉시 갱신됩니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(state.criteriaPreviews) { preview in
                                        let results = state.criterionResults(for: preview)
                                        let passed = preview.output.error == nil
                                            && !results.isEmpty
                                            && results.allSatisfy(\.passed)
                                        let rowSummary = preview.row.values.keys.sorted().map {
                                            "\($0): \(preview.row.values[$0] ?? "")"
                                        }.joined(separator: " · ")
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(rowSummary)
                                                    .font(.caption.weight(.semibold))
                                                    .lineLimit(2)
                                                Spacer()
                                                if preview.output.error != nil {
                                                    Label("실행 오류", systemImage: "exclamationmark.triangle.fill")
                                                        .foregroundStyle(.red)
                                                } else {
                                                    Label(
                                                        passed ? "PASS" : "FAIL",
                                                        systemImage: passed ? "checkmark.circle.fill" : "xmark.circle.fill"
                                                    )
                                                    .foregroundStyle(passed ? .green : .red)
                                                }
                                            }
                                            if let error = preview.output.error {
                                                Text(error)
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            } else {
                                                ForEach(results) { result in
                                                    HStack {
                                                        Label(
                                                            result.name,
                                                            systemImage: result.passed ? "checkmark.circle" : "xmark.circle"
                                                        )
                                                        .foregroundStyle(result.passed ? .green : .red)
                                                        Text("기대 \(result.expected)")
                                                        Text("결과 \(result.actual)")
                                                            .foregroundStyle(.secondary)
                                                        Spacer()
                                                    }
                                                    .font(.caption)
                                                }
                                            }
                                        }
                                        .padding(9)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            .frame(minHeight: 180, maxHeight: 360)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
    }

    private var testRunView: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 14) {
            pageHeader(title: "테스트", subtitle: "저장된 테스트 케이스를 실행하고 LLM output과 테스트 결과를 데이터셋과 별도로 보관합니다.")
            DisclosureGroup(isExpanded: $isTestExecutionExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Picker("테스트 케이스", selection: Binding(
                            get: { state.selectedTestCaseID },
                            set: { state.selectTestCase($0) }
                        )) {
                            Text("선택").tag(UUID?.none)
                            ForEach(state.savedTestCases) { testCase in
                                Text(testCase.name).tag(Optional(testCase.id))
                            }
                        }
                        .frame(maxWidth: 420)
                        if let testCase = state.selectedTestCase {
                            Label(testCase.datasetName, systemImage: "tablecells")
                            Label(testCase.modelID, systemImage: "cpu")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack {
                        SecureField("\(state.selectedTestCase?.provider ?? state.provider.rawValue) API 키", text: $state.providerAPIKey)
                        Button { pasteClipboard(into: $state.providerAPIKey) } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        Text("실행 레코드")
                        TextField("개수", value: $state.testRunLimit, format: .number)
                            .frame(width: 80)
                        Text("/ \(state.selectedTestCase.flatMap { selected in state.sourceDatasets.first { $0.id == selected.datasetID }?.rows.count } ?? 0)")
                            .foregroundStyle(.secondary)
                        Stepper("동시 실행 \(state.generationConcurrency)개", value: $state.generationConcurrency, in: 1...16)
                            .frame(width: 180)
                        Spacer()
                        if state.isTestRunning {
                            ProgressView(value: Double(state.progress), total: Double(max(state.testRunLimit, 1)))
                                .frame(width: 130)
                            Button(role: .destructive) { state.cancelTestRun() } label: {
                                Label("취소", systemImage: "stop.fill")
                            }
                        } else {
                            Button { state.startTestRun() } label: {
                                Label("테스트 실행", systemImage: "play.fill")
                            }
                            .disabled(state.selectedTestCase == nil || state.providerAPIKey.isEmpty)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("테스트 실행", systemImage: "play.rectangle")
                    .font(.headline)
            }

            Divider()
            VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("테스트 결과")
                    .font(.headline)
                Button { state.refreshTestRuns() } label: { Image(systemName: "arrow.clockwise") }
                    .help("테스트 결과 새로고침")
                Button { state.openSelectedTestRun() } label: { Image(systemName: "folder") }
                    .help("Finder에서 결과 파일 보기")
                    .disabled(state.selectedTestRun == nil)
                Button(role: .destructive) { state.deleteSelectedTestRun() } label: {
                    Label("테스트 삭제", systemImage: "trash")
                }
                .disabled(state.selectedTestRun == nil || state.isTestRunning)
                Spacer()
                Text("총 \(state.testRuns.count)개")
                    .foregroundStyle(.secondary)
            }

            if state.testRuns.isEmpty {
                ContentUnavailableView("테스트 결과가 없습니다", systemImage: "play.rectangle", description: Text("저장된 테스트 케이스를 실행하세요."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: Binding(
                        get: { state.selectedTestRunID },
                        set: { state.selectTestRun($0) }
                    )) {
                        ForEach(state.testRuns) { run in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.name).fontWeight(.medium).lineLimit(1)
                                Text(run.hasDeterministicCriteria
                                     ? "\(run.completedCount)/\(run.requestedCount) · 통과 \(run.passedCount) · \(formatLatency(run.averageLatencyMilliseconds))"
                                     : "\(run.completedCount)/\(run.requestedCount) · 정량 판정 없음 · \(formatLatency(run.averageLatencyMilliseconds))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("\(run.status.displayName) · \(run.completedAt.formatted(date: .numeric, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(run.status == .completed ? .green : .orange)
                            }
                            .tag(Optional(run.id))
                        }
                    }
                    .frame(minWidth: 270, idealWidth: 310, maxHeight: .infinity)
                    testRunDetail
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
    }

    @ViewBuilder
    private var testRunDetail: some View {
        if let run = state.selectedTestRun {
            VStack(alignment: .leading, spacing: 10) {
                Text(run.testCaseName).font(.title3.weight(.semibold))
                HStack(spacing: 16) {
                    Label(run.datasetName, systemImage: "tablecells")
                    Label(run.promptName, systemImage: "text.quote")
                    Label(run.modelID, systemImage: "cpu")
                    if run.hasDeterministicCriteria {
                        Label("통과 \(run.passedCount)/\(run.completedCount)", systemImage: "checkmark.circle")
                    } else {
                        Label("정량 판정 없음", systemImage: "minus.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                if !run.criteria.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("적용 조건")
                            .font(.headline)
                        ForEach(run.criteria) { criterion in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(testCriterionConditionHeader(criterion))
                                    .font(.caption)
                                ForEach(testCriterionConditionBullets(criterion), id: \.self) { condition in
                                    Text("• \(condition)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    Divider()
                }
                let displayedRows = filteredTestRunRows(run)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("정렬", selection: $testResultSort) {
                            ForEach(TestResultRowSort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .frame(width: 190)
                        Button { testResultSortDescending.toggle() } label: {
                            Image(systemName: testResultSortDescending ? "arrow.down" : "arrow.up")
                        }
                        .help(testResultSortDescending ? "내림차순" : "오름차순")
                        Picker("통과 여부", selection: $testResultPassFilter) {
                            ForEach(EvaluationPassFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .frame(width: 170)
                        Spacer()
                        Text("표시 \(displayedRows.count) / \(run.rows.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button { resetTestResultFilters() } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .help("필터 초기화")
                    }
                    HStack(spacing: 12) {
                        judgementRangeFilter(
                            title: "토큰",
                            minimum: $minimumTestTokenFilter,
                            maximum: $maximumTestTokenFilter
                        )
                        judgementRangeFilter(
                            title: "레이턴시(ms)",
                            minimum: $minimumTestLatencyFilter,
                            maximum: $maximumTestLatencyFilter
                        )
                    }
                }
                if displayedRows.isEmpty {
                    ContentUnavailableView("필터 조건에 맞는 테스트 결과가 없습니다", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedRows) { row in
                            let passed = testRunRowPassed(row)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Spacer()
                                    if row.error != nil {
                                        Label("실패", systemImage: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    } else if row.criterionResults.isEmpty {
                                        Label("정량 판정 없음", systemImage: "minus.circle")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Label(passed ? "통과" : "실패", systemImage: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(passed ? .green : .red)
                                    }
                                }
                                ForEach(row.criterionResults) { criterion in
                                    HStack {
                                        Text(criterion.name)
                                            .fontWeight(.medium)
                                        Text("기대값 \(criterion.expected)")
                                        Text("결과값 \(criterion.actual)")
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Image(systemName: criterion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(criterion.passed ? .green : .red)
                                    }
                                    .font(.caption)
                                }
                                if let error = row.error {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack {
                ContentUnavailableView("테스트 결과를 선택하세요", systemImage: "sidebar.left")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func testCriterionConditionHeader(_ criterion: TestCriterionDefinition) -> String {
        let condition = criterion.withDefaultArrayAssertions()
        switch condition.passRule {
        case .arrayObjectCondition:
            return "\(condition.name): 만약 \(condition.outputPath)에 \(condition.matchField ?? "선택된 필드") 값이 \(condition.matchValue ?? "선택된 값")인 요소가 있다면"
        case .range:
            return "\(condition.name): output의 \(condition.outputPath) 값은 데이터셋의 \(condition.expectedMinField) 이상 \(condition.expectedMaxField) 이하여야 합니다."
        case .contains:
            return "\(condition.name): output의 \(condition.outputPath)에는 데이터셋의 \(condition.expectedField) 값이 포함되어야 합니다."
        case .exists:
            return "\(condition.name): output에 \(condition.outputPath) 값이 있어야 합니다."
        case .exact:
            return "\(condition.name): output의 \(condition.outputPath) 값은 데이터셋의 \(condition.expectedField) 값과 같아야 합니다."
        }
    }

    private func testCriterionConditionBullets(_ criterion: TestCriterionDefinition) -> [String] {
        let condition = criterion.withDefaultArrayAssertions()
        guard condition.passRule == .arrayObjectCondition else { return [] }
        return condition.arrayAssertions.map { assertion in
            switch assertion.kind {
            case .datasetValue:
                return "데이터셋의 \(assertion.datasetField)는 값이 \(assertion.expectedValue)이어야 합니다."
            case .objectValueRange:
                return "해당 요소의 \(assertion.objectField)는 \(assertion.minimumField) 이상 \(assertion.maximumField) 이하여야 합니다."
            }
        }
    }

    private var evaluationView: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "평가", subtitle: "완료된 테스트 결과 파일을 불러와 선택한 로컬 Codex 모델로 평가합니다.")
            DisclosureGroup(isExpanded: $isEvaluationExecutionExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("테스트 결과", selection: Binding(
                        get: { state.selectedTestRunID },
                        set: { state.selectTestRun($0) }
                    )) {
                        Text("완료된 테스트 결과 선택").tag(UUID?.none)
                        ForEach(state.testRuns.filter { $0.status == .completed }) { run in
                            Text(run.name).tag(Optional(run.id))
                        }
                    }
                    .disabled(state.isEvaluating)
                    HStack {
                        Text("평가 모델")
                        Picker("평가 모델", selection: $state.codexEvaluationModel) {
                            ForEach(state.codexEvaluationModelOptions, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .disabled(state.isEvaluating)
                        TextField("모델 ID 직접 입력", text: $state.codexEvaluationModel)
                            .frame(width: 210)
                            .disabled(state.isEvaluating)
                        Spacer()
                    }
                    HStack {
                        Text("평가 행 수")
                        TextField("개수", value: $state.codexJudgeLimit, format: .number)
                            .frame(width: 80)
                            .disabled(state.isEvaluating)
                        Text("0은 output이 있는 모든 행")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper("동시 실행 \(state.codexConcurrency)개", value: $state.codexConcurrency, in: 2...8)
                            .frame(width: 180)
                            .disabled(state.isEvaluating)
                        Spacer()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("평가 프롬프트")
                                .font(.headline)
                            Spacer()
                            Button { state.recommendEvaluationPrompt() } label: {
                                Label(
                                    state.isRecommendingEvaluationPrompt ? "추천 중" : "프롬프트 추천",
                                    systemImage: "sparkles"
                                )
                            }
                            .disabled(
                                state.selectedTestRun?.status != .completed
                                    || state.isRecommendingEvaluationPrompt
                                    || state.isEvaluating
                            )
                            Button { state.resetEvaluationPrompt() } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .help("기본 평가 프롬프트로 되돌리기")
                            .disabled(state.isRecommendingEvaluationPrompt || state.isEvaluating)
                        }
                        ScrollablePromptEditor(text: $state.evaluationPrompt)
                            .frame(height: 180)
                            .disabled(state.isRecommendingEvaluationPrompt || state.isEvaluating)
                        Text("사용 변수: {{llm_input}}, {{original_prompt}}, {{dataset_values}}, {{test_criteria}}, {{model_output}}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Promptfoo API 키")
                        SecureField("pf_...", text: $state.promptfooAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .disabled(state.isEvaluating || state.isSharingEvaluation)
                        Button { pasteClipboard(into: $state.promptfooAPIKey) } label: {
                            Image(systemName: "doc.on.clipboard")
                        }
                        .help("클립보드에서 Promptfoo API 키 붙여넣기")
                        .disabled(state.isEvaluating || state.isSharingEvaluation)
                        Text("현재 앱 실행 중에만 보관")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack {
                    Button { state.generateEvaluationBundle() } label: {
                        Label("평가 준비", systemImage: "folder.badge.plus")
                    }
                    .disabled(state.selectedTestRun?.status != .completed || state.isEvaluating)
                    Button { state.runEvaluation() } label: {
                        Label(state.isEvaluating ? "평가 중" : "평가 실행", systemImage: "checkmark.seal")
                    }
                    .disabled(state.evaluationBundleURL == nil || state.isEvaluating)
                    if state.isEvaluating {
                        ProgressView(
                            value: Double(state.evaluationProgress),
                            total: Double(max(state.evaluationTotal, 1))
                        )
                        .frame(width: 150)
                        Text("\(state.evaluationProgress)/\(state.evaluationTotal)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let run = state.selectedTestRun {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow { Text("테스트 케이스").foregroundStyle(.secondary); Text(run.testCaseName) }
                        GridRow { Text("데이터셋").foregroundStyle(.secondary); Text(run.datasetName) }
                        GridRow { Text("테스트 모델").foregroundStyle(.secondary); Text(run.modelID) }
                        GridRow { Text("레코드").foregroundStyle(.secondary); Text("\(run.completedCount)개") }
                    }
                    .padding(.top, 8)
                }
            } label: {
                Label("평가 실행", systemImage: "checkmark.seal")
                    .font(.headline)
            }
            Divider()
            evaluationResultsContent
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
    }

    private var evaluationResultsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("평가 결과")
                    .font(.headline)
                Button { state.refreshEvaluationResults() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("평가 결과 새로고침")
                Button { state.openSelectedEvaluationResult() } label: {
                    Image(systemName: "folder")
                }
                .help("Finder에서 평가 결과 보기")
                .disabled(state.selectedEvaluationResult == nil)
                Menu {
                    Button("CSV") { state.exportSelectedEvaluationData(format: .csv) }
                    Button("JSON") { state.exportSelectedEvaluationData(format: .json) }
                } label: {
                    Label("평가 데이터 내보내기", systemImage: "square.and.arrow.up")
                }
                .disabled(state.selectedEvaluationResult?.hasEvaluatedDataset != true)
                Button { state.shareSelectedEvaluationResultToPromptfoo() } label: {
                    Label(
                        state.isSharingEvaluation ? "Promptfoo 전송 중" : "Promptfoo로 전송",
                        systemImage: "arrow.up.right.square"
                    )
                }
                .disabled(
                    state.selectedEvaluationResult?.isComplete != true
                        || state.promptfooAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || state.isSharingEvaluation
                )
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
                    description: Text("완료된 테스트 결과를 선택해 평가를 실행하세요.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(selection: $state.selectedEvaluationResultID) {
                        ForEach(state.evaluationResults) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.input.testCaseName ?? result.input.promptName ?? result.input.datasetName ?? "평가 실행")
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
                    .frame(minWidth: 260, idealWidth: 300, maxHeight: .infinity)

                    evaluationResultDetail
                        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, 14)
                }
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var evaluationResultDetail: some View {
        if let result = state.selectedEvaluationResult {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.input.testCaseName ?? result.input.promptName ?? "이름 없는 테스트")
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
                        let displayedJudgements = filteredJudgements(for: result)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Picker("정렬", selection: $judgementSort) {
                                    ForEach(EvaluationJudgementSort.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                .frame(width: 190)
                                Button { judgementSortDescending.toggle() } label: {
                                    Image(systemName: judgementSortDescending ? "arrow.down" : "arrow.up")
                                }
                                .help(judgementSortDescending ? "내림차순" : "오름차순")
                                Picker("통과 여부", selection: $judgementPassFilter) {
                                    ForEach(EvaluationPassFilter.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
                                .frame(width: 170)
                                Spacer()
                                Text("표시 \(displayedJudgements.count) / \(result.judgements.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button { resetJudgementFilters() } label: {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                }
                                .help("필터 초기화")
                            }
                            HStack(spacing: 12) {
                                judgementRangeFilter(
                                    title: "토큰",
                                    minimum: $minimumTokenFilter,
                                    maximum: $maximumTokenFilter
                                )
                                judgementRangeFilter(
                                    title: "레이턴시(ms)",
                                    minimum: $minimumLatencyFilter,
                                    maximum: $maximumLatencyFilter
                                )
                                judgementRangeFilter(
                                    title: "점수",
                                    minimum: $minimumScoreFilter,
                                    maximum: $maximumScoreFilter
                                )
                            }
                        }

                        if displayedJudgements.isEmpty {
                            ContentUnavailableView("필터 조건에 맞는 판정이 없습니다", systemImage: "line.3.horizontal.decrease.circle")
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(displayedJudgements) { judgement in
                                    let row = result.datasetRow(for: judgement)
                                    let title = row?.values["source_data"] ?? "데이터 행"
                                    let totalTokens = judgementTokenCount(judgement, row: row)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(title)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)
                                            Spacer()
                                            Label(formatTokens(totalTokens), systemImage: "number")
                                                .help("소모 토큰 합계")
                                            Label(formatLatency(row?.latencyMilliseconds), systemImage: "timer")
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
                                                        Label(criterion.name, systemImage: criterion.pass ? "checkmark.circle" : "xmark.circle")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(criterion.pass ? .green : .red)
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
                                            } else if result.input.criteria?.isEmpty == true {
                                                Text("정량 평가 기준 없이 원본 프롬프트와 전체 output을 평가했습니다.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Text("기대값과 결과값이 기록되지 않은 이전 평가 형식입니다.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else if let error = judgement.error {
                                            Text(error)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack {
                ContentUnavailableView("평가 결과를 선택하세요", systemImage: "sidebar.left")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func judgementRangeFilter(
        title: String,
        minimum: Binding<String>,
        maximum: Binding<String>
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("최소", text: minimum)
                .frame(width: 58)
            Text("~")
                .foregroundStyle(.secondary)
            TextField("최대", text: maximum)
                .frame(width: 58)
        }
    }

    private func filteredTestRunRows(_ run: SavedTestRun) -> [TestRunRowResult] {
        run.rows.filter { row in
            let passMatches: Bool
            switch testResultPassFilter {
            case .all:
                passMatches = true
            case .passed:
                passMatches = row.error == nil
                    && !row.criterionResults.isEmpty
                    && testRunRowPassed(row)
            case .failed:
                passMatches = row.error == nil
                    && !row.criterionResults.isEmpty
                    && !testRunRowPassed(row)
            case .error:
                passMatches = row.error != nil
            }
            return passMatches
                && matchesRange(
                    testRunTokenCount(row).map(Double.init),
                    minimum: minimumTestTokenFilter,
                    maximum: maximumTestTokenFilter
                )
                && matchesRange(
                    row.latencyMilliseconds,
                    minimum: minimumTestLatencyFilter,
                    maximum: maximumTestLatencyFilter
                )
        }
        .sorted { left, right in
            let leftValue: Double?
            let rightValue: Double?
            switch testResultSort {
            case .tokens:
                leftValue = testRunTokenCount(left).map(Double.init)
                rightValue = testRunTokenCount(right).map(Double.init)
            case .latency:
                leftValue = left.latencyMilliseconds
                rightValue = right.latencyMilliseconds
            case .pass:
                leftValue = left.error == nil && !left.criterionResults.isEmpty
                    ? (testRunRowPassed(left) ? 1 : 0)
                    : nil
                rightValue = right.error == nil && !right.criterionResults.isEmpty
                    ? (testRunRowPassed(right) ? 1 : 0)
                    : nil
            }
            return compareTestResultMetric(
                leftValue,
                rightValue,
                leftID: left.id.uuidString,
                rightID: right.id.uuidString
            )
        }
    }

    private func testRunTokenCount(_ row: TestRunRowResult) -> Int? {
        guard row.inputTokens != nil || row.outputTokens != nil else { return nil }
        return (row.inputTokens ?? 0) + (row.outputTokens ?? 0)
    }

    private func testRunRowPassed(_ row: TestRunRowResult) -> Bool {
        row.error == nil && !row.criterionResults.isEmpty && row.criterionResults.allSatisfy(\.passed)
    }

    private func compareTestResultMetric(
        _ left: Double?,
        _ right: Double?,
        leftID: String,
        rightID: String
    ) -> Bool {
        switch (left, right) {
        case let (.some(leftValue), .some(rightValue)):
            if leftValue == rightValue { return leftID < rightID }
            return testResultSortDescending ? leftValue > rightValue : leftValue < rightValue
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return leftID < rightID
        }
    }

    private func resetTestResultFilters() {
        testResultPassFilter = .all
        minimumTestTokenFilter = ""
        maximumTestTokenFilter = ""
        minimumTestLatencyFilter = ""
        maximumTestLatencyFilter = ""
    }

    private func filteredJudgements(for result: EvaluationResultRecord) -> [CodexJudgementRecord] {
        result.judgements.filter { judgement in
            let row = result.datasetRow(for: judgement)
            let passMatches: Bool
            switch judgementPassFilter {
            case .all:
                passMatches = true
            case .passed:
                passMatches = judgement.judge?.pass == true
            case .failed:
                passMatches = judgement.judge?.pass == false
            case .error:
                passMatches = judgement.judge == nil
            }
            return passMatches
                && matchesRange(
                    judgementTokenCount(judgement, row: row).map(Double.init),
                    minimum: minimumTokenFilter,
                    maximum: maximumTokenFilter
                )
                && matchesRange(
                    row?.latencyMilliseconds,
                    minimum: minimumLatencyFilter,
                    maximum: maximumLatencyFilter
                )
                && matchesRange(
                    judgement.judge.map { Double($0.score) },
                    minimum: minimumScoreFilter,
                    maximum: maximumScoreFilter
                )
        }
        .sorted { left, right in
            let leftRow = result.datasetRow(for: left)
            let rightRow = result.datasetRow(for: right)
            let leftValue: Double?
            let rightValue: Double?
            switch judgementSort {
            case .tokens:
                leftValue = judgementTokenCount(left, row: leftRow).map(Double.init)
                rightValue = judgementTokenCount(right, row: rightRow).map(Double.init)
            case .latency:
                leftValue = leftRow?.latencyMilliseconds
                rightValue = rightRow?.latencyMilliseconds
            case .score:
                leftValue = left.judge.map { Double($0.score) }
                rightValue = right.judge.map { Double($0.score) }
            }
            return compareMetric(
                leftValue,
                rightValue,
                leftID: left.rowId,
                rightID: right.rowId
            )
        }
    }

    private func judgementTokenCount(_ judgement: CodexJudgementRecord, row: DatasetRow?) -> Int? {
        if judgement.evaluationInputTokens != nil || judgement.evaluationOutputTokens != nil {
            return (judgement.evaluationInputTokens ?? 0) + (judgement.evaluationOutputTokens ?? 0)
        }
        if row?.inputTokens != nil || row?.outputTokens != nil {
            return (row?.inputTokens ?? 0) + (row?.outputTokens ?? 0)
        }
        return nil
    }

    private func matchesRange(_ value: Double?, minimum: String, maximum: String) -> Bool {
        let minimumValue = Double(minimum.trimmingCharacters(in: .whitespacesAndNewlines))
        let maximumValue = Double(maximum.trimmingCharacters(in: .whitespacesAndNewlines))
        guard minimumValue != nil || maximumValue != nil else { return true }
        guard let value else { return false }
        if let minimumValue, value < minimumValue { return false }
        if let maximumValue, value > maximumValue { return false }
        return true
    }

    private func compareMetric(
        _ left: Double?,
        _ right: Double?,
        leftID: String,
        rightID: String
    ) -> Bool {
        switch (left, right) {
        case let (.some(leftValue), .some(rightValue)):
            if leftValue == rightValue { return leftID < rightID }
            return judgementSortDescending ? leftValue > rightValue : leftValue < rightValue
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return leftID < rightID
        }
    }

    private func resetJudgementFilters() {
        judgementPassFilter = .all
        minimumTokenFilter = ""
        maximumTokenFilter = ""
        minimumLatencyFilter = ""
        maximumLatencyFilter = ""
        minimumScoreFilter = ""
        maximumScoreFilter = ""
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
                        in: 2...8
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
                Button { selectedSection = .evaluation } label: {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 160, ideal: 240, max: 360)
            TableColumn("유형") { dataset in
                Text(dataset.kind.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 60, ideal: 70, max: 90)
            TableColumn("파일 확장자") { dataset in
                Text(dataset.fileExtension.uppercased())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 90, ideal: 110, max: 130)
            TableColumn("등록일") { dataset in
                Text(dataset.createdAt.formatted(date: .numeric, time: .shortened))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 150, ideal: 180, max: 210)
            TableColumn("용량") { dataset in
                Text(ByteCountFormatter.string(fromByteCount: Int64(dataset.byteSize), countStyle: .file))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 90, ideal: 110, max: 130)
        }
    }
}

private struct DatasetPreview: View {
    let headers: [String]
    let rows: [DatasetRow]
    private let pageSize = 10
    @State private var visibleRowCount = 10

    private var visibleRows: ArraySlice<DatasetRow> {
        rows.prefix(visibleRowCount)
    }

    private var hasMoreRows: Bool {
        visibleRowCount < rows.count
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        ForEach(headers, id: \.self) { header in
                            Text(header)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            .frame(width: columnWidth(for: header), alignment: .leading)
                        }
                    }
                    .padding(.bottom, 2)

                    ForEach(visibleRows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(headers, id: \.self) { header in
                                Text(row.values[header] ?? "")
                                    .font(.caption)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                .frame(width: columnWidth(for: header), alignment: .leading)
                            }
                        }
                        .frame(minHeight: 28, alignment: .topLeading)
                    }

                    if hasMoreRows {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Text("다음 \(min(pageSize, rows.count - visibleRowCount))개 행 불러오는 중")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .onAppear(perform: loadNextPage)
                        .id(visibleRowCount)
                    }
                }
                .padding(8)
                .frame(minWidth: geometry.size.width, alignment: .topLeading)
            }
        }
        .frame(minHeight: 180, maxHeight: 320)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func columnWidth(for header: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let widest = ([header] + visibleRows.map { $0.values[header] ?? "" })
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return min(max(widest + 24, 110), 280)
    }

    private func loadNextPage() {
        guard hasMoreRows else { return }
        visibleRowCount = min(visibleRowCount + pageSize, rows.count)
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
