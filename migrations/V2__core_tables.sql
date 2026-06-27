-- Core tables for the CSV ingestion workflow. Assumption references are from
-- QUESTIONS_ASSUMPTIONS.md.

CREATE TABLE researchers (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  name text NOT NULL,
  email text NOT NULL UNIQUE,
  role researcher_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE projects (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title text NOT NULL,
  description text NOT NULL,
  status project_status NOT NULL DEFAULT 'planning',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE project_researchers (
  project_id bigint NOT NULL REFERENCES projects(id),
  researcher_id bigint NOT NULL REFERENCES researchers(id),
  PRIMARY KEY (project_id, researcher_id)
);

CREATE TABLE samples (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sample_code text NOT NULL UNIQUE,
  sample_type text NOT NULL,
  collected_at timestamptz NOT NULL,
  storage_location text,
  parent_sample_id bigint REFERENCES samples(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT samples_no_direct_self_parent
    CHECK (parent_sample_id IS NULL OR parent_sample_id <> id)
);

CREATE TABLE experiments (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  project_id bigint NOT NULL REFERENCES projects(id),
  title text NOT NULL,
  hypothesis text NOT NULL,
  status experiment_status NOT NULL DEFAULT 'planning',
  start_date date NOT NULL,
  end_date date,
  predecessor_experiment_id bigint REFERENCES experiments(id),
  lead_researcher_id bigint NOT NULL REFERENCES researchers(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT experiments_end_not_before_start
    CHECK (end_date IS NULL OR end_date >= start_date),
  CONSTRAINT experiments_no_direct_self_predecessor
    CHECK (predecessor_experiment_id IS NULL OR predecessor_experiment_id <> id)
);

CREATE TABLE measurements (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  experiment_id bigint NOT NULL REFERENCES experiments(id),
  sample_id bigint REFERENCES samples(id),
  measurement_type text NOT NULL REFERENCES measurement_types(type),
  value jsonb NOT NULL,
  recorded_at timestamptz NOT NULL,
  notes text,
  researcher_id bigint NOT NULL REFERENCES researchers(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX project_researchers_researcher_id_idx
  ON project_researchers (researcher_id);

CREATE INDEX samples_parent_sample_id_idx
  ON samples (parent_sample_id);

CREATE INDEX experiments_project_id_idx
  ON experiments (project_id);

CREATE INDEX experiments_predecessor_experiment_id_idx
  ON experiments (predecessor_experiment_id);

CREATE INDEX experiments_lead_researcher_id_idx
  ON experiments (lead_researcher_id);

CREATE INDEX measurements_experiment_id_idx
  ON measurements (experiment_id);

CREATE INDEX measurements_sample_id_idx
  ON measurements (sample_id);

CREATE INDEX measurements_measurement_type_idx
  ON measurements (measurement_type);

CREATE INDEX measurements_researcher_id_idx
  ON measurements (researcher_id);
