# Shelf(서재) — Claude Code 연동 로컬 지식 서재 앱 설계

- 날짜: 2026-07-23
- 작성: Claude Code 세션 브레인스토밍으로 확정
- 상태: 설계 승인 대기 → 승인 시 구현 계획 단계로
- 이번 세션 범위: **설계만** (구현 없음)

## 1. 목적 · 배경

Claude Code 세션에서 "이거 설명해줘"라고 물으면 다이어그램 포함 리치 HTML 해설 챕터가 생성된다(현재 `tech-guide-book.html` 5챕터로 검증됨). 이 산출물을:

1. **맥북 로컬 앱**에서 ebook처럼 읽는다 — 독 아이콘, 앱 창, 서재(라이브러리) UI.
2. 질문할 때마다 생기는 챕터가 **자동으로 서재에 쌓인다** — 자기만의 지식 저장소(로컬 옵시디언 감성).
3. 도구 자체는 **깃허브에 소스 공개**해 다른 Claude Code 사용자도 자기 서재를 만들 수 있게 한다.

기존 자산 재사용: 챕터 HTML 형식과 생성 절차(현 책 파이프라인), 페이지형 책 UI, 챕터 품질 가드(awk 검사), 개인 위키(`llm-wiki`)와는 별개 유지.

## 2. 확정된 핵심 결정 (대안 · 근거)

| # | 결정 | 대안(기각) | 근거 |
|---|---|---|---|
| D1 | 지식 원본 포맷 = **자립형 리치 HTML 챕터** (현 가이드 형식 그대로) | Markdown 볼트, MD→HTML 하이브리드 | SVG 다이어그램 해설이 이 제품의 차별점. 검증된 파이프라인·기존 5챕터 100% 재사용. MD는 "그럼 그냥 Obsidian 쓰지"에 취약 |
| D2 | 조직 모델 = **라이브러리(서재 → 책 → 챕터)** | 한 권의 책(현행), 플랫+태그(Obsidian식) | 주제가 늘어도 무너지지 않으면서 ebook 읽기 감성(책·읽기 순서) 유지. 태그/그래프는 v1 과잉 |
| D3 | 앱 = **Swift + WKWebView 네이티브 .app** (로컬 전용, 배포 없음) | Tauri, 로컬서버+브라우저 독 추가 | 이 맥에 Swift 6.3.2 기설치(실측) → 새 툴체인 0. 진짜 앱 요구 충족. 배포 안 하므로 서명·dmg 불필요. Rust 미설치라 Tauri는 과함 |
| D4 | 연동 = **파일 시스템** (스킬이 폴더에 쓰고, 앱이 폴더 감시) | 훅 푸시, MCP 서버 | 서로를 직접 호출하지 않아 각자 독립 동작(앱 꺼져 있어도 스킬 동작, Claude 없어도 앱 동작). 훅/MCP는 필요해지면 승격 |
| D5 | 외부 리서치 스킬 = **동봉하지 않고 추천 + 있으면 활용** | 레포에 복사 동봉 | 복사본은 낡음(조직 원칙), 라이선스·재배포 문제, 레포 정체성 유지. README 추천 + `/learn`이 설치된 도구를 감지해 활용 |
| D6 | 공개 범위 = **도구만 공개, 서재 내용물은 비공개** | 서재 통째 공개 | 현 챕터에 업무상 비공개 정보 포함 — 라이브러리는 레포 밖(`~/Shelf`), 레포엔 일반 주제 샘플만 |
| D7 | 챕터 렌더링 = **iframe 로드** (합본 격리 regex 제거) | 현 build_book식 접두어 격리 합본 | iframe이면 챕터가 각자 문서라 id/CSS 충돌이 원천 소멸. 깨지기 쉬운 regex 격리·`<pre>` 가드 문제가 설계 차원에서 제거 |
| D8 | 이름 = 앱/레포 가칭 **Shelf** (한글 표기 "서재", 레포명 후보 `claude-shelf`) | — | 구현 시작 전 사용자가 바꿀 수 있음. 문서 내 일관 표기용 확정 |

## 3. 전체 아키텍처

3개 층, 접점은 파일 시스템 하나:

```
[사용자] "Iceberg vs Delta 설명해줘"
    ↓  Claude Code 세션
[스킬 /learn] 리서치 → 챕터 HTML 생성 → 품질 가드 → ~/Shelf/books/…에 저장
              + library.json 갱신 (등록)
    ↓  파일 변경 (연동의 전부)
[Shelf.app] FSEvents 폴더 감시 → 웹 UI에 reload 신호
    → 사이드바에 새 챕터 자동 등장 → ebook처럼 읽기
```

- 스킬과 앱은 서로의 존재를 모른다. 계약은 오직 **폴더 구조 + library.json 스키마**.
- Claude Code 쪽 추가 설정(훅·MCP) 없음.

