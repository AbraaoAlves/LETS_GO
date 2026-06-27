-- A1: known measurement payload shapes are enforced by PostgreSQL.

ALTER TABLE measurements
  ADD CONSTRAINT measurements_value_shape CHECK (
    CASE measurement_type
      WHEN 'numeric' THEN
        jsonb_typeof(value->'value') = 'number'
        AND jsonb_typeof(value->'unit') = 'string'
      WHEN 'categorical' THEN
        jsonb_typeof(value->'value') = 'string'
      WHEN 'text' THEN
        jsonb_typeof(value->'note') = 'string'
      -- Intentional fail-open: a newly registered measurement_type is accepted
      -- with any payload until a later migration adds its shape branch here.
      -- This is the A1 extensibility trade-off, exercised by the spectral_scan
      -- case in run_pipeline.sh. Do not switch to ELSE FALSE.
      ELSE TRUE
    END IS TRUE
  );
