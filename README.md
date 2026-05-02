# PromptEvalApp

로컬 프롬프트 실험을 위한 SwiftUI macOS 앱입니다.

## 실행

```bash
swift run
```

## 제공 기능

- 여러 `.md` / `.txt` 프롬프트 등록·선택·저장과 `{{variables}}` 감지
- 여러 CSV·JSON·Google Sheets 데이터셋 등록·선택·저장
- 긴 프롬프트를 위한 스크롤 가능한 고정폭 편집기
- Gemini 또는 OpenAI 연결, 모델 목록 조회, `model_output` 생성
- 업데이트된 CSV 내보내기
- 로컬 Promptfoo + Codex SDK 평가 번들 생성과 실행

Google Sheet 가져오기는 API 키로 접근 가능한 시트에 사용합니다. 비공개 시트는 OAuth 연동이 필요하며 이 로컬 프로토타입에는 포함하지 않았습니다.

생성된 평가 실행기에는 Node.js, pnpm, 인증된 로컬 Codex CLI가 필요합니다. Codex 평가는 기본 20행으로 제한되며, 표본을 검토한 뒤에만 `JUDGE_LIMIT`를 늘리세요.

등록된 프롬프트와 데이터셋은 `~/Library/Application Support/PromptEvalApp/library.json`에 보관됩니다. API 키는 저장하지 않습니다.
