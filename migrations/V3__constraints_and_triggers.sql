-- B1: terminal projects freeze descendant writes.

CREATE FUNCTION enforce_writable_project_for_experiment()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  project_state project_status;
BEGIN
  SELECT status
    INTO project_state
    FROM projects
   WHERE id = NEW.project_id;

  IF project_state IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'project % is %, so new experiments are not allowed',
      NEW.project_id, project_state;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER experiments_require_writable_project
BEFORE INSERT ON experiments
FOR EACH ROW
EXECUTE FUNCTION enforce_writable_project_for_experiment();

CREATE FUNCTION enforce_writable_project_for_measurement()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  project_state project_status;
BEGIN
  SELECT p.status
    INTO project_state
    FROM experiments e
    JOIN projects p ON p.id = e.project_id
   WHERE e.id = NEW.experiment_id;

  IF project_state IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'experiment % belongs to a % project, so new measurements are not allowed',
      NEW.experiment_id, project_state;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER measurements_require_writable_project
BEFORE INSERT ON measurements
FOR EACH ROW
EXECUTE FUNCTION enforce_writable_project_for_measurement();

-- E1: measurements are immutable after insert. TRUNCATE is intentionally not
-- guarded so the executable spec can reset the database.

CREATE FUNCTION prevent_measurement_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'measurements are immutable after insert';
END;
$$;

CREATE TRIGGER measurements_are_immutable
BEFORE UPDATE OR DELETE ON measurements
FOR EACH ROW
EXECUTE FUNCTION prevent_measurement_mutation();
