#!/usr/bin/env bash
# End-to-end smoke test for the demo stack.
# - Verifies each service URL responds.
# - Executes the three demo notebooks headlessly inside the running jupyter container.
#
# Run after `docker compose up -d` and once `docker compose ps` shows all (healthy).
set -euo pipefail

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

check_url() {
    local name="$1" url="$2"
    if curl -fsS -o /dev/null --max-time 5 "$url"; then
        green "  OK   $name ($url)"
    else
        red   "  FAIL $name ($url)"
        return 1
    fi
}

echo "==> Health endpoints"
check_url "MinIO API"        http://localhost:9000/minio/health/ready
check_url "MinIO console"    http://localhost:9001/
check_url "Spark master"     http://localhost:8080/
check_url "Spark worker"     http://localhost:8081/
check_url "Spark history"    http://localhost:18080/
check_url "Iceberg REST"     http://localhost:8181/v1/config
check_url "JupyterLab"       http://localhost:8888/lab

echo
echo "==> Running notebooks headlessly inside the jupyter container"
# 03 is markdown-heavy (UI tour) — no need to execute. The medallion notebooks
# (04 ingest → 05 Delta → 06 Iceberg) must run in order: 04 produces the raw
# data that 05 and 06 read.
for nb in \
    00_setup_check \
    01_delta_lake_demo \
    02_iceberg_demo \
    04_ingest_open_data \
    05_etl_delta_lakehouse \
    06_etl_iceberg_lakehouse; do
    echo "  -- $nb.ipynb"
    docker compose exec -T jupyter \
        jupyter nbconvert --to notebook --execute \
            --ExecutePreprocessor.timeout=600 \
            "/home/jovyan/work/${nb}.ipynb" \
            --output "/tmp/${nb}.executed.ipynb" >/dev/null
    green "     OK"
done

green "==> All checks passed"
