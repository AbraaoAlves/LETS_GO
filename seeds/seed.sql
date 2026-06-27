-- Trusted baseline for the executable CSV spec.
-- Alpha: active FK target plus immutable measurement.
-- Beta: created writable, given an experiment, then completed for freeze tests.
-- Gamma: planning project positive control for B1.

TRUNCATE TABLE
  project_researchers,
  measurements,
  experiments,
  samples,
  projects,
  researchers
RESTART IDENTITY CASCADE;

INSERT INTO researchers (name, email, role) VALUES
  ('Dr. Alice Nguyen', 'alice@example.org', 'principal_investigator'),
  ('Ben Torres', 'ben@example.org', 'lab_technician'),
  ('Carla Silva', 'carla@example.org', 'graduate_student');

INSERT INTO projects (title, description, status) VALUES
  ('Project Alpha', 'Active baseline project for valid imports', 'active'),
  ('Project Beta', 'Frozen project used to prove terminal write blocking', 'active'),
  ('Project Gamma', 'Planning project used to prove planning accepts writes', 'planning');

INSERT INTO project_researchers (project_id, researcher_id)
SELECT p.id, r.id
FROM projects p
JOIN researchers r ON r.email IN ('alice@example.org', 'ben@example.org')
WHERE p.title = 'Project Alpha';

INSERT INTO project_researchers (project_id, researcher_id)
SELECT p.id, r.id
FROM projects p
JOIN researchers r ON r.email = 'alice@example.org'
WHERE p.title = 'Project Beta';

INSERT INTO project_researchers (project_id, researcher_id)
SELECT p.id, r.id
FROM projects p
JOIN researchers r ON r.email = 'carla@example.org'
WHERE p.title = 'Project Gamma';

INSERT INTO samples (sample_code, sample_type, collected_at, storage_location, parent_sample_id)
VALUES
  ('S-ALPHA-001', 'blood', '2024-01-10T09:00:00Z', 'Freezer A1', NULL),
  (
    'S-ALPHA-001-A',
    'blood aliquot',
    '2024-01-10T10:00:00Z',
    'Freezer A2',
    (SELECT id FROM samples WHERE sample_code = 'S-ALPHA-001')
  ),
  ('S-BETA-001', 'soil', '2024-02-11T08:00:00Z', 'Shelf B1', NULL);

INSERT INTO experiments (
  project_id,
  title,
  hypothesis,
  status,
  start_date,
  end_date,
  predecessor_experiment_id,
  lead_researcher_id
) VALUES
  (
    (SELECT id FROM projects WHERE title = 'Project Alpha'),
    'Alpha Baseline',
    'Baseline concentration stays within expected range',
    'active',
    '2024-01-12',
    NULL,
    NULL,
    (SELECT id FROM researchers WHERE email = 'alice@example.org')
  ),
  (
    (SELECT id FROM projects WHERE title = 'Project Alpha'),
    'Alpha Follow-up',
    'Replicate the baseline with an aliquot',
    'planning',
    '2024-01-15',
    NULL,
    (SELECT id FROM experiments WHERE title = 'Alpha Baseline'),
    (SELECT id FROM researchers WHERE email = 'carla@example.org')
  ),
  (
    (SELECT id FROM projects WHERE title = 'Project Beta'),
    'Beta Frozen Seed',
    'Experiment created before the project was completed',
    'completed',
    '2024-02-12',
    '2024-02-20',
    NULL,
    (SELECT id FROM researchers WHERE email = 'alice@example.org')
  );

INSERT INTO measurements (
  experiment_id,
  sample_id,
  measurement_type,
  value,
  recorded_at,
  notes,
  researcher_id
) VALUES (
  (SELECT id FROM experiments WHERE title = 'Alpha Baseline'),
  (SELECT id FROM samples WHERE sample_code = 'S-ALPHA-001'),
  'numeric',
  '{"value": 4.2, "unit": "mg/L"}'::jsonb,
  '2024-01-12T12:00:00Z',
  'seed immutable measurement',
  (SELECT id FROM researchers WHERE email = 'ben@example.org')
);

UPDATE projects
   SET status = 'completed'
 WHERE title = 'Project Beta';
