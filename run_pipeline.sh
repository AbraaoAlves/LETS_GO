#!/usr/bin/env bash
set -euo pipefail

# Executable spec for A0: CSV rows go through TEMP staging tables, and
# PostgreSQL accepts or rejects them through constraints/triggers.

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"
FAILURES=()

test_case() {
  printf '\n==> %s\n' "$1"
}

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1"
  FAILURES+=("$1")
}

assert_success() {
  local name="$1"
  shift

  if "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_failure() {
  local name="$1"
  shift

  if "$@"; then
    fail "$name (unexpected success)"
  else
    pass "$name"
  fi
}

psql_run() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 "$@"
}

seed_database() {
  psql_run -f seeds/seed.sql
}

register_spectral_scan() {
  psql_run <<'SQL'
INSERT INTO measurement_types (type, description)
VALUES ('spectral_scan', 'Raw spectral scan payload accepted before shape hardening')
ON CONFLICT (type) DO NOTHING;
SQL
}

ingest_researchers() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_researchers (
  name text,
  email text,
  role text
);
\\copy staging_researchers FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO researchers (name, email, role)
SELECT name, email, role::researcher_role
FROM staging_researchers;
COMMIT;
SQL
}

ingest_projects() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_projects (
  title text,
  description text,
  status text
);
\\copy staging_projects FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO projects (title, description, status)
SELECT title, description, status::project_status
FROM staging_projects;
COMMIT;
SQL
}

ingest_project_researchers() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_project_researchers (
  project_title text,
  researcher_email text
);
\\copy staging_project_researchers FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO project_researchers (project_id, researcher_id)
SELECT
  (SELECT id FROM projects WHERE title = s.project_title),
  (SELECT id FROM researchers WHERE email = s.researcher_email)
FROM staging_project_researchers s;
COMMIT;
SQL
}

ingest_samples() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_samples (
  sample_code text,
  sample_type text,
  collected_at text,
  storage_location text,
  parent_sample_code text
);
\\copy staging_samples FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO samples (
  sample_code,
  sample_type,
  collected_at,
  storage_location,
  parent_sample_id
)
SELECT
  sample_code,
  sample_type,
  collected_at::timestamptz,
  storage_location,
  CASE
    WHEN NULLIF(parent_sample_code, '') IS NULL THEN NULL
    ELSE COALESCE((SELECT id FROM samples WHERE sample_code = s.parent_sample_code), 0)
  END
FROM staging_samples s;
COMMIT;
SQL
}

ingest_experiments() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_experiments (
  project_title text,
  title text,
  hypothesis text,
  status text,
  start_date text,
  end_date text,
  predecessor_project_title text,
  predecessor_experiment_title text,
  lead_researcher_email text
);
\\copy staging_experiments FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO experiments (
  project_id,
  title,
  hypothesis,
  status,
  start_date,
  end_date,
  predecessor_experiment_id,
  lead_researcher_id
)
SELECT
  (SELECT id FROM projects WHERE title = s.project_title),
  title,
  hypothesis,
  status::experiment_status,
  start_date::date,
  NULLIF(end_date, '')::date,
  CASE
    WHEN NULLIF(predecessor_project_title, '') IS NULL
      AND NULLIF(predecessor_experiment_title, '') IS NULL THEN NULL
    ELSE COALESCE((
      SELECT e.id
      FROM experiments e
      JOIN projects p ON p.id = e.project_id
      WHERE p.title = s.predecessor_project_title
        AND e.title = s.predecessor_experiment_title
    ), 0)
  END,
  (SELECT id FROM researchers WHERE email = s.lead_researcher_email)
FROM staging_experiments s;
COMMIT;
SQL
}

ingest_measurements() {
  local file="$1"
  psql_run <<SQL
BEGIN;
CREATE TEMP TABLE staging_measurements (
  experiment_project_title text,
  experiment_title text,
  sample_code text,
  measurement_type text,
  numeric_value text,
  unit text,
  categorical_value text,
  note text,
  recorded_at text,
  notes text,
  researcher_email text
);
\\copy staging_measurements FROM '$file' WITH (FORMAT csv, HEADER true)
INSERT INTO measurements (
  experiment_id,
  sample_id,
  measurement_type,
  value,
  recorded_at,
  notes,
  researcher_id
)
SELECT
  (
    SELECT e.id
    FROM experiments e
    JOIN projects p ON p.id = e.project_id
    WHERE p.title = s.experiment_project_title
      AND e.title = s.experiment_title
  ),
  CASE
    WHEN NULLIF(sample_code, '') IS NULL THEN NULL
    ELSE COALESCE((SELECT id FROM samples WHERE sample_code = s.sample_code), 0)
  END,
  measurement_type,
  CASE measurement_type
    WHEN 'numeric' THEN jsonb_build_object('value', numeric_value::numeric, 'unit', unit)
    WHEN 'categorical' THEN jsonb_build_object('value', categorical_value)
    WHEN 'text' THEN jsonb_build_object('note', note)
    ELSE to_jsonb(note)
  END,
  recorded_at::timestamptz,
  notes,
  (SELECT id FROM researchers WHERE email = s.researcher_email)
FROM staging_measurements s;
COMMIT;
SQL
}

