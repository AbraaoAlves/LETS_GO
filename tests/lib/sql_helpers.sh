seed_database() {
  run_sql -f seeds/seed.sql
}

register_spectral_scan() {
  run_sql <<'SQL'
INSERT INTO measurement_types (type, description)
VALUES ('spectral_scan', 'Raw spectral scan payload accepted before shape hardening')
ON CONFLICT (type) DO NOTHING;
SQL
}

ingest_researchers() {
  local file="$1"
  run_sql <<SQL
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
  run_sql <<SQL
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
  run_sql <<SQL
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
  run_sql <<SQL
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
  run_sql <<SQL
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
  run_sql <<SQL
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
  run_sql <<'SQL'
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
  run_sql <<'SQL'
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
  run_sql <<'SQL'
UPDATE measurements
   SET notes = 'mutated'
 WHERE notes = 'seed immutable measurement';
SQL
}

delete_seed_measurement() {
  run_sql <<'SQL'
DELETE FROM measurements
 WHERE notes = 'seed immutable measurement';
SQL
}

assert_demo_queries() {
  run_sql <<'SQL'
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

  IF NOT EXISTS (
    SELECT 1
    FROM measurements
    WHERE sample_id IS NOT NULL
    GROUP BY sample_id
    HAVING count(DISTINCT experiment_id) > 1
  ) THEN
    RAISE EXCEPTION 'expected a sample used across multiple experiments';
  END IF;
END $$;
SQL
}
