#!/usr/bin/env bash
# 커밋 대상 파일에 비공개 식별자가 들어갔는지 점검한다 (설계 D6).
#
# 금칙어 목록 자체가 비공개 정보이므로 레포 안에 두지 않는다.
# 기본 위치: ~/.config/shelf/privacy-patterns.txt  (SHELF_PRIVACY_PATTERNS로 변경 가능)
# 예시 파일: .privacy-patterns.example
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PATTERNS_FILE="${SHELF_PRIVACY_PATTERNS:-$HOME/.config/shelf/privacy-patterns.txt}"

if [ ! -f "$PATTERNS_FILE" ]; then
  cat >&2 <<MSG
✗ 금칙어 목록이 없습니다: $PATTERNS_FILE

  다음으로 만드세요 (레포 밖에 둡니다):
    mkdir -p "\$(dirname "$PATTERNS_FILE")"
    cp .privacy-patterns.example "$PATTERNS_FILE"
    \$EDITOR "$PATTERNS_FILE"
MSG
  exit 2
fi

PATTERN=$(grep -v '^[[:space:]]*#' "$PATTERNS_FILE" | grep -v '^[[:space:]]*$' | paste -sd'|' -)

if [ -z "$PATTERN" ]; then
  echo "✗ 금칙어 목록이 비어 있습니다: $PATTERNS_FILE" >&2
  exit 2
fi

fail=0

# 1) 추적 중인 파일 + 추적 예정(스테이지된) 파일 검사
echo "▸ 커밋 대상 파일에서 금칙어 검사"
TRACKED=$( { git ls-files; git diff --cached --name-only --diff-filter=d; } 2>/dev/null | sort -u)

if [ -n "$TRACKED" ]; then
  HITS=$(printf '%s\n' "$TRACKED" | tr '\n' '\0' | xargs -0 grep -Iinl -E "$PATTERN" 2>/dev/null || true)
  if [ -n "$HITS" ]; then
    echo "✗ 금칙어가 포함된 파일:"
    printf '%s\n' "$HITS" | sed 's/^/    /'
    fail=1
  else
    echo "✓ 금칙어 없음 ($(printf '%s\n' "$TRACKED" | wc -l | tr -d ' ')개 파일)"
  fi
else
  echo "✓ 검사 대상 파일 없음"
fi

# 2) 아직 추적되지 않은 파일도 경고한다 (add 하기 전에 알아채도록)
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$UNTRACKED" ]; then
  WARN=$(printf '%s\n' "$UNTRACKED" | tr '\n' '\0' | xargs -0 grep -Iinl -E "$PATTERN" 2>/dev/null || true)
  if [ -n "$WARN" ]; then
    echo "⚠ 미추적 파일에 금칙어가 있습니다 — git add 하기 전에 정리하세요:"
    printf '%s\n' "$WARN" | sed 's/^/    /'
    fail=1
  fi
fi

# 3) 개인 서재로 향하는 심볼릭 링크가 추적되면 안 된다
if git ls-files --error-unmatch app/ui/library >/dev/null 2>&1; then
  echo "✗ app/ui/library 심볼릭 링크가 추적되고 있습니다 — .gitignore를 확인하세요."
  fail=1
fi

# 4) 개인 책 배치 파일이 레포 안에 들어오면 안 된다
if git ls-files --error-unmatch book-layout.json >/dev/null 2>&1; then
  echo "✗ book-layout.json이 추적되고 있습니다 — 개인 배치는 ~/.config/shelf/ 에 둡니다."
  fail=1
fi

[ "$fail" -eq 0 ] && echo "✓ 통과"
exit "$fail"
