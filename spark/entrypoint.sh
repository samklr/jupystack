#!/usr/bin/env bash
# Entrypoint shared by spark-master, spark-worker, and spark-history.
# - Renders spark-defaults.conf with envsubst (so ${MINIO_ACCESS_KEY}/... get filled).
# - Starts the right daemon based on $SPARK_ROLE.
set -euo pipefail

: "${SPARK_ROLE:?SPARK_ROLE must be one of: master, worker, history}"
: "${MINIO_ACCESS_KEY:?missing MINIO_ACCESS_KEY}"
: "${MINIO_SECRET_KEY:?missing MINIO_SECRET_KEY}"

# Render configured spark-defaults.conf from the template (only ${VAR} forms are substituted).
envsubst < /opt/spark-defaults.conf.tmpl > "${SPARK_HOME}/conf/spark-defaults.conf"

# Sensible Java opts for the standalone daemons.
export SPARK_DAEMON_MEMORY="${SPARK_DAEMON_MEMORY:-512m}"

case "${SPARK_ROLE}" in
    master)
        export SPARK_MASTER_HOST="${SPARK_MASTER_HOST:-0.0.0.0}"
        exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.deploy.master.Master \
            --host "${SPARK_MASTER_HOST}" --port 7077 --webui-port 8080
        ;;
    worker)
        : "${SPARK_MASTER_URL:=spark://spark-master:7077}"
        WORKER_ARGS=( --webui-port 8081 )
        [[ -n "${SPARK_WORKER_CORES:-}" ]] && WORKER_ARGS+=( --cores "${SPARK_WORKER_CORES}" )
        [[ -n "${SPARK_WORKER_MEMORY:-}" ]] && WORKER_ARGS+=( --memory "${SPARK_WORKER_MEMORY}" )
        exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.deploy.worker.Worker \
            "${WORKER_ARGS[@]}" "${SPARK_MASTER_URL}"
        ;;
    history)
        # spark.history.fs.logDirectory comes from spark-defaults.conf (s3a://spark-logs/events).
        exec "${SPARK_HOME}/bin/spark-class" org.apache.spark.deploy.history.HistoryServer
        ;;
    *)
        echo "Unknown SPARK_ROLE='${SPARK_ROLE}' (expected master | worker | history)" >&2
        exit 1
        ;;
esac
