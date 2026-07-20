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

private enum PromptViewMode: String, CaseIterable, Identifiable {
    case editor = "원문 편집"
    case structured = "구조화 보기"

    var id: String { rawValue }
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
    @State private var testCasePromptFilter = ""
    @State private var testCaseDatasetFilter = ""
    @State private var testRunPromptFilter = ""
    @State private var testRunDatasetFilter = ""
    @State private var evaluationPromptFilter = ""
    @State private var evaluationDatasetFilter = ""
    @State private var isTestExecutionExpanded = true
    @State private var isEvaluationExecutionExpanded = true
    @State private var promptViewMode: PromptViewMode = .editor
    @State private var isPromptOutputSchemaExpanded = true
    @FocusState private var isCriterionTextFieldFocused: Bool

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
        .overlay(alignment: .topTrailing) {
            if let notification = state.notification {
                ToastView(message: notification.message) {
                    state.notification = nil
                }
                .padding(20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: state.notification?.id) { _, _ in
            dismissNotificationAfterDelay()
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
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "프롬프트")
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("등록된 프롬프트")
                            .font(.headline)
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
                            .contextMenu {
                                Button("편집") { state.selectPrompt(prompt.id) }
                                Button("복제") {
                                    state.selectPrompt(prompt.id)
                                    state.duplicateSelectedPrompt()
                                }
                                Button("내보내기") {
                                    state.selectPrompt(prompt.id)
                                    state.exportCurrentPrompt()
                                }
                                Divider()
                                Button("삭제", role: .destructive) {
                                    state.selectPrompt(prompt.id)
                                    state.deleteSelectedPrompt()
                                }
                            }
                        }
                    }
                    Button { state.choosePrompt() } label: {
                        Label("파일 가져오기", systemImage: "square.and.arrow.down")
                    }
                }
                .frame(minWidth: 230, idealWidth: 260)
                .padding(.trailing, 10)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button { state.saveCurrentPrompt() } label: {
                            Label("저장", systemImage: "square.and.arrow.down")
                        }
                        Button { state.duplicateSelectedPrompt() } label: {
                            Label("복제", systemImage: "doc.on.doc")
                        }
                        .disabled(state.selectedPromptID == nil)
                        Button { state.exportCurrentPrompt() } label: {
                            Label("내보내기", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) { state.deleteSelectedPrompt() } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        .disabled(state.selectedPromptID == nil)
                    }
                    Divider()
                    HStack {
                        LabeledInput("프롬프트 이름") {
                            TextField("", text: $state.promptName)
                                .labelsHidden()
                                .font(.title3.weight(.semibold))
                        }
                        LabeledInput("보기") {
                            Picker("", selection: $promptViewMode) {
                                ForEach(PromptViewMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    if promptViewMode == .editor {
                        ScrollablePromptEditor(text: $state.promptText)
                            .frame(minHeight: 420)
                    } else {
                        PromptStructuredView(text: state.promptText)
                            .frame(minHeight: 420)
                    }
                    DisclosureGroup(isExpanded: $isPromptOutputSchemaExpanded) {
                        if let schema = state.promptOutputSchema {
                            ScrollView {
                                Text(schema.exampleJSON)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 90, maxHeight: 180)
                        } else {
                            Text("프롬프트에서 유효한 JSON output 스키마를 찾지 못했습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label("예시 output", systemImage: "curlybraces")
                            .font(.headline)
                    }
                    Text("변수 \(state.promptVariables.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "데이터셋")
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
                Text("총 \(state.sourceDatasets.count)개")
                    .foregroundStyle(.secondary)
            }
            DatasetLibraryTable(
                datasets: state.sourceDatasets,
                selection: Binding(
                    get: { state.selectedDatasetID },
                    set: { state.selectDataset($0) }
                ),
                onExport: { dataset in
                    state.selectDataset(dataset.id)
                    state.exportDataset()
                },
                onDelete: { dataset in
                    state.selectDataset(dataset.id)
                    state.deleteSelectedDataset()
                }
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
                        }
                        if !state.rows.isEmpty {
                            DatasetPreview(headers: state.headers, rows: state.rows)
                                .id(state.selectedDatasetID)
                        } else {
                            ContentUnavailableView("데이터가 없습니다", systemImage: "tablecells")
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
            }

            DisclosureGroup("Google Sheet에서 데이터셋 등록") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        LabeledInput("스프레드시트 ID") {
                            TextField("", text: $state.spreadsheetID)
                                .labelsHidden()
                        }
                        LabeledInput("범위") {
                            TextField("", text: $state.spreadsheetRange)
                                .labelsHidden()
                        }
                    }
                    HStack {
                        LabeledInput("Google Sheets API 키") {
                            SecureField("", text: $state.googleAPIKey)
                                .labelsHidden()
                        }
                        Button("시트 불러오기") { state.loadSpreadsheet() }
                            .disabled(state.isRunning)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var testCaseView: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "테스트 케이스")
            HSplitView {
                testCaseSidebar
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button { state.saveCurrentTestCase() } label: {
                            Label("저장", systemImage: "square.and.arrow.down")
                        }
                        Button { state.duplicateSelectedTestCase() } label: {
                            Label("복제", systemImage: "doc.on.doc")
                        }
                        .disabled(state.selectedTestCaseID == nil)
                        Button(role: .destructive) { state.deleteSelectedTestCase() } label: {
                            Label("삭제", systemImage: "trash")
                        }
                        .disabled(state.selectedTestCaseID == nil)
                        Spacer()
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                WorkflowSection {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledInput("테스트 케이스 이름") {
                            TextField("", text: $state.testCaseName)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledInput("프롬프트") {
                                Picker("", selection: Binding(
                                    get: { state.selectedPromptID },
                                    set: { state.selectPrompt($0) }
                                )) {
                                    Text("선택").tag(UUID?.none)
                                    ForEach(state.savedPrompts) { prompt in
                                        Text(prompt.name).tag(Optional(prompt.id))
                                    }
                                }
                                .labelsHidden()
                            }
                            LabeledInput("데이터셋") {
                                Picker("", selection: Binding(
                                    get: { state.selectedDatasetID },
                                    set: { state.selectDataset($0) }
                                )) {
                                    Text("선택").tag(UUID?.none)
                                    ForEach(state.sourceDatasets) { dataset in
                                        Text(dataset.name).tag(Optional(dataset.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                        HStack {
                            LabeledInput("제공 서비스") {
                                Picker("", selection: $state.provider) {
                                    ForEach(ProviderKind.allCases) { provider in
                                        Text(provider.rawValue).tag(provider)
                                    }
                                }
                                .labelsHidden()
                            }
                            LabeledInput("API 키") {
                                SecureField("", text: $state.providerAPIKey)
                                    .labelsHidden()
                                    .onSubmit { state.loadModels() }
                            }
                            Button { state.loadModels() } label: {
                                Label("모델 연결", systemImage: "arrow.clockwise")
                            }
                            .disabled(state.providerAPIKey.isEmpty || state.isLoadingModels)
                        }
                        HStack {
                            LabeledInput("실행 모델") {
                                Picker("", selection: $state.selectedModelID) {
                                    Text("선택").tag("")
                                    ForEach(state.models) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .disabled(state.models.isEmpty)
                            }
                            Label("변수 \(state.promptVariables.count)개", systemImage: "curlybraces")
                            Label("기댓값 필드 \(state.testCaseExpectedFields.count)개", systemImage: "target")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                WorkflowSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("결과에 표시할 값")
                                .font(.headline)
                            Button("선택 해제") {
                                state.testCaseDisplayDatasetFields = []
                                state.testCaseDisplayOutputPaths = []
                            }
                            .disabled(
                                state.testCaseDisplayDatasetFields.isEmpty
                                    && state.testCaseDisplayOutputPaths.isEmpty
                            )
                        }
                        HStack(alignment: .top, spacing: 18) {
                            datasetPreviewFieldSelection(
                                headers: state.headers,
                                rows: Array(state.rows.prefix(5)),
                                selection: $state.testCaseDisplayDatasetFields,
                            )
                            Divider()
                                .frame(height: 150)
                            outputExampleFieldSelection(
                                schema: state.promptOutputSchema,
                                selection: $state.testCaseDisplayOutputPaths
                            )
                        }
                        resultDisplaySelectionChips(
                            datasetFields: state.testCaseDisplayDatasetFields,
                            outputPaths: state.testCaseDisplayOutputPaths
                        )
                    }
                }

                WorkflowSection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            LabeledInput("추천 모델") {
                                Picker("", selection: $state.codexEvaluationModel) {
                                    ForEach(state.codexEvaluationModelOptions, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .labelsHidden()
                            }
                            Button { state.recommendCriteriaWithCodex() } label: {
                                Label(state.isRecommendingCriteria ? "추천 중" : "AI로 다시 추천", systemImage: "wand.and.stars")
                            }
                            .disabled(state.promptOutputSchema == nil || state.isRecommendingCriteria)
                        }

                        if !state.testCaseCriteria.isEmpty {
                            ForEach($state.testCaseCriteria) { $criterion in
                                let outputPathOptions = Array(Set(state.promptOutputSchemaPaths + [criterion.outputPath]))
                                    .filter { !$0.isEmpty }
                                    .sorted()
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        LabeledInput("조건 이름") {
                                            TextField("", text: $criterion.name)
                                                .labelsHidden()
                                                .focused($isCriterionTextFieldFocused)
                                        }
                                        LabeledInput("값 타입") {
                                            Picker("", selection: $criterion.valueType) {
                                                ForEach(CriterionValueType.allCases) { type in
                                                    Text(type.rawValue).tag(type)
                                                }
                                            }
                                            .labelsHidden()
                                            .onChange(of: criterion.valueType) { _, type in
                                                if type == .number,
                                                   !criterion.expectedMinField.isEmpty,
                                                   !criterion.expectedMaxField.isEmpty {
                                                    criterion.passRule = .range
                                                } else if type == .arrayObject || criterion.passRule == .range {
                                                    criterion.passRule = .exact
                                                }
                                            }
                                        }
                                        if criterion.valueType != .arrayObject {
                                            LabeledInput("PASS 규칙") {
                                                Picker("", selection: $criterion.passRule) {
                                                    ForEach(PassRuleType.allCases) { rule in
                                                        Text(rule.rawValue).tag(rule)
                                                    }
                                                }
                                                .labelsHidden()
                                            }
                                        }
                                        Button(role: .destructive) { state.removeTestCriterion(id: criterion.id) } label: {
                                            Image(systemName: "trash")
                                        }
                                        .help("평가 기준 삭제")
                                    }
                                    if criterion.valueType == .arrayObject {
                                        HStack(spacing: 6) {
                                            LabeledInput("배열") {
                                                Picker("", selection: $criterion.outputPath) {
                                                    Text("선택").tag("")
                                                    ForEach(outputPathOptions, id: \.self) { path in
                                                        Text(path).tag(path)
                                                    }
                                                }
                                                .labelsHidden()
                                            }
                                            Text("의 요소를 검사합니다.")
                                        }

                                        if criterion.arrayAssertions.contains(where: {
                                            $0.kind == .datasetValue || $0.kind == .objectValueRange
                                        }) {
                                            HStack(spacing: 6) {
                                                Text("대상 요소는")
                                                TextField("키", text: Binding(
                                                    get: { criterion.matchField ?? "" },
                                                    set: { criterion.matchField = $0 }
                                                ))
                                                .focused($isCriterionTextFieldFocused)
                                                Text("값이")
                                                TextField("값", text: Binding(
                                                    get: { criterion.matchValue ?? "" },
                                                    set: { criterion.matchValue = $0 }
                                                ))
                                                .focused($isCriterionTextFieldFocused)
                                                Text("인 요소입니다.")
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach($criterion.arrayAssertions) { $assertion in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: 10) {
                                                        LabeledInput("조건 이름") {
                                                            TextField("", text: $assertion.name)
                                                                .labelsHidden()
                                                                .focused($isCriterionTextFieldFocused)
                                                        }
                                                        Toggle("빈 배열이면 통과", isOn: $assertion.allowEmptyArray)
                                                            .toggleStyle(.checkbox)
                                                    }
                                                    HStack(spacing: 6) {
                                                        Text("조건")
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
                                                            Text("는 값이")
                                                            Picker("값", selection: $assertion.expectedValue) {
                                                                Text("1").tag("1")
                                                                Text("0").tag("0")
                                                            }
                                                            .labelsHidden()
                                                            Text("이어야 합니다.")
                                                        case .objectValueRange:
                                                            Text("해당 요소의")
                                                            TextField("필드", text: $assertion.objectField)
                                                            .focused($isCriterionTextFieldFocused)
                                                            Text("는")
                                                            Picker("최솟값 필드", selection: $assertion.minimumField) {
                                                                Text("선택").tag("")
                                                                ForEach(state.testCaseExpectedFields, id: \.self) { field in
                                                                    Text(field).tag(field)
                                                                }
                                                            }
                                                            .labelsHidden()
                                                            Text("이상")
                                                            Picker("최댓값 필드", selection: $assertion.maximumField) {
                                                                Text("선택").tag("")
                                                                ForEach(state.testCaseExpectedFields, id: \.self) { field in
                                                                    Text(field).tag(field)
                                                                }
                                                            }
                                                            .labelsHidden()
                                                            Text("이하여야 합니다.")
                                                        case .objectValueAllowedValues:
                                                            Text("배열의")
                                                            TextField("필드", text: $assertion.objectField)
                                                            .focused($isCriterionTextFieldFocused)
                                                            Text("값은")
                                                            TextField("허용 값", text: $assertion.expectedValue)
                                                                .focused($isCriterionTextFieldFocused)
                                                            Text("중 하나여야 합니다.")
                                                        case .arrayValueRequired:
                                                            Text("배열의")
                                                            TextField("필드", text: $assertion.objectField)
                                                            .focused($isCriterionTextFieldFocused)
                                                            Text("값에")
                                                            TextField("필수 값", text: $assertion.expectedValue)
                                                                .focused($isCriterionTextFieldFocused)
                                                            Text("이 하나 이상 있어야 합니다.")
                                                        case .arrayValueForbidden:
                                                            Text("배열의")
                                                            TextField("필드", text: $assertion.objectField)
                                                            .focused($isCriterionTextFieldFocused)
                                                            Text("값에")
                                                            TextField("금지 값", text: $assertion.expectedValue)
                                                                .focused($isCriterionTextFieldFocused)
                                                            Text("이 포함되면 안 됩니다.")
                                                        }
                                                Button(role: .destructive) {
                                                            state.removeArrayAssertion(
                                                                from: criterion.id,
                                                                assertionID: assertion.id
                                                            )
                                                        } label: {
                                                            Image(systemName: "minus.circle")
                                                        }
                                                        .help("조건 삭제")
                                                    }
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
                                                Button("배열 값 허용 목록") {
                                                    state.addArrayAssertion(to: criterion.id, kind: .objectValueAllowedValues)
                                                }
                                                Button("배열 필수 값") {
                                                    state.addArrayAssertion(to: criterion.id, kind: .arrayValueRequired)
                                                }
                                                Button("배열 값 제외") {
                                                    state.addArrayAssertion(to: criterion.id, kind: .arrayValueForbidden)
                                                }
                                            } label: {
                                                Label("조건 추가", systemImage: "plus")
                                            }
                                            .font(.caption)
                                        }
                                        .padding(.leading, 20)
                                        .overlay(alignment: .leading) {
                                            Rectangle()
                                                .fill(.quaternary)
                                                .frame(width: 1)
                                                .padding(.vertical, 2)
                                        }
                                    } else {
                                        HStack {
                                            if criterion.passRule == .range {
                                                LabeledInput("최솟값") {
                                                    Picker("", selection: $criterion.expectedMinField) {
                                                        Text("선택").tag("")
                                                        ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                    }
                                                    .labelsHidden()
                                                }
                                                LabeledInput("최댓값") {
                                                    Picker("", selection: $criterion.expectedMaxField) {
                                                        Text("선택").tag("")
                                                        ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                    }
                                                    .labelsHidden()
                                                }
                                            } else if criterion.passRule != .exists {
                                                LabeledInput("기댓값") {
                                                    Picker("", selection: $criterion.expectedField) {
                                                        Text("선택").tag("")
                                                        ForEach(state.testCaseExpectedFields, id: \.self) { Text($0).tag($0) }
                                                    }
                                                    .labelsHidden()
                                                }
                                            }
                                            LabeledInput("Output") {
                                                Picker("", selection: $criterion.outputPath) {
                                                    Text("선택").tag("")
                                                    ForEach(outputPathOptions, id: \.self) { path in
                                                        Text(path).tag(path)
                                                    }
                                                }
                                                .labelsHidden()
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                        Button { state.addTestCriterion() } label: {
                            Image(systemName: "plus")
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .help("기준 추가")
                    }
                }

                WorkflowSection {
                    VStack(alignment: .leading, spacing: 12) {
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
                        }

                        if state.criteriaPreviews.isEmpty {
                            Text("미리보기 결과가 없습니다.")
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(state.criteriaPreviews) { preview in
                                        let results = state.criterionResults(for: preview)
                                        TestResultRowView(
                                            criterionResults: results,
                                            datasetValues: previewDisplayDatasetValues(preview.row),
                                            outputValues: previewDisplayOutputValues(preview.output),
                                            error: preview.output.error
                                        )
                                        .padding(9)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            .frame(minHeight: 180, maxHeight: 360)
                        }
                    }
                }
                    }
                    .padding(.leading, 12)
                }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        .padding(24)
        .onChange(of: state.testCaseCriteria) { _, _ in
            guard !isCriterionTextFieldFocused else { return }
            state.commitCriteriaPreviewCriteria()
        }
        .onChange(of: isCriterionTextFieldFocused) { _, isFocused in
            guard !isFocused else { return }
            state.commitCriteriaPreviewCriteria()
        }
    }

    private var filteredTestCases: [SavedTestCase] {
        state.savedTestCases.filter { testCase in
            (testCasePromptFilter.isEmpty || testCase.promptName == testCasePromptFilter)
                && (testCaseDatasetFilter.isEmpty || testCase.datasetName == testCaseDatasetFilter)
        }
    }

    private var filteredTestRuns: [SavedTestRun] {
        state.testRuns.filter { run in
            (testRunPromptFilter.isEmpty || run.promptName == testRunPromptFilter)
                && (testRunDatasetFilter.isEmpty || run.datasetName == testRunDatasetFilter)
        }
    }

    private var filteredEvaluationResults: [EvaluationResultRecord] {
        state.evaluationResults.filter { result in
            let promptName = result.input.promptName ?? ""
            let datasetName = result.input.sourceDatasetName ?? result.input.datasetName ?? ""
            return (evaluationPromptFilter.isEmpty || promptName == evaluationPromptFilter)
                && (evaluationDatasetFilter.isEmpty || datasetName == evaluationDatasetFilter)
        }
    }

    private func promptDatasetFilters(
        prompts: [String],
        datasets: [String],
        promptSelection: Binding<String>,
        datasetSelection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledInput("프롬프트") {
                Picker("", selection: promptSelection) {
                    Text("전체").tag("")
                    ForEach(uniqueSortedNames(prompts), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            LabeledInput("데이터셋") {
                Picker("", selection: datasetSelection) {
                    Text("전체").tag("")
                    ForEach(uniqueSortedNames(datasets), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func uniqueSortedNames(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func displayFieldSelection(
        title: String,
        fields: [String],
        selection: Binding<[String]>,
        emptyMessage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if fields.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(fields.sorted(), id: \.self) { field in
                            Toggle(field, isOn: Binding(
                                get: { selection.wrappedValue.contains(field) },
                                set: { isSelected in
                                    var selectedFields = selection.wrappedValue
                                    if isSelected {
                                        if !selectedFields.contains(field) {
                                            selectedFields.append(field)
                                        }
                                    } else {
                                        selectedFields.removeAll { $0 == field }
                                    }
                                    selection.wrappedValue = selectedFields
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    }
                }
                .frame(minWidth: 240, maxWidth: .infinity, minHeight: 90, maxHeight: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outputExampleFieldSelection(
        schema: PromptOutputSchema?,
        selection: Binding<[String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("아웃풋 미리보기")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let schema {
                OutputExampleFieldPicker(schema: schema, selection: selection)
            } else {
                Text("output 스키마가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func datasetPreviewFieldSelection(
        headers: [String],
        rows: [DatasetRow],
        selection: Binding<[String]>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("데이터셋 미리보기")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if headers.isEmpty || rows.isEmpty {
                Text("데이터셋을 선택하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            } else {
                DatasetPreviewFieldPicker(headers: headers, rows: rows, selection: selection)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func resultDisplaySelectionChips(
        datasetFields: [String],
        outputPaths: [String]
    ) -> some View {
        if !datasetFields.isEmpty || !outputPaths.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(datasetFields.sorted(), id: \.self) { field in
                    Button {
                        state.testCaseDisplayDatasetFields.removeAll { $0 == field }
                    } label: {
                        Label(field, systemImage: "tablecells")
                    }
                    .buttonStyle(.borderless)
                }
                ForEach(outputPaths.sorted(), id: \.self) { path in
                    Button {
                        state.testCaseDisplayOutputPaths.removeAll { $0 == path }
                    } label: {
                        Label(path, systemImage: "curlybraces")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.caption)
        }
    }

    private var testCaseSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("저장된 테스트 케이스")
                    .font(.headline)
                Button { state.newTestCase() } label: {
                    Image(systemName: "plus")
                }
                .help("새 테스트 케이스")
            }
            promptDatasetFilters(
                prompts: state.savedTestCases.map(\.promptName),
                datasets: state.savedTestCases.map(\.datasetName),
                promptSelection: $testCasePromptFilter,
                datasetSelection: $testCaseDatasetFilter
            )
            List(selection: Binding(
                get: { state.selectedTestCaseID },
                set: { state.selectTestCase($0) }
            )) {
                ForEach(filteredTestCases) { testCase in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(testCase.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Label(testCase.promptName, systemImage: "text.quote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(testCase.datasetName, systemImage: "tablecells")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Label(testCase.modelID, systemImage: "cpu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(testCase.id))
                    .contextMenu {
                        Button("편집") { state.selectTestCase(testCase.id) }
                        Button("복제") {
                            state.selectTestCase(testCase.id)
                            state.duplicateSelectedTestCase()
                        }
                        Button("저장") {
                            state.selectTestCase(testCase.id)
                            state.saveCurrentTestCase()
                        }
                        Divider()
                        Button("삭제", role: .destructive) {
                            state.selectTestCase(testCase.id)
                            state.deleteSelectedTestCase()
                        }
                    }
                }
            }
        }
        .padding(.trailing, 10)
    }

    private var testRunView: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "테스트")
            CollapsibleSection(title: "테스트 실행", systemImage: "play.rectangle", isExpanded: $isTestExecutionExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                        LabeledInput("테스트 케이스") {
                            Picker("", selection: Binding(
                                get: { state.selectedTestCaseID },
                                set: { state.selectTestCase($0) }
                            )) {
                                Text("선택").tag(UUID?.none)
                                ForEach(state.savedTestCases) { testCase in
                                    Text(testCase.name).tag(Optional(testCase.id))
                                }
                            }
                            .labelsHidden()
                        }
                        if let testCase = state.selectedTestCase {
                            Label(testCase.datasetName, systemImage: "tablecells")
                            Label(testCase.modelID, systemImage: "cpu")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        LabeledInput("API 키") {
                            SecureField("", text: $state.providerAPIKey)
                                .labelsHidden()
                                .onSubmit { state.loadModels() }
                        }
                    }
                    HStack(spacing: 12) {
                        LabeledInput("실행 레코드") {
                            TextField("", value: $state.testRunLimit, format: .number)
                                .labelsHidden()
                        }
                        Text("/ \(state.selectedTestCase.flatMap { selected in state.sourceDatasets.first { $0.id == selected.datasetID }?.rows.count } ?? 0)")
                            .foregroundStyle(.secondary)
                        Stepper("동시 실행 \(state.generationConcurrency)개", value: $state.generationConcurrency, in: 1...16)
                        if state.isTestRunning {
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
            }

            Divider()
            VStack(alignment: .leading, spacing: 16) {
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
                Text("총 \(state.testRuns.count)개")
                    .foregroundStyle(.secondary)
            }

            if state.testRuns.isEmpty && state.activeTestRun == nil {
                ContentUnavailableView("테스트 결과가 없습니다", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 8) {
                        promptDatasetFilters(
                            prompts: state.testRuns.map(\.promptName),
                            datasets: state.testRuns.map(\.datasetName),
                            promptSelection: $testRunPromptFilter,
                            datasetSelection: $testRunDatasetFilter
                        )
                        List(selection: Binding(
                            get: { state.selectedTestRunID },
                            set: { state.selectTestRun($0) }
                        )) {
                            if let activeRun = state.activeTestRun {
                                RunningProgressRow(
                                    name: activeRun.name,
                                    detail: activeRun.detail,
                                    progress: state.progress,
                                    total: activeRun.total,
                                    systemImage: "play.fill"
                                )
                                .listRowBackground(Color.accentColor.opacity(0.08))
                                .allowsHitTesting(false)
                            }
                            ForEach(filteredTestRuns) { run in
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
                                .contextMenu {
                                    Button("Finder에서 보기") {
                                        state.selectTestRun(run.id)
                                        state.openSelectedTestRun()
                                    }
                                    Divider()
                                    Button("삭제", role: .destructive) {
                                        state.selectTestRun(run.id)
                                        state.deleteSelectedTestRun()
                                    }
                                }
                            }
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
                        Button { testResultSortDescending.toggle() } label: {
                            Image(systemName: testResultSortDescending ? "arrow.down" : "arrow.up")
                        }
                        .help(testResultSortDescending ? "내림차순" : "오름차순")
                        Picker("통과 여부", selection: $testResultPassFilter) {
                            ForEach(EvaluationPassFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
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
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(displayedRows) { row in
                            TestResultRowView(
                                criterionResults: row.criterionResults,
                                datasetValues: selectedDisplayValues(
                                    row.displayDatasetValues,
                                    allowedKeys: run.displayDatasetFields
                                ),
                                outputValues: selectedDisplayValues(
                                    row.displayOutputValues,
                                    allowedKeys: run.displayOutputPaths
                                ),
                                error: row.error,
                                retryAction: row.error.map { _ in
                                    { state.retryTestRunRow(row, in: run) }
                                },
                                isRetryDisabled: state.isTestRunning
                            )
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func selectedDisplayValues(
        _ values: [String: String]?,
        allowedKeys: [String]?
    ) -> [String: String] {
        guard let values, let allowedKeys else { return [:] }
        return values.filter { allowedKeys.contains($0.key) }
    }

    private func previewDisplayDatasetValues(_ row: DatasetRow) -> [String: String] {
        Dictionary(uniqueKeysWithValues: state.testCaseDisplayDatasetFields.map { field in
            (field, row.values[field] ?? "")
        })
    }

    private func previewDisplayOutputValues(_ output: LLMOutputRecord) -> [String: String] {
        Dictionary(uniqueKeysWithValues: state.testCaseDisplayOutputPaths.map { path in
            (path, JSONValueExtractor.value(at: path, in: output.output ?? "") ?? "")
        })
    }

    private func selectedDatasetDisplayValues(
        for row: DatasetRow?,
        input: EvaluationInput
    ) -> [String: String] {
        guard let row else { return [:] }
        return Dictionary(uniqueKeysWithValues: (input.displayDatasetFields ?? []).map { field in
            (field, row.values[field] ?? "")
        })
    }

    private func selectedOutputDisplayValues(
        for row: DatasetRow?,
        input: EvaluationInput
    ) -> [String: String] {
        guard let row else { return [:] }
        return Dictionary(uniqueKeysWithValues: (input.displayOutputPaths ?? []).map { path in
            (path, row.values["display.output.\(path)"] ?? "")
        })
    }

    private func testCriterionConditionHeader(_ criterion: TestCriterionDefinition) -> String {
        let condition = criterion.withDefaultArrayAssertions()
        if condition.valueType == .arrayObject {
            if let matchField = condition.matchField?.trimmingCharacters(in: .whitespacesAndNewlines),
               !matchField.isEmpty,
               let matchValue = condition.matchValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !matchValue.isEmpty {
                return "\(condition.name): 배열 \(condition.outputPath)에서 \(matchField)의 값이 \(matchValue)인 요소를 검사합니다."
            }
            return "\(condition.name): 배열 \(condition.outputPath)의 요소를 검사합니다."
        }
        switch condition.passRule {
        case .arrayObjectCondition:
            return "\(condition.name): 배열 객체 조건"
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
        guard condition.valueType == .arrayObject else { return [] }
        return condition.arrayAssertions.map { assertion in
            let detail: String
            switch assertion.kind {
            case .datasetValue:
                detail = "데이터셋의 \(assertion.datasetField)는 값이 \(assertion.expectedValue)이어야 합니다."
            case .objectValueRange:
                detail = "해당 요소의 \(assertion.objectField)는 \(assertion.minimumField) 이상 \(assertion.maximumField) 이하여야 합니다."
            case .objectValueAllowedValues:
                detail = "배열의 \(assertion.objectField) 값은 \(assertion.expectedValue) 중 하나여야 합니다."
            case .arrayValueRequired:
                detail = "배열의 \(assertion.objectField) 값에 \(assertion.expectedValue)가 하나 이상 있어야 합니다."
            case .arrayValueForbidden:
                detail = "배열의 \(assertion.objectField) 값에 \(assertion.expectedValue)가 포함되면 안 됩니다."
            }
            let emptyArrayBehavior = assertion.allowEmptyArray ? " 빈 배열이면 통과합니다." : ""
            return "\(assertion.name): \(detail)\(emptyArrayBehavior)"
        }
    }

    private var evaluationView: some View {
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 16) {
            pageHeader(title: "평가")
            CollapsibleSection(title: "평가 실행", systemImage: "checkmark.seal", isExpanded: $isEvaluationExecutionExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledInput("테스트 결과") {
                        Picker("", selection: Binding(
                            get: { state.selectedTestRunID },
                            set: { state.selectTestRun($0) }
                        )) {
                            Text("선택").tag(UUID?.none)
                            ForEach(state.testRuns.filter { $0.status == .completed }) { run in
                                Text(run.name).tag(Optional(run.id))
                            }
                        }
                        .labelsHidden()
                        .disabled(state.isEvaluating)
                    }
                    HStack {
                        LabeledInput("평가 모델") {
                            Picker("", selection: $state.codexEvaluationModel) {
                                ForEach(state.codexEvaluationModelOptions, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .disabled(state.isEvaluating)
                        }
                    }
                    HStack(spacing: 12) {
                        LabeledInput("평가 행 수") {
                            TextField("", value: $state.codexJudgeLimit, format: .number)
                                .labelsHidden()
                        }
                            .disabled(state.isEvaluating)
                        Stepper("동시 실행 \(state.codexConcurrency)개", value: $state.codexConcurrency, in: 2...8)
                            .disabled(state.isEvaluating)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("평가 프롬프트")
                                .font(.headline)
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
                    }
                    Divider()
                    HStack {
                        LabeledInput("Promptfoo API 키") {
                            SecureField("", text: $state.promptfooAPIKey)
                                .labelsHidden()
                        }
                            .textFieldStyle(.roundedBorder)
                            .disabled(state.isEvaluating || state.isSharingEvaluation)
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
                }
                if let run = state.selectedTestRun {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                        GridRow { Text("테스트 케이스").foregroundStyle(.secondary); Text(run.testCaseName) }
                        GridRow { Text("데이터셋").foregroundStyle(.secondary); Text(run.datasetName) }
                        GridRow { Text("테스트 모델").foregroundStyle(.secondary); Text(run.modelID) }
                        GridRow { Text("레코드").foregroundStyle(.secondary); Text("\(run.completedCount)개") }
                    }
            }
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
                Text("총 \(state.evaluationResults.count)개")
                    .foregroundStyle(.secondary)
            }

            if state.evaluationResults.isEmpty && state.activeEvaluationRun == nil {
                ContentUnavailableView("평가 결과가 없습니다", systemImage: "chart.bar.doc.horizontal")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    VStack(alignment: .leading, spacing: 8) {
                        promptDatasetFilters(
                            prompts: state.evaluationResults.compactMap { $0.input.promptName },
                            datasets: state.evaluationResults.compactMap { $0.input.sourceDatasetName ?? $0.input.datasetName },
                            promptSelection: $evaluationPromptFilter,
                            datasetSelection: $evaluationDatasetFilter
                        )
                        List(selection: $state.selectedEvaluationResultID) {
                            if let activeRun = state.activeEvaluationRun {
                                RunningProgressRow(
                                    name: activeRun.name,
                                    detail: activeRun.detail,
                                    progress: state.evaluationProgress,
                                    total: activeRun.total,
                                    systemImage: "checkmark.seal"
                                )
                                .listRowBackground(Color.accentColor.opacity(0.08))
                                .allowsHitTesting(false)
                            }
                            ForEach(filteredEvaluationResults) { result in
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
                                    Image(systemName: result.integrity.systemImage)
                                        .help(result.integrity.label)
                                }
                                .font(.caption2)
                                .foregroundStyle(result.integrity == .invalid ? Color.red : (result.isComplete ? Color.green : Color.secondary))
                            }
                            .tag(Optional(result.id))
                            .contextMenu {
                                Button("Finder에서 보기") {
                                    state.selectedEvaluationResultID = result.id
                                    state.openSelectedEvaluationResult()
                                }
                                Menu("내보내기") {
                                    Button("CSV") {
                                        state.selectedEvaluationResultID = result.id
                                        state.exportSelectedEvaluationData(format: .csv)
                                    }
                                    Button("JSON") {
                                        state.selectedEvaluationResultID = result.id
                                        state.exportSelectedEvaluationData(format: .json)
                                    }
                                }
                                Divider()
                                Button("삭제", role: .destructive) {
                                    state.selectedEvaluationResultID = result.id
                                    state.deleteSelectedEvaluationResult()
                                }
                            }
                            }
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
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.input.testCaseName ?? result.input.promptName ?? "이름 없는 테스트")
                            .font(.title3.weight(.semibold))
                        Text(result.input.sourceDatasetName ?? result.input.datasetName ?? "데이터셋 정보 없음")
                            .foregroundStyle(.secondary)
                    }
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
                                Button { judgementSortDescending.toggle() } label: {
                                    Image(systemName: judgementSortDescending ? "arrow.down" : "arrow.up")
                                }
                                .help(judgementSortDescending ? "내림차순" : "오름차순")
                                Picker("통과 여부", selection: $judgementPassFilter) {
                                    ForEach(EvaluationPassFilter.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                }
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
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(displayedJudgements) { judgement in
                                    let row = result.datasetRow(for: judgement)
                                    let title = row?.values["source_data"] ?? "데이터 행"
                                    let totalTokens = judgementTokenCount(judgement, row: row)
                                    let datasetValues = selectedDatasetDisplayValues(for: row, input: result.input)
                                    let outputValues = selectedOutputDisplayValues(for: row, input: result.input)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(title)
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(2)
                                            Label(formatTokens(totalTokens), systemImage: "number")
                                                .help("소모 토큰 합계")
                                            Label(formatLatency(row?.latencyMilliseconds), systemImage: "timer")
                                            if let judge = judgement.judge {
                                                Label("\(judge.score)점", systemImage: judge.pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                    .foregroundStyle(judge.pass ? .green : .red)
                                            } else {
                                                Label("오류", systemImage: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(.red)
                                                Button { state.retryEvaluationJudgement(judgement, in: result) } label: {
                                                    Image(systemName: "arrow.clockwise")
                                                }
                                                .help("오류 행 다시 평가")
                                                .disabled(state.isEvaluating)
                                            }
                                        }
                                        SelectedResultValues(
                                            datasetValues: datasetValues,
                                            outputValues: outputValues
                                        )
                                        if let judge = judgement.judge {
                                            if !judge.reasons.isEmpty {
                                                CopyableDetailText(judge.reasons.joined(separator: "\n"), font: .caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let criteria = judge.criteria, !criteria.isEmpty {
                                                Divider()
                                                ForEach(criteria) { criterion in
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Label(criterion.name, systemImage: criterion.pass ? "checkmark.circle" : "xmark.circle")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundStyle(criterion.pass ? .green : .red)
                                                        CopyableDetailText(
                                                            "기대: \(criterion.expected)\n결과: \(criterion.observed)",
                                                            font: .caption2
                                                        )
                                                        CopyableDetailText(criterion.reason, font: .caption)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.vertical, 3)
                                                }
                                            }
                                        } else if let error = judgement.error {
                                            CopyableDetailText(error, font: .caption.monospaced())
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
                ContentUnavailableView("평가가 완료되지 않았습니다", systemImage: "clock.badge.exclamationmark")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text("~")
                .foregroundStyle(.secondary)
            TextField("최대", text: maximum)
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
        HStack {
            Text("프롬프트 비교 작업 공간")
                .font(.title2.weight(.semibold))
            Spacer()
            if state.isRunning || state.isEvaluating || state.isLoadingModels {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private func pageHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title2.weight(.semibold))
            Spacer()
        }
    }

    private func dismissNotificationAfterDelay() {
        guard let notification = state.notification else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard state.notification?.id == notification.id else { return }
            withAnimation { state.notification = nil }
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
                        .onSubmit { state.loadModels() }
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
            }
            .padding(.top, 6)
        }
    }

}

private struct TestRunCriterionGroup: Identifiable {
    let id: UUID
    let name: String
    let isHierarchical: Bool
    var results: [CriterionRunResult]
}

private struct TestResultRowView: View {
    let criterionResults: [CriterionRunResult]
    let datasetValues: [String: String]
    let outputValues: [String: String]
    let error: String?
    let retryAction: (() -> Void)?
    let isRetryDisabled: Bool

    init(
        criterionResults: [CriterionRunResult],
        datasetValues: [String: String],
        outputValues: [String: String],
        error: String?,
        retryAction: (() -> Void)? = nil,
        isRetryDisabled: Bool = false
    ) {
        self.criterionResults = criterionResults
        self.datasetValues = datasetValues
        self.outputValues = outputValues
        self.error = error
        self.retryAction = retryAction
        self.isRetryDisabled = isRetryDisabled
    }

    private var passed: Bool {
        !criterionResults.isEmpty && criterionResults.allSatisfy(\.passed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                if error != nil {
                    Label("실패", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    if let retryAction {
                        Button(action: retryAction) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("오류 행 다시 실행")
                        .disabled(isRetryDisabled)
                    }
                } else if criterionResults.isEmpty {
                    Label("정량 판정 없음", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Label(passed ? "통과" : "실패", systemImage: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(passed ? .green : .red)
                }
            }
            SelectedResultValues(datasetValues: datasetValues, outputValues: outputValues)
            ForEach(groupedCriteria) { group in
                if group.isHierarchical {
                    Text(group.name)
                        .font(.caption.weight(.semibold))
                    ForEach(group.results) { criterion in
                        CriterionResultLine(criterion: criterion)
                            .padding(.leading, 24)
                    }
                } else if let criterion = group.results.first {
                    CriterionResultLine(criterion: criterion)
                }
            }
            if let error {
                CopyableDetailText(error, font: .caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var groupedCriteria: [TestRunCriterionGroup] {
        var groups: [TestRunCriterionGroup] = []
        var indices: [UUID: Int] = [:]

        for result in criterionResults {
            let groupID = result.parentCriterionID ?? result.criterionID
            if let index = indices[groupID] {
                groups[index].results.append(result)
            } else {
                indices[groupID] = groups.count
                groups.append(TestRunCriterionGroup(
                    id: groupID,
                    name: result.parentCriterionName ?? result.name,
                    isHierarchical: result.parentCriterionName != nil,
                    results: [result]
                ))
            }
        }
        return groups
    }
}

private struct CriterionResultLine: View {
    let criterion: CriterionRunResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(criterion.name)
                    .font(.caption.weight(.medium))
                Spacer()
                Image(systemName: criterion.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(criterion.passed ? .green : .red)
            }
            resultValue(label: "기대값", value: criterion.expected)
            resultValue(label: "결과값", value: criterion.actual)
        }
    }

    private func resultValue(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            CopyableDetailText(value, font: .caption)
        }
    }
}

private struct SelectedResultValues: View {
    let datasetValues: [String: String]
    let outputValues: [String: String]

    private var arrayOutputGroups: [ArrayOutputDisplayGroup] {
        var groupedValues: [String: [String: String]] = [:]

        for (path, value) in outputValues {
            guard let marker = path.range(of: "[]") else { continue }
            let arrayPath = String(path[..<marker.lowerBound])
            let fieldPath = String(path[marker.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !arrayPath.isEmpty, !fieldPath.isEmpty else { continue }
            groupedValues[arrayPath, default: [:]][fieldPath] = value
        }

        return groupedValues.keys.sorted().compactMap { arrayPath in
            guard let fields = groupedValues[arrayPath] else { return nil }
            let valuesByField = fields.mapValues(jsonArray)
            let count = valuesByField.values.map(\.count).max() ?? 0
            guard count > 0 else { return nil }

            let elements = (0..<count).map { index in
                Dictionary(uniqueKeysWithValues: fields.keys.sorted().map { field in
                    let value = valuesByField[field]?[safe: index] ?? ""
                    return (field, jsonDisplayValue(value))
                })
            }
            return ArrayOutputDisplayGroup(path: arrayPath, elements: elements)
        }
    }

    private var scalarOutputValues: [String: String] {
        outputValues.filter { !$0.key.contains("[]") }
    }

    var body: some View {
        if !datasetValues.isEmpty || !outputValues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !datasetValues.isEmpty {
                    valueGroup(title: "데이터셋 값", values: datasetValues)
                }
                if !outputValues.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("output 값")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if !scalarOutputValues.isEmpty {
                            valueGroup(values: scalarOutputValues)
                        }
                        ForEach(arrayOutputGroups) { group in
                            arrayOutputGroup(group)
                        }
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func valueGroup(title: String? = nil, values: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(values.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 2) {
                    Text(key)
                        .font(.caption.weight(.medium))
                    CopyableDetailText(values[key] ?? "", font: .caption)
                        .padding(.leading, 8)
                }
            }
        }
    }

    private func arrayOutputGroup(_ group: ArrayOutputDisplayGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.path)
                .font(.caption.weight(.medium))
            Text("[")
                .font(.caption.monospaced())
            ForEach(Array(group.elements.enumerated()), id: \.offset) { index, element in
                VStack(alignment: .leading, spacing: 2) {
                    Text("{")
                        .font(.caption.monospaced())
                    ForEach(element.keys.sorted(), id: \.self) { field in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(field):")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            CopyableDetailText(element[field] ?? "", font: .caption)
                        }
                        .padding(.leading, 12)
                    }
                    Text(index == group.elements.indices.last ? "}" : "},")
                        .font(.caption.monospaced())
                }
                .padding(.leading, 8)
            }
            Text("]")
                .font(.caption.monospaced())
        }
    }

    private func jsonArray(_ text: String) -> [Any] {
        guard let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let array = value as? [Any] else {
            return []
        }
        return array
    }

    private func jsonDisplayValue(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return String(text.dropFirst().dropLast())
    }
}

private struct ArrayOutputDisplayGroup: Identifiable {
    let path: String
    let elements: [[String: String]]

    var id: String { path }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
}

private struct ToastView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("닫기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .frame(maxWidth: 420, alignment: .leading)
    }
}

private struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: () -> Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        _isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private struct WorkflowSection<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct LabeledInput<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            content()
        }
    }
}

private struct RunningProgressRow: View {
    let name: String
    let detail: String
    let progress: Int
    let total: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(name, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: Double(progress), total: Double(max(total, 1)))
            Text("\(progress)/\(total)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CopyableDetailText: View {
    let text: String
    let font: Font
    @State private var isHovering = false

    init(_ text: String, font: Font = .caption) {
        self.text = text
        self.font = font
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(font)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            if isHovering {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("복사")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct DatasetLibraryTable: View {
    let datasets: [SavedDataset]
    @Binding var selection: UUID?
    let onExport: (SavedDataset) -> Void
    let onDelete: (SavedDataset) -> Void

    var body: some View {
        Table(datasets, selection: $selection) {
            TableColumn("데이터셋") { dataset in
                Text(dataset.name)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("내보내기") { onExport(dataset) }
                        Divider()
                        Button("삭제", role: .destructive) { onDelete(dataset) }
                    }
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
                        HStack(spacing: 12) {
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

private enum PromptStructuredBlock {
    case heading(level: Int, text: String)
    case bullet(depth: Int, text: String)
    case paragraph(String)
    case code(String)
    case divider
}

private struct PromptStructuredView: View {
    let text: String

    private var blocks: [PromptStructuredBlock] {
        PromptStructuredParser.blocks(from: text)
    }

    var body: some View {
        ScrollView {
            if blocks.isEmpty {
                ContentUnavailableView("표시할 프롬프트가 없습니다.", systemImage: "text.document")
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { item in
                        blockView(item.element)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func blockView(_ block: PromptStructuredBlock) -> some View {
        switch block {
        case let .heading(level, value):
            Text(value)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level == 1 ? 6 : 2)
        case let .bullet(depth, value):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•")
                Text(value)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .paragraph(value):
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .code(value):
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.tertiary, in: RoundedRectangle(cornerRadius: 4))
        case .divider:
            Divider()
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }
}

private struct OutputExampleFieldPicker: View {
    let schema: PromptOutputSchema
    @Binding var selection: [String]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(schema.exampleNodes) { node in
                    if node.isSelectable {
                        Button {
                            toggle(node.path)
                        } label: {
                            nodeRow(node, isSelected: selection.contains(node.path))
                        }
                        .buttonStyle(.plain)
                        .help(node.path)
                    } else {
                        nodeRow(node, isSelected: false)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 3)
        }
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 90, maxHeight: 150)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }

    private func nodeRow(_ node: PromptOutputExampleNode, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            if node.isSelectable {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            Text(node.label)
                .font(.caption.monospaced())
            Text(": \(node.value)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(node.depth) * 16 + 6)
        .padding(.vertical, 3)
        .padding(.trailing, 6)
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    private func toggle(_ path: String) {
        if selection.contains(path) {
            selection.removeAll { $0 == path }
        } else {
            selection.append(path)
        }
    }
}

private struct DatasetPreviewFieldPicker: View {
    let headers: [String]
    let rows: [DatasetRow]
    @Binding var selection: [String]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ForEach(headers, id: \.self) { header in
                        Text(header)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(selection.contains(header) ? Color.accentColor : Color.secondary)
                            .frame(width: 150, alignment: .leading)
                    }
                }
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        ForEach(headers, id: \.self) { header in
                            datasetCell(row: row, header: header)
                        }
                    }
                }
            }
            .padding(6)
        }
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 90, maxHeight: 150)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }

    private func toggle(_ field: String) {
        if selection.contains(field) {
            selection.removeAll { $0 == field }
        } else {
            selection.append(field)
        }
    }

    private func datasetCell(row: DatasetRow, header: String) -> some View {
        let isSelected = selection.contains(header)
        let value = row.values[header] ?? ""
        return Button {
            toggle(header)
        } label: {
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 150, height: 34, alignment: .leading)
                .padding(.horizontal, 5)
                .background(
                    isSelected ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(header)
    }
}

private enum PromptStructuredParser {
    static func blocks(from text: String) -> [PromptStructuredBlock] {
        var result: [PromptStructuredBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var isInCodeBlock = false

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !paragraph.isEmpty {
                result.append(.paragraph(cleanInlineMarkdown(paragraph)))
            }
            paragraphLines = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                if isInCodeBlock {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                isInCodeBlock.toggle()
                continue
            }
            if isInCodeBlock {
                codeLines.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            if isDivider(trimmed) {
                flushParagraph()
                result.append(.divider)
                continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph()
                result.append(.heading(level: heading.level, text: cleanInlineMarkdown(heading.text)))
                continue
            }
            if let bullet = bullet(from: line) {
                flushParagraph()
                result.append(.bullet(depth: bullet.depth, text: cleanInlineMarkdown(bullet.text)))
                continue
            }
            paragraphLines.append(line)
        }

        if isInCodeBlock {
            result.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        return result
    }

    private static func heading(from value: String) -> (level: Int, text: String)? {
        let hashes = value.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), value.count > hashes else { return nil }
        let start = value.index(value.startIndex, offsetBy: hashes)
        guard value[start] == " " else { return nil }
        let text = value[value.index(after: start)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes, text)
    }

    private static func bullet(from line: String) -> (depth: Int, text: String)? {
        let indentation = line.prefix { $0 == " " || $0 == "\t" }.count
        let content = line.dropFirst(indentation)
        let prefixLength: Int
        if content.hasPrefix("- ") || content.hasPrefix("* ") || content.hasPrefix("+ ") {
            prefixLength = 2
        } else {
            let digits = content.prefix { $0.isWholeNumber }
            guard !digits.isEmpty,
                  content.dropFirst(digits.count).hasPrefix(". ") else {
                return nil
            }
            prefixLength = digits.count + 2
        }
        let text = content.dropFirst(prefixLength).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (indentation / 2, text)
    }

    private static func isDivider(_ value: String) -> Bool {
        value.count >= 3 && Set(value).isSubset(of: Set("-*_"))
    }

    private static func cleanInlineMarkdown(_ value: String) -> String {
        value
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
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