## 4. 데이터 모델 — 라이브러리 폴더

기본 위치 `~/Shelf/` (앱·스킬 양쪽에서 설정으로 변경 가능, v1 기본값 고정):

```
~/Shelf/
  library.json          # 서재 매니페스트 (유일한 인덱스)
  library.json.bak      # 스킬이 쓰기 직전 자동 백업
  books/
    data-engineering/   # 책 = 폴더 (slug)
      medallion-architecture.html  # 챕터 = 자립형 리치 HTML (slug.html)
      iceberg-vs-delta.html
    aws-basics/
      cloudformation.html
```

### library.json 스키마 (v1)

```json
{
  "version": 1,
  "shelfTitle": "기술 해설 노트",
  "books": [
    {
      "slug": "data-engineering",
      "title": "데이터 엔지니어링",
      "emoji": "🗄️",
      "chapters": [
        { "slug": "medallion-architecture", "title": "메달리온 아키텍처", "added": "2026-07-23" },
        { "slug": "iceberg-vs-delta", "title": "Iceberg vs Delta Lake", "added": "2026-07-23" }
      ]
    }
  ]
}
```

- 챕터 파일 경로는 `books/<book.slug>/<chapter.slug>.html`로 유도(스키마에 경로 중복 저장 안 함).
- 배열 순서 = 읽기 순서(책 순서, 챕터 순서).
- `version` 필드로 향후 스키마 변경 대비.

### 챕터 HTML 계약 (스킬 생성물의 형식 — 현 가이드 형식 그대로)

- 자립형: 인라인 `<style>`, 외부 리소스 없음(오프라인 완결).
- 구조: `<title>` + head style + `<header class="top">`(`<h1>`, `<p class="sub">`) + `<div class="wrap">`본문`</div>`.
- 라이트/다크 테마 변수(`data-theme`) 지원.
- SVG 다이어그램: SVG 내부에 `<b>` 등 HTML 태그 금지(강조는 `<tspan font-weight>`).

## 5. 뷰어 앱 (Shelf.app)

### Swift 셸 (파일 1개, 약 150–200줄, 거의 안 바뀜)

- `NSApplication` + 창 1개 + `WKWebView`.
- 라이브러리 폴더 읽기 허용(`loadFileURL(_:allowingReadAccessTo:)` + 로컬 파일 접근 설정).
- **FSEvents(또는 DispatchSource)로 `~/Shelf` 감시** → 변경 시 웹 UI에 JS 이벤트(`shelfChanged`) 전달.
- 빌드: `swiftc` 한 줄 → `.app` 번들 생성 스크립트(`build.sh`). 서명 없음(본인 맥 전용).

### 웹 UI (app/ui/ — HTML/CSS/JS, 프레임워크 없음)

- **사이드바**: 서재 → 책(이모지+제목) → 챕터 트리. 현재 위치 하이라이트. `library.json`을 읽어 렌더.
- **챕터 뷰**: 페이지형(한 번에 한 챕터). 챕터 HTML을 **iframe**으로 로드(D7 — 스타일·id 격리 공짜). 이전/다음/책 목차 내비게이션.
- **검색**: 전체 라이브러리 대상 텍스트 검색. v1 구현 = 검색 시 챕터 HTML들을 fetch해 텍스트 추출 후 매칭(수십 챕터 규모에서 충분; 수백 개가 되면 사전 인덱스로 개선).
- **테마**: 라이트/다크 토글(현 책 UI 이식).
- **자동 갱신**: `shelfChanged` 수신 → library.json 다시 읽어 사이드바 갱신, 보던 챕터는 유지.

## 6. Claude Code 연동 스킬 (skills/ — 공개 번들)

| 스킬 | 동작 | 세부 |
|---|---|---|
| **/learn `<주제>`** | 주제 리서치 → 리치 HTML 챕터 생성 → 책 배정 → 등록 | ① 리서치: 내장 웹검색/레포/대화 맥락 + **설치된 외부 리서치 스킬 감지 시 활용**(D5; 감지 = 세션의 사용 가능 스킬 목록에서 리서치 성격 스킬을 확인, 없으면 내장 도구만으로 동작). ② 챕터 생성: §4 계약 형식. ③ 책 배정: 기존 책 중 어울리는 곳 제안, 없으면 새 책 제안(사용자 확인). ④ 가드 통과 시 저장+등록 |
| **/shelf** | 서재 관리 | 책 생성·이름변경·이모지 변경, 챕터 이동·삭제·순서 변경. `library.json`(+파일 이동)만 조작. 쓰기 전 `.bak` 백업 |
| **/learn-from-session** | 지금 대화에서 배운 내용을 챕터로 | /learn의 변형(리서치 대신 대화 내용을 소재로). v1은 단순 버전 |

