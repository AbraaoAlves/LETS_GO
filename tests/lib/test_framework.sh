RED=$(tput setaf 1 2>/dev/null || printf '')
GREEN=$(tput setaf 2 2>/dev/null || printf '')
YELLOW=$(tput setaf 3 2>/dev/null || printf '')
RESET=$(tput sgr0 2>/dev/null || printf '')

FAILURES=()

run_sql() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 "$@"
}

test_case() {
  printf '\n%s==> TEST: %s%s\n' "$YELLOW" "$1" "$RESET"
}

assert_success() {
  local name="$1"
  shift
  if "$@"; then
    printf '%s✔ PASS:%s %s\n' "$GREEN" "$RESET" "$name"
  else
    printf '%s✘ FAIL:%s %s\n' "$RED" "$RESET" "$name"
    FAILURES+=("$name")
  fi
}

assert_failure() {
  local name="$1"
  shift
  if "$@"; then
    printf '%s✘ FAIL:%s %s (unexpected success)\n' "$RED" "$RESET" "$name"
    FAILURES+=("$name")
  else
    printf '%s✔ PASS:%s %s (failure expected)\n' "$GREEN" "$RESET" "$name"
  fi
}

finish() {
  printf '\n'
  if (( ${#FAILURES[@]} == 0 )); then
    printf '%sAll pipeline assertions passed.%s\n' "$GREEN" "$RESET"
  else
    printf '%sPipeline failures:%s\n' "$RED" "$RESET"
    printf ' - %s\n' "${FAILURES[@]}"
    exit 1
  fi
}
