``` shell

#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"

# Colors for nicer output
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

# Track failures
FAILURES=()

test_case() {
  local name="$1"
  echo -e "${YELLOW}==> TEST: $name${RESET}"
}

run_sql() {
  local sql="$1"
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<<"$sql"
}

assert_success() {
  local name="$1"
  local sql="$2"

  if run_sql "$sql"; then
    echo -e "${GREEN}✔ PASS:${RESET} $name"
  else
    echo -e "${RED}✘ FAIL:${RESET} $name"
    FAILURES+=("$name")
  fi
}

assert_failure() {
  local name="$1"
  local sql="$2"

  if run_sql "$sql"; then
    echo -e "${RED}✘ FAIL:${RESET} $name (unexpected success)"
    FAILURES+=("$name")
  else
    echo -e "${GREEN}✔ PASS:${RESET} $name (failure expected)"
  fi
}

finish() {
  echo
  if (( ${#FAILURES[@]} == 0 )); then
    echo -e "${GREEN}All tests passed.${RESET}"
  else
    echo -e "${RED}Failures:${RESET}"
    for f in "${FAILURES[@]}"; do
      echo " - $f"
    done
    exit 1
  fi
}


test_case "Cleaning stale test data"
assert_success "truncate tables" "
  TRUNCATE TABLE measurements, staging_measurements CASCADE;
"

test_case "Load seed data"
assert_success "seed.sql loads" "
  \\i seeds/seed.sql
"

test_case "Valid CSV ingestion"
assert_success "valid CSV import" "
BEGIN;
\\copy staging_measurements from 'samples/valid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz
FROM staging_measurements;
COMMIT;
"

test_case "Invalid CSV rejected"
assert_failure "invalid CSV import" "
BEGIN;
\\copy staging_measurements from 'samples/invalid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz
FROM staging_measurements;
COMMIT;
"


```