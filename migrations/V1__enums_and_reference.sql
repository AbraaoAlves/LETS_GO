-- A1/F1/B1: database-owned domains and the measurement type registry.

CREATE TYPE researcher_role AS ENUM (
  'principal_investigator',
  'lab_technician',
  'graduate_student'
);

CREATE TYPE project_status AS ENUM (
  'planning',
  'active',
  'completed',
  'cancelled'
);

CREATE TYPE experiment_status AS ENUM (
  'planning',
  'active',
  'completed',
  'cancelled'
);

CREATE TABLE measurement_types (
  type text PRIMARY KEY,
  description text NOT NULL
);

INSERT INTO measurement_types (type, description) VALUES
  ('numeric', 'Numeric reading with a unit'),
  ('categorical', 'Categorical outcome such as pass/fail'),
  ('text', 'Free-text observation');
