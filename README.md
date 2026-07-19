# PromptEvalApp

로컬 프롬프트 실험을 위한 SwiftUI macOS 앱입니다.

## 실행

```bash
swift run
```

## 제공 기능

- 여러 `.md` / `.txt` 프롬프트 등록·선택·저장과 `{{variables}}` 감지
- 여러 CSV·JSON·Google Sheets 데이터셋 등록·선택·저장
- 프롬프트·데이터셋·LLM 모델을 묶은 재사용 가능한 테스트 케이스
- 첫 번째 행 미리 실행과 기댓값 ↔ LLM output JSON 경로 매핑
- 값 타입별 PASS 규칙 추천 및 범위·일치·포함·값 존재 규칙 편집
- 선택한 로컬 Codex agent 모델을 이용한 평가 기준 추천
- 실행 레코드 수와 동시 요청 수 조절, 실행 중 취소
- 데이터셋과 분리된 LLM output 및 불변 테스트 결과 JSON/CSV
- 완료된 테스트 결과를 입력으로 사용하는 Promptfoo + Codex 평가

Google Sheet 가져오기는 API 키로 접근 가능한 시트에 사용합니다. 비공개 시트는 OAuth 연동이 필요하며 이 로컬 프로토타입에는 포함하지 않았습니다.

생성된 평가 실행기에는 Node.js, pnpm, 인증된 로컬 Codex CLI가 필요합니다. API 키는 앱 세션 메모리에만 보관합니다.

## 로컬 저장 구조

- `library.json`: 프롬프트와 원본 데이터셋
- `test-cases.json`: 테스트 케이스와 평가 기준 정의
- `llm-outputs/`: 테스트 케이스 미리 실행 output
- `test-runs/<id>/llm-outputs.json`: 전체 실행의 LLM output 원본
- `test-runs/<id>/test-result.json`: 변수·기댓값·추출값·PASS 결과·토큰·레이턴시
- `test-runs/<id>/test-result.csv`: 동일 결과의 CSV 형식
- `evaluations/`: Codex 평가 감사 로그와 평가 결과

모든 경로의 기준 디렉터리는 `~/Library/Application Support/PromptEvalApp`입니다. 완료된 테스트 결과와 평가 로그는 읽기 전용 및 macOS 불변 파일로 잠깁니다.
