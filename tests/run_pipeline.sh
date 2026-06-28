#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@localhost:5432/lab}"

source "$(dirname "$0")/lib/test_framework.sh"
source "$(dirname "$0")/lib/sql_helpers.sh"

for case_file in "$(dirname "$0")"/cases/*.sh; do
  source "$case_file"
done

finish
