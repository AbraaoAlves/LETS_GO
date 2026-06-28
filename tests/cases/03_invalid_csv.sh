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