### 챕터 품질 가드 (`skills/…/validate.py` — 등록 전 필수 통과)

현 세션에서 수동으로 하던 검사의 정식화:

1. 필수 구조 존재: `<title>`, `<h1>` 1개, `p.sub`, `div.wrap`.
2. SVG 내부 HTML 태그(`<b>` 등) 0개 — foreign-content breakout 방지.
3. 외부 리소스 참조 0개(자립형 보장): `http(s)://` src/href 링크 검사(본문 텍스트 내 참고링크는 허용, 리소스 로드만 금지).
4. `library.json` 스키마 유효성(쓰기 후 재파싱).

실패 시: 등록하지 않고 무엇이 걸렸는지 사용자에게 보고.

## 7. 에러 처리

| 상황 | 동작 |
|---|---|
| `library.json` 파싱 실패 | 앱: 에러 화면 + `library.json.bak` 복구 버튼. 스킬: 쓰기 전 항상 `.bak` 생성 |
| 목록에 있는데 챕터 파일 없음 | 사이드바에 흐리게 표시 + 클릭 시 "파일 없음" 안내(조용히 숨기지 않음) |
| 폴더 감시 실패/누락 | 수동 새로고침 버튼 상시 제공(자동 갱신은 편의 기능) |
| 스킬 가드 실패 | 미등록 + 실패 항목 보고 |
| 검색 중 챕터 로드 실패 | 해당 챕터만 건너뛰고 결과에 "검색 제외됨" 표시 |

## 8. 검증 기준 (구현 완료 판정표)

1. `./build.sh` → `Shelf.app` 생성, 독에서 클릭해 열림.
2. 기존 챕터 전량을 이전 후 다이어그램 포함 그대로 렌더(스크린샷 대조).
3. 앱 켜둔 채 `/learn`으로 새 챕터 추가 → **5초 내** 사이드바 자동 등장.
4. 검색어 입력 → 해당 챕터 검색·이동 동작.
5. `library.json` 고의 손상 → 에러 화면 + 백업 복구 동작.
6. `validate.py`에 고의 불량 HTML(SVG 내 `<b>`) 입력 → 등록 거부 확인.

## 9. 마이그레이션 (기존 자산 → 서재)

- 현 5개 `*-guide.html`은 이미 §4 챕터 계약을 만족 → `~/Shelf/books/…`로 복사 + `library.json` 최초 작성이면 끝.
- 초기 책 구성은 **레포 밖 설정 파일**(`~/.config/shelf/book-layout.json`)에 둔다. 개인 서재의 책·챕터 이름은 업무 주제를 드러낼 수 있으므로 레포에 커밋하지 않는다. 레포에는 일반 주제 예시(`examples/book-layout.example.json`)만 둔다. 마이그레이션 후에는 `/shelf`로 자유 개편.
- `build_book.py`: 폐기하지 않고 **"서재 전체 → 한 파일 합본 export"** 도구로 강등 유지(공유·인쇄용).
- 개인 메모리의 "책에 챕터 추가" 절차는 구현 완료 후 "서재에 /learn" 절차로 갱신.

## 10. 깃허브 공개

- 레포 구성:
  ```
  claude-shelf/
    app/           # Swift 셸 + build.sh + ui/(웹 UI)
    skills/        # /learn, /shelf, /learn-from-session + validate.py
    examples/      # 일반 주제 샘플 챕터 1–2개 + 샘플 library.json
    README.md      # 빌드 한 줄, 스킬 설치, "함께 쓰면 좋은 스킬"(외부 링크만)
    LICENSE        # MIT
  ```
- **프라이버시 경계(D6)**: 개인 서재(`~/Shelf`)는 레포 밖. 업무상 비공개 정보가 담긴 챕터는 절대 커밋하지 않음. examples는 일반 주제만. 커밋 전 `tools/privacy-check.sh`로 강제.
- 배포 파이프라인 없음: "clone → `./build.sh`" 안내가 전부.

## 11. 비범위 (v1에서 하지 않는 것)

- 앱 내 질문/생성(Anthropic API 연동) — 질문은 Claude Code에서.
- 훅·MCP 연동(파일 감시로 충분; 필요 시 승격).
- 태그·백링크·그래프 뷰(Obsidian식 탐색).
- Markdown 지원, 서명·dmg 배포, 자동 업데이트, iCloud/기기 동기화.
- 다국어 UI(한국어 우선).

## 12. 구현 순서 제안 (다음 단계 = 구현 계획 수립)

1. 라이브러리 폴더 + library.json + 기존 5챕터 마이그레이션 (§9)
2. 웹 UI (사이드바·iframe 챕터 뷰·검색·테마) — 브라우저에서 먼저 검증
3. Swift 셸 + build.sh + 폴더 감시
4. 스킬 3종 + validate.py
5. 깃허브 레포 구성 + README + examples
