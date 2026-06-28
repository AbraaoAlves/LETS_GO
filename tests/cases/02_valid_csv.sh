test_case "Valid CSV ingestion"
assert_success "valid researchers CSV" ingest_researchers samples/researchers_valid.csv
assert_success "valid projects CSV" ingest_projects samples/projects_valid.csv
assert_success "valid project_researchers CSV" ingest_project_researchers samples/project_researchers_valid.csv
assert_success "valid samples CSV" ingest_samples samples/samples_valid.csv
assert_success "valid experiments CSV" ingest_experiments samples/experiments_valid.csv
assert_success "register new measurement type as data" register_spectral_scan
assert_success "valid measurements CSV" ingest_measurements samples/measurements_valid.csv
assert_success "demo data assertions" assert_demo_queries
