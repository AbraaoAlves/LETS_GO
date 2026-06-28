
## 🧩 **Plan: Modular Bash Test Framework for psql**

### 🎯 **Goal**
Create a modular Bash test framework where:
- Test helper functions live in separate files
- Individual test cases live in separate files
- A main runner loads helpers and executes all tests
- The structure feels similar to imports/modules in TypeScript or Java

---

## 📁 **Directory Structure (Claude must generate these files)**

```
tests/
  run_pipeline.sh          # main runner
  lib/
    test_framework.sh      # core test helpers
    sql_helpers.sh         # optional shared SQL utilities
  cases/
    01_seed_data.sh
    02_valid_csv.sh
    03_invalid_csv.sh
```

---

## 📦 **Module Loading Requirements**

Claude must implement:

- Use `source` to import helper modules:
  - `source "$(dirname "$0")/lib/test_framework.sh"`
  - `source "$(dirname "$0")/lib/sql_helpers.sh"`

- The runner must automatically load all test case files:
  - Loop through `tests/cases/*.sh`
  - `source` each file

---

## 🧱 **test_framework.sh Requirements**

Claude must implement the following functions:

- `[run_sql]` — executes SQL via psql with `ON_ERROR_STOP=1`
- `[test_case]` — prints a test header
- `[assert_success]` — passes if SQL succeeds
- `[assert_failure]` — passes if SQL fails
- `[finish]` — prints summary and exits with non‑zero on failures

Additional requirements:
- Use color output (tput)
- Track failures in a global array

### 🧱 Example: test_framework.sh

```bash
# tests/lib/test_framework.sh

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

FAILURES=()

run_sql() {
  local sql="$1"
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<<"$sql"
}

test_case() {
  echo -e "${YELLOW}==> TEST: $1${RESET}"
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
```


---

## 🧪 **Test Case File Requirements**

Each test file must:

- Contain only test logic
- Use `test_case`, `assert_success`, and `assert_failure`
- Not define helper functions
- Not set global state except through SQL

Example structure Claude must follow:

```
test_case "Description"
assert_success "step name" "
  SQL HERE
"
```

### 🧪 Example test case file

`tests/cases/02_valid_csv.sh`

```bash
test_case "Valid CSV ingestion"

assert_success "valid CSV import" "
BEGIN;
\\copy staging_measurements from 'samples/valid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz
FROM staging_measurements;
COMMIT;
"
```

Each file contains only tests — no framework code.

---

## 🚀 **run_pipeline.sh Requirements**

Claude must implement:

- `set -euo pipefail`
- Read `DB_URL` from environment with default
- Import helper modules
- Loop through test case files and `source` them
- Call `finish` at the end


### Example: 🚀 Main runner (called by docker-compose)

`tests/run_pipeline.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"

# Import your “modules”
source "$(dirname "$0")/lib/test_framework.sh"
source "$(dirname "$0")/lib/sql_helpers.sh"

# Run all test case files
for case in "$(dirname "$0")"/cases/*.sh; do
  source "$case"
done

finish
```

This is your “test runner”, similar to Jest or JUnit.



---

## 🐳 **Docker Compose Integration Requirements**

Claude must ensure:

- `run_pipeline.sh` can be invoked as the container command
- No hardcoded paths outside `/tests`

### Example:

```yaml
services:
  test-runner:
    build: .
    command: ["bash", "tests/run_pipeline.sh"]
```

Works perfectly.


---

## 🔧 **Optional Enhancements (Claude may include)**

- A `before_all` and `after_all` hook system
- A `before_each` and `after_each` system
- A helper for running `.sql` files (`run_file`)
- Assertions for row counts or query results

---

## 📝 **Output Format Requirements for Claude**

Claude must output:

1. All file contents separately  
2. With clear file headers, e.g.:

```
# File: tests/lib/test_framework.sh
<content>
```

3. No extra commentary beyond what is needed  
4. No placeholders — full working code




## 🧩 Clean project structure

A simple, scalable layout:

```
tests/
  run_pipeline.sh          # main entry point (called by docker-compose)
  lib/
    test_framework.sh      # assert_success, assert_failure, run_sql, etc.
    sql_helpers.sh         # optional: reusable SQL snippets
  cases/
    01_seed_data.sh
    02_valid_csv.sh
    03_invalid_csv.sh
```

This gives you:

- A **test framework** file (like a TypeScript module)
- Multiple **test case files** (like Java test classes)
- A **main runner** that loads everything and executes tests

---

## 📦 Importing modules (Bash-style)

Bash’s equivalent of “import” is:

```bash
source tests/lib/test_framework.sh
source tests/lib/sql_helpers.sh
```

This is the closest analogue to TypeScript’s `import { foo } from './module'`.

---

## 🧱 Example: test_framework.sh

```bash
# tests/lib/test_framework.sh

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

FAILURES=()

run_sql() {
  local sql="$1"
  psql "$DB_URL" -v ON_ERROR_STOP=1 <<<"$sql"
}

test_case() {
  echo -e "${YELLOW}==> TEST: $1${RESET}"
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
```

---

## 🧪 Example test case file

`tests/cases/02_valid_csv.sh`

```bash
test_case "Valid CSV ingestion"

assert_success "valid CSV import" "
BEGIN;
\\copy staging_measurements from 'samples/valid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz
FROM staging_measurements;
COMMIT;
"
```

Each file contains only tests — no framework code.

---

## 🚀 Main runner (called by docker-compose)

`tests/run_pipeline.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"

# Import your “modules”
source "$(dirname "$0")/lib/test_framework.sh"
source "$(dirname "$0")/lib/sql_helpers.sh"

# Run all test case files
for case in "$(dirname "$0")"/cases/*.sh; do
  source "$case"
done

finish
```

This is your “test runner”, similar to Jest or JUnit.

---

## 🐳 Using it in docker-compose

```yaml
services:
  test-runner:
    build: .
    command: ["bash", "tests/run_pipeline.sh"]
```

Works perfectly.

---

## 🧠 Why this structure works

- **Modular**: helpers live in their own file  
- **Readable**: test files contain only tests  
- **Composable**: add more test files without touching the runner  
- **Docker-friendly**: everything is just Bash + psql  
- **Scalable**: you can add fixtures, before_each, after_each, etc.

