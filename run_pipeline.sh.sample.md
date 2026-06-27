``` shell

#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"

echo "==> Cleaning stale test data (Idempotency)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -c "TRUNCATE TABLE measurements, staging_measurements CASCADE;"

echo "==> Load fresh seed data"
psql "$DB_URL" -v ON_ERROR_STOP=1 -f seeds/seed.sql

echo "==> Import valid CSV (Happy Path)"
psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
\copy staging_measurements from 'samples/valid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz FROM staging_measurements;
COMMIT;
SQL
echo "Success: Valid CSV ingested."

echo "==> Import invalid CSV (Defensive Check)"
if psql "$DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
\copy staging_measurements from 'samples/invalid_measurements.csv' with (format csv, header true);
INSERT INTO measurements (experiment_id, sample_id, measurement_kind, payload, recorded_at)
SELECT experiment_id, sample_id, measurement_kind, payload::jsonb, recorded_at::timestamptz FROM staging_measurements;
COMMIT;
SQL
then
  echo "CRITICAL ERROR: Unexpected success. Invalid data bypassed constraints!"
  exit 1
else
  echo "Excellent: Invalid CSV was successfully rejected by database guardrails."
fi
```