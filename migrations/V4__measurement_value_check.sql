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
      ELSE TRUE
    END IS TRUE
  );