reject_experiment_self_predecessor() {
  psql_run <<'SQL'
BEGIN;
INSERT INTO experiments (
  id,
  project_id,
  title,
  hypothesis,
  status,
  start_date,
  predecessor_experiment_id,
  lead_researcher_id
) OVERRIDING SYSTEM VALUE VALUES (
  9000,
  (SELECT id FROM projects WHERE title = 'Project Alpha'),
  'Impossible Self Predecessor',
  'Direct self reference must fail',
  'planning',
  '2024-04-01',
  9000,
  (SELECT id FROM researchers WHERE email = 'alice@example.org')
);
COMMIT;
SQL
}

reject_numeric_json_string() {
  psql_run <<'SQL'
BEGIN;
INSERT INTO measurements (
  experiment_id,
  sample_id,
  measurement_type,
  value,
  recorded_at,
  notes,
  researcher_id
) VALUES (
  (
    SELECT e.id
      FROM experiments e
      JOIN projects p ON p.id = e.project_id
     WHERE p.title = 'Project Alpha'
       AND e.title = 'Alpha Baseline'
  ),
  (SELECT id FROM samples WHERE sample_code = 'S-ALPHA-001'),
  'numeric',
  '{"value": "12.4", "unit": "C"}'::jsonb,
  '2024-01-12T13:45:00Z',
  'numeric value stored as JSON string must fail',
  (SELECT id FROM researchers WHERE email = 'ben@example.org')
);
COMMIT;
SQL
}

update_seed_measurement() {
  psql_run <<'SQL'
UPDATE measurements
   SET notes = 'mutated'
 WHERE notes = 'seed immutable measurement';
SQL
}

delete_seed_measurement() {
  psql_run <<'SQL'
DELETE FROM measurements
 WHERE notes = 'seed immutable measurement';
SQL
}

assert_demo_queries() {
  psql_run <<'SQL'
DO $$
BEGIN
  IF (SELECT count(*) FROM researchers) < 5 THEN
    RAISE EXCEPTION 'expected seeded and CSV researchers';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM measurements
    WHERE measurement_type = 'spectral_scan'
  ) THEN
    RAISE EXCEPTION 'expected registered unknown measurement type';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM measurements
    WHERE sample_id IS NULL
      AND measurement_type = 'text'
  ) THEN
    RAISE EXCEPTION 'expected experiment-level measurement without sample';
  END IF;
END $$;
SQL
}

finish() {
  printf '\n'
  if ((${#FAILURES[@]} == 0)); then
    printf 'All pipeline assertions passed.\n'
  else
    printf 'Pipeline failures:\n'
    printf ' - %s\n' "${FAILURES[@]}"
    exit 1
  fi
}

test_case "Reset and seed trusted baseline"
assert_success "seed.sql loads" seed_database

test_case "Valid CSV ingestion"
assert_success "valid researchers CSV" ingest_researchers samples/researchers_valid.csv
assert_success "valid projects CSV" ingest_projects samples/projects_valid.csv
assert_success "valid project_researchers CSV" ingest_project_researchers samples/project_researchers_valid.csv
assert_success "valid samples CSV" ingest_samples samples/samples_valid.csv
assert_success "valid experiments CSV" ingest_experiments samples/experiments_valid.csv
assert_success "register new measurement type as data" register_spectral_scan
assert_success "valid measurements CSV" ingest_measurements samples/measurements_valid.csv
assert_success "demo data assertions" assert_demo_queries

test_case "Invalid CSV rows rejected by database invariants"
assert_failure "researcher role enum rejects postdoc" ingest_researchers samples/researchers_invalid_role.csv
assert_failure "researcher name is required" ingest_researchers samples/researchers_invalid_name.csv
assert_failure "project status enum rejects archived" ingest_projects samples/projects_invalid_status.csv
assert_failure "project title is required" ingest_projects samples/projects_invalid_title.csv
assert_failure "project researcher FK rejects missing researcher" ingest_project_researchers samples/project_researchers_invalid_email.csv
assert_failure "project researcher PK rejects duplicate pair" ingest_project_researchers samples/project_researchers_invalid_duplicate.csv
assert_failure "sample code uniqueness rejects duplicate" ingest_samples samples/samples_invalid_duplicate_code.csv
assert_failure "sample parent FK rejects missing parent" ingest_samples samples/samples_invalid_parent.csv
assert_failure "experiment end date cannot precede start" ingest_experiments samples/experiments_invalid_end_before_start.csv
assert_failure "experiment project FK rejects missing project" ingest_experiments samples/experiments_invalid_project.csv
assert_failure "completed project rejects new experiment" ingest_experiments samples/experiments_invalid_frozen_project.csv
assert_failure "numeric measurement unit is required by CHECK" ingest_measurements samples/measurements_invalid_missing_unit.csv
assert_failure "numeric measurement cast rejects bad number" ingest_measurements samples/measurements_invalid_bad_numeric.csv
assert_failure "measurement experiment FK rejects missing experiment" ingest_measurements samples/measurements_invalid_experiment.csv
assert_failure "completed project rejects new measurement" ingest_measurements samples/measurements_invalid_frozen_project.csv

test_case "Direct database invariants that CSV identity cannot express"
assert_failure "experiment cannot directly follow itself" reject_experiment_self_predecessor
assert_failure "numeric value cannot be a JSON string" reject_numeric_json_string
assert_failure "measurement UPDATE is rejected" update_seed_measurement
assert_failure "measurement DELETE is rejected" delete_seed_measurement

finish
