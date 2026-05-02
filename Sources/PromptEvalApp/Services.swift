import CryptoKit
import Foundation

enum LibraryStore {
    static func load() throws -> SavedLibrary {
        let url = try libraryURL(createDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SavedLibrary.self, from: Data(contentsOf: url))
    }

    static func save(_ library: SavedLibrary) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(library).write(to: libraryURL(createDirectory: true), options: .atomic)
    }

    private static func libraryURL(createDirectory: Bool) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let directory = appSupport.appendingPathComponent("PromptEvalApp", isDirectory: true)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("library.json")
    }
}

enum NetworkService {
    static func request(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        maxRateLimitRetries: Int = 0
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.timeoutInterval = 90

        var retry = 0
        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AppError.message("제공 서비스가 올바르지 않은 응답을 반환했습니다.")
            }
            if 200..<300 ~= response.statusCode {
                return data
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "No error body"
            guard response.statusCode == 429, retry < maxRateLimitRetries else {
                throw AppError.message("HTTP \(response.statusCode): \(responseBody.prefix(500))")
            }

            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            let exponentialDelay = pow(2.0, Double(retry))
            let delay = retryAfter ?? (exponentialDelay + Double.random(in: 0...0.25))
            retry += 1
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

enum GoogleSheetsService {
    static func load(spreadsheetID: String, range: String, apiKey: String) async throws -> (headers: [String], rows: [DatasetRow]) {
        guard !spreadsheetID.isEmpty, !range.isEmpty, !apiKey.isEmpty else {
            throw AppError.message("스프레드시트 ID, 범위, Google Sheets API 키를 모두 입력하세요.")
        }
        let safeID = spreadsheetID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spreadsheetID
        let safeRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        var components = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(safeID)/values/\(safeRange)")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        let data = try await NetworkService.request(url: components.url!)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let values = object?["values"] as? [[String]] ?? []
        guard let headers = values.first else { throw AppError.message("요청한 시트 범위가 비어 있습니다.") }
        return (headers, try DatasetDecoder.rows(headers: headers, values: Array(values.dropFirst())))
    }
}

enum LLMService {
    static func models(provider: ProviderKind, apiKey: String) async throws -> [ModelOption] {
        guard !apiKey.isEmpty else { throw AppError.message("API 키를 먼저 입력하세요.") }
        switch provider {
        case .gemini:
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            let data = try await NetworkService.request(url: components.url!)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = (object?["models"] as? [[String: Any]] ?? []).compactMap { model -> ModelOption? in
                guard let name = model["name"] as? String,
                      (model["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                return ModelOption(id: id, name: model["displayName"] as? String ?? id)
            }
            return models.sorted { $0.id < $1.id }
        case .openAI:
            let url = URL(string: "https://api.openai.com/v1/models")!
            let data = try await NetworkService.request(url: url, headers: ["Authorization": "Bearer \(apiKey)"])
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = (object?["data"] as? [[String: Any]] ?? []).compactMap { model -> ModelOption? in
                guard let id = model["id"] as? String, id.hasPrefix("gpt-") || id.contains("codex") else { return nil }
                return ModelOption(id: id, name: id)
            }
            return models.sorted { $0.id < $1.id }
        }
    }

    static func generate(provider: ProviderKind, apiKey: String, model: String, prompt: String) async throws -> LLMGeneratedResponse {
        guard !apiKey.isEmpty, !model.isEmpty else { throw AppError.message("제공 서비스를 연결하고 모델을 선택하세요.") }
        switch provider {
        case .gemini:
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
            components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
            let body = try JSONSerialization.data(withJSONObject: [
                "contents": [["parts": [["text": prompt]]]],
                "generationConfig": ["temperature": 0],
            ])
            let data = try await NetworkService.request(
                url: components.url!,
                method: "POST",
                headers: ["Content-Type": "application/json"],
                body: body,
                maxRateLimitRetries: 4
            )
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let candidates = object?["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            guard let output = parts?.compactMap({ $0["text"] as? String }).joined(separator: "\n"), !output.isEmpty else {
                throw AppError.message("Gemini가 텍스트 응답을 반환하지 않았습니다.")
            }
            let usage = object?["usageMetadata"] as? [String: Any]
            return LLMGeneratedResponse(
                text: output,
                inputTokens: usage?["promptTokenCount"] as? Int,
                outputTokens: usage?["candidatesTokenCount"] as? Int
            )
        case .openAI:
            let body = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "input": prompt,
                "temperature": 0,
            ])
            let data = try await NetworkService.request(
                url: URL(string: "https://api.openai.com/v1/responses")!,
                method: "POST",
                headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
                body: body,
                maxRateLimitRetries: 4
            )
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let directOutput = object?["output_text"] as? String
            let output = (object?["output"] as? [[String: Any]] ?? []).flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            let text = directOutput?.isEmpty == false ? directOutput! : output
            guard !text.isEmpty else { throw AppError.message("OpenAI가 텍스트 응답을 반환하지 않았습니다.") }
            let usage = object?["usage"] as? [String: Any]
            return LLMGeneratedResponse(
                text: text,
                inputTokens: usage?["input_tokens"] as? Int,
                outputTokens: usage?["output_tokens"] as? Int
            )
        }
    }
}

enum GenerationCheckpointStore {
    static func prepare(datasetID: UUID) throws {
        try Data().write(to: fileURL(for: datasetID), options: .atomic)
    }

    static func append(_ record: GenerationCheckpointRecord) throws {
        let url = try fileURL(for: record.datasetID)
        let data = try JSONEncoder().encode(record) + Data([0x0A])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    static func recover(into datasets: inout [SavedDataset]) throws -> Set<UUID> {
        let directory = try directoryURL()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var recoveredDatasetIDs: Set<UUID> = []
        let decoder = JSONDecoder()

        for file in files where file.pathExtension == "jsonl" {
            guard let datasetID = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let datasetIndex = datasets.firstIndex(where: { $0.id == datasetID }) else {
                continue
            }
            recoveredDatasetIDs.insert(datasetID)
            let lines = try Data(contentsOf: file).split(separator: 0x0A)
            for line in lines {
                guard let record = try? decoder.decode(GenerationCheckpointRecord.self, from: Data(line)),
                      let rowIndex = datasets[datasetIndex].rows.firstIndex(where: { $0.id == record.rowID }) else {
                    continue
                }
                datasets[datasetIndex].rows[rowIndex].llmInput = record.llmInput
                datasets[datasetIndex].rows[rowIndex].output = record.output
                datasets[datasetIndex].rows[rowIndex].error = record.error
                datasets[datasetIndex].rows[rowIndex].outputModel = record.outputModel
                datasets[datasetIndex].rows[rowIndex].latencyMilliseconds = record.latencyMilliseconds
                datasets[datasetIndex].rows[rowIndex].inputTokens = record.inputTokens
                datasets[datasetIndex].rows[rowIndex].outputTokens = record.outputTokens
            }
            let headers = datasets[datasetIndex].headers
            let rows = datasets[datasetIndex].rows
            datasets[datasetIndex].updateContents(headers: headers, rows: rows)
        }
        return recoveredDatasetIDs
    }

    static func remove(datasetID: UUID) throws {
        let url = try fileURL(for: datasetID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func fileURL(for datasetID: UUID) throws -> URL {
        try directoryURL().appendingPathComponent("\(datasetID.uuidString).jsonl")
    }

    private static func directoryURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("PromptEvalApp", isDirectory: true)
            .appendingPathComponent("generation-checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum EvaluationBundle {
    private static let resultArtifactNames = [
        "promptfoo-validation.json",
        "codex-judgements.json",
        "evaluated-dataset.json",
        "evaluated-dataset.csv",
        "summary.json",
        "evaluation-log.json",
        "evaluation-log.sha256",
    ]

    static func write(input: EvaluationInput) throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let formatter = ISO8601DateFormatter()
        let folder = appSupport
            .appendingPathComponent("PromptEvalApp", isDirectory: true)
            .appendingPathComponent("evaluations", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(input).write(to: folder.appendingPathComponent("eval-input.json"))
        try packageJSON.write(to: folder.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try runner.write(to: folder.appendingPathComponent("run-eval.mjs"), atomically: true, encoding: .utf8)
        try readme.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        return folder
    }

    static func prepareSharedRuntime() throws -> (directory: URL, needsInstall: Bool) {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport
            .appendingPathComponent("PromptEvalApp", isDirectory: true)
            .appendingPathComponent("evaluation-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let packageURL = directory.appendingPathComponent("package.json")
        let markerURL = directory.appendingPathComponent(".runtime-ready")
        let installedPackage = try? String(contentsOf: packageURL, encoding: .utf8)
        if installedPackage != packageJSON {
            try packageJSON.write(to: packageURL, atomically: true, encoding: .utf8)
        }
        let marker = try? String(contentsOf: markerURL, encoding: .utf8)
        let nodeModulesExists = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("node_modules", isDirectory: true).path
        )
        return (directory, !nodeModulesExists || marker != packageJSON)
    }

    static func markSharedRuntimeReady(at directory: URL) throws {
        try packageJSON.write(
            to: directory.appendingPathComponent(".runtime-ready"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func linkSharedRuntime(from runtimeDirectory: URL, to bundleDirectory: URL) throws {
        let bundleNodeModules = bundleDirectory.appendingPathComponent("node_modules", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleNodeModules.path) { return }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: bundleNodeModules.path)) != nil {
            try FileManager.default.removeItem(at: bundleNodeModules)
        }
        let runtimeNodeModules = runtimeDirectory.appendingPathComponent("node_modules", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtimeNodeModules.path) else {
            throw AppError.message("공용 평가 런타임의 node_modules가 없습니다.")
        }
        try FileManager.default.createSymbolicLink(at: bundleNodeModules, withDestinationURL: runtimeNodeModules)
    }

    static func lockCompletedResults(in bundleDirectory: URL) throws {
        let resultsDirectory = bundleDirectory.appendingPathComponent("results", isDirectory: true)
        for name in resultArtifactNames {
            let url = resultsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o444, .immutable: true],
                ofItemAtPath: url.path
            )
        }
    }

    static func deleteEvaluation(at bundleDirectory: URL) throws {
        let resultsDirectory = bundleDirectory.appendingPathComponent("results", isDirectory: true)
        for name in resultArtifactNames {
            let url = resultsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.setAttributes(
                [.immutable: false, .posixPermissions: 0o644],
                ofItemAtPath: url.path
            )
        }
        try FileManager.default.removeItem(at: bundleDirectory)
    }

    private static let packageJSON = #"""
{
  "private": true,
  "type": "module",
  "scripts": { "eval": "node run-eval.mjs" },
  "dependencies": {
    "@openai/codex-sdk": "latest",
    "promptfoo": "0.115.4"
  }
}
"""#

    private static let readme = #"""
# Promptfoo + Codex evaluation bundle

This folder was generated by PromptEvalApp. It validates saved model outputs with Promptfoo, then asks the locally authenticated Codex SDK to judge a limited number of outputs. Results are written incrementally to the `results` folder.

Data artifacts:

- `eval-input.json`: original row values, rendered LLM input, and model output.
- `results/evaluated-dataset.json`: LLM execution data joined with Codex judgements.
- `results/evaluated-dataset.csv`: the same evaluated data in CSV format.

Prerequisites:

1. Install Node.js and pnpm.
2. Authenticate Codex locally (`codex login`).
3. Run `JUDGE_LIMIT=20 CODEX_CONCURRENCY=3 pnpm run eval` after dependencies are linked.

`JUDGE_LIMIT` defaults to 20; `0` judges every row. `CODEX_CONCURRENCY` defaults to 3.
"""#

    private static let runner = #"""
import fs from "node:fs/promises";
import path from "node:path";
import { createHash } from "node:crypto";
import promptfoo from "promptfoo";
import { Codex } from "@openai/codex-sdk";

const root = process.cwd();
const input = JSON.parse(await fs.readFile(path.join(root, "eval-input.json"), "utf8"));
const rows = input.rows.filter((row) => row.output && !row.error);
const judgeLimit = Number.parseInt(process.env.JUDGE_LIMIT ?? "20", 10);
const codexConcurrency = Math.max(1, Number.parseInt(process.env.CODEX_CONCURRENCY ?? "3", 10));
const evaluationModel = process.env.CODEX_MODEL ?? "gpt-5.5";
const evaluationStartedAt = new Date();
const resultsDir = path.join(root, "results");
await fs.mkdir(resultsDir, { recursive: true });
const auditLogPath = path.join(resultsDir, "evaluation-log.json");
try {
  await fs.access(auditLogPath);
  throw new Error("이미 완료된 평가 로그는 다시 실행하거나 수정할 수 없습니다. 새 평가 번들을 만드세요.");
} catch (error) {
  if (error?.code !== "ENOENT") throw error;
}
const renderPrompt = (template, values) => template.replace(
  /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/g,
  (_match, name) => values[name] ?? "",
);
const llmInputFor = (row) => row.llmInput ?? renderPrompt(input.prompt, row.values);

const passthrough = async (_prompt, context) => ({ output: context.vars.model_output });
const evaluation = await promptfoo.evaluate({
  prompts: ["{{model_output}}"],
  providers: [passthrough],
  tests: rows.map((row) => ({
    vars: { model_output: row.output },
    assert: [{ type: "is-json" }],
  })),
  writeLatestResults: false,
}, { maxConcurrency: 4 });
const validation = await evaluation.toEvaluateSummary();
await fs.writeFile(path.join(resultsDir, "promptfoo-validation.json"), JSON.stringify(validation, null, 2));

const codex = new Codex();
const judgeRows = judgeLimit === 0 ? rows : rows.slice(0, Math.max(judgeLimit, 0));
const judgements = new Array(judgeRows.length);
const judgeSchema = {
  type: "object",
  properties: {
    pass: { type: "boolean" },
    score: { type: "integer", minimum: 0, maximum: 100 },
    reasons: { type: "array", items: { type: "string" } },
    criteria: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          expected: { type: "string" },
          observed: { type: "string" },
          pass: { type: "boolean" },
          score: { type: "integer", minimum: 0, maximum: 100 },
          reason: { type: "string" },
        },
        required: ["name", "expected", "observed", "pass", "score", "reason"],
        additionalProperties: false,
      },
    },
  },
  required: ["pass", "score", "reasons", "criteria"],
  additionalProperties: false,
};

let nextJudgeIndex = 0;
let persistence = Promise.resolve();
const persistJudgements = () => {
  const snapshot = judgements.filter(Boolean);
  persistence = persistence.then(() => fs.writeFile(
    path.join(resultsDir, "codex-judgements.json"),
    JSON.stringify(snapshot, null, 2),
  ));
  return persistence;
};

const judgeRow = async (row, index) => {
  try {
    const thread = codex.startThread({
      workingDirectory: root,
      skipGitRepoCheck: true,
      model: evaluationModel,
    });
    const result = await thread.run(`You are a strict, impartial LLM evaluation judge.\n\nActual input sent to the evaluated model:\n${llmInputFor(row)}\n\nDataset row and expected fields:\n${JSON.stringify(row.values)}\n\nModel output:\n${row.output}\n\nJudge whether the output follows the prompt and the expected fields. Identify every evaluation criterion represented by the expected fields, such as sentiment score, inquiry type, spam score, risk score, and risk type. Combine minimum and maximum fields into one criterion when they define a range. For each criterion, record the expected value or range, the value actually found in the model output, its score, pass/fail, and a concrete reason. Every entry in reasons and every criterion reason must be written in Korean.`, { outputSchema: judgeSchema });
    judgements[index] = {
      rowId: row.id,
      status: "completed",
      evaluationModel,
      evaluationInputTokens: result.usage?.input_tokens ?? null,
      evaluationOutputTokens: result.usage?.output_tokens ?? null,
      evaluatedAt: new Date().toISOString(),
      judge: JSON.parse(result.finalResponse),
    };
  } catch (error) {
    judgements[index] = {
      rowId: row.id,
      status: "error",
      evaluationModel,
      evaluationInputTokens: null,
      evaluationOutputTokens: null,
      evaluatedAt: new Date().toISOString(),
      error: error instanceof Error ? error.message : String(error),
    };
  }
  await persistJudgements();
};

const worker = async () => {
  while (true) {
    const index = nextJudgeIndex;
    nextJudgeIndex += 1;
    if (index >= judgeRows.length) return;
    await judgeRow(judgeRows[index], index);
  }
};

await Promise.all(
  Array.from({ length: Math.min(codexConcurrency, judgeRows.length) }, () => worker()),
);
await persistence;

if (judgeRows.length === 0) {
  await fs.writeFile(path.join(resultsDir, "codex-judgements.json"), "[]\n");
}

const orderedJudgements = judgements.filter(Boolean);
const completed = orderedJudgements.filter((item) => item.status === "completed");
const scores = completed.map((item) => item.judge.score);
const judgementByRowId = new Map(orderedJudgements.map((item) => [item.rowId, item]));
const evaluatedDataset = input.rows.map((row) => {
  const judgement = judgementByRowId.get(row.id);
  return {
    ...row.values,
    llm_input: llmInputFor(row),
    model_output: row.output ?? null,
    generation_error: row.error ?? null,
    output_model: row.outputModel ?? input.model,
    latency_ms: row.latencyMilliseconds ?? null,
    input_tokens: row.inputTokens ?? null,
    output_tokens: row.outputTokens ?? null,
    codex_status: judgement?.status ?? (row.output ? "not_evaluated" : "generation_failed"),
    codex_pass: judgement?.judge?.pass ?? null,
    codex_score: judgement?.judge?.score ?? null,
    codex_reasons: judgement?.judge?.reasons ?? [],
    codex_criteria: judgement?.judge?.criteria ?? [],
    evaluation_model: judgement?.evaluationModel ?? null,
    evaluation_input_tokens: judgement?.evaluationInputTokens ?? null,
    evaluation_output_tokens: judgement?.evaluationOutputTokens ?? null,
    evaluated_at: judgement?.evaluatedAt ?? null,
    codex_error: judgement?.error ?? null,
  };
});
const csvHeaders = [...new Set(evaluatedDataset.flatMap((row) => Object.keys(row)))];
const csvEscape = (value) => {
  const text = Array.isArray(value)
    ? (value.some((item) => typeof item === "object") ? JSON.stringify(value) : value.join(" | "))
    : value && typeof value === "object" ? JSON.stringify(value)
    : value == null ? "" : String(value);
  return `"${text.replaceAll('"', '""')}"`;
};
const evaluatedCSV = [
  csvHeaders.map(csvEscape).join(","),
  ...evaluatedDataset.map((row) => csvHeaders.map((header) => csvEscape(row[header])).join(",")),
].join("\n") + "\n";
await fs.writeFile(path.join(resultsDir, "evaluated-dataset.json"), JSON.stringify(evaluatedDataset, null, 2));
await fs.writeFile(path.join(resultsDir, "evaluated-dataset.csv"), evaluatedCSV);
const latencies = input.rows.map((row) => row.latencyMilliseconds).filter(Number.isFinite);
const generationInputTokens = input.rows.reduce((sum, row) => sum + (row.inputTokens ?? 0), 0);
const generationOutputTokens = input.rows.reduce((sum, row) => sum + (row.outputTokens ?? 0), 0);
const evaluationInputTokens = orderedJudgements.reduce((sum, item) => sum + (item.evaluationInputTokens ?? 0), 0);
const evaluationOutputTokens = orderedJudgements.reduce((sum, item) => sum + (item.evaluationOutputTokens ?? 0), 0);
const codexPassed = completed.filter((item) => item.judge.pass).length;
const summary = {
  promptfooValidated: rows.length,
  promptfooPassed: validation.stats.successes,
  promptfooFailed: validation.stats.failures + validation.stats.errors,
  codexRequested: judgeRows.length,
  codexCompleted: completed.length,
  codexErrors: orderedJudgements.length - completed.length,
  codexPassed,
  codexAverageScore: scores.length > 0 ? scores.reduce((sum, score) => sum + score, 0) / scores.length : null,
  evaluationModel,
  executedAt: evaluationStartedAt.toISOString(),
  passRate: completed.length > 0 ? codexPassed / completed.length : null,
  averageLatencyMilliseconds: latencies.length > 0 ? latencies.reduce((sum, value) => sum + value, 0) / latencies.length : null,
  generationInputTokens,
  generationOutputTokens,
  evaluationInputTokens,
  evaluationOutputTokens,
};
await fs.writeFile(path.join(resultsDir, "summary.json"), JSON.stringify(summary, null, 2));
const auditLog = {
  schemaVersion: 1,
  evaluationID: path.basename(root),
  executedAt: evaluationStartedAt.toISOString(),
  input,
  summary,
  judgements: orderedJudgements,
};
const auditData = `${JSON.stringify(auditLog, null, 2)}\n`;
const auditHash = createHash("sha256").update(auditData).digest("hex");
const auditHashPath = path.join(resultsDir, "evaluation-log.sha256");
await fs.writeFile(auditLogPath, auditData, { flag: "wx" });
await fs.writeFile(auditHashPath, `${auditHash}\n`, { flag: "wx" });
await Promise.all([
  "promptfoo-validation.json",
  "codex-judgements.json",
  "evaluated-dataset.json",
  "evaluated-dataset.csv",
  "summary.json",
  "evaluation-log.json",
  "evaluation-log.sha256",
].map((name) => fs.chmod(path.join(resultsDir, name), 0o444)));
console.log(`Validated ${rows.length} output(s); Codex completed ${completed.length}/${judgeRows.length}.`);
"""#
}

enum EvaluationResultStore {
    static func load() throws -> [EvaluationResultRecord] {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("PromptEvalApp", isDirectory: true)
        .appendingPathComponent("evaluations", isDirectory: true)

        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder in
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
            guard values?.isDirectory == true else {
                return nil
            }

            let resultsFolder = folder.appendingPathComponent("results", isDirectory: true)
            let auditURL = resultsFolder.appendingPathComponent("evaluation-log.json")
            let hashURL = resultsFolder.appendingPathComponent("evaluation-log.sha256")
            let auditData = try? Data(contentsOf: auditURL)
            let audit = auditData.flatMap { try? decoder.decode(EvaluationAuditLog.self, from: $0) }
            let integrity: EvaluationLogIntegrity
            if let auditData {
                let actualHash = SHA256.hash(data: auditData).map { String(format: "%02x", $0) }.joined()
                let expectedHash = (try? String(contentsOf: hashURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                integrity = audit != nil && expectedHash == actualHash ? .verified : .invalid
            } else {
                integrity = .legacy
            }

            let fallbackInput = (try? Data(contentsOf: folder.appendingPathComponent("eval-input.json")))
                .flatMap { try? decoder.decode(EvaluationInput.self, from: $0) }
            guard let input = audit?.input ?? fallbackInput else { return nil }

            let fallbackSummary = try? decoder.decode(
                EvaluationRunSummary.self,
                from: Data(contentsOf: resultsFolder.appendingPathComponent("summary.json"))
            )
            let fallbackJudgements = (try? decoder.decode(
                [CodexJudgementRecord].self,
                from: Data(contentsOf: resultsFolder.appendingPathComponent("codex-judgements.json"))
            )) ?? []
            let summary = audit?.summary ?? fallbackSummary
            let judgements = audit?.judgements ?? fallbackJudgements

            return EvaluationResultRecord(
                id: folder.lastPathComponent,
                folderURL: folder,
                createdAt: audit?.executedAt ?? summary?.executedAt ?? values?.creationDate ?? .distantPast,
                input: input,
                summary: summary,
                judgements: judgements,
                integrity: integrity
            )
        }
        .sorted { $0.executionDate > $1.executionDate }
    }
}

enum ProcessRunner {
    static func run(
        command: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String] = [:]
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
            let errorPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AppError.message("\(command) failed: \(error.prefix(500))"))
                }
            }
            do {
                try process.run()
            } catch {
                    continuation.resume(throwing: AppError.message("\(command)을 실행할 수 없습니다. 설치한 뒤 PATH에 추가하세요."))
            }
        }
    }
}
