#!/usr/bin/env bash
# Submit a PySpark job to a remote Kubernetes cluster from the host.
#
# Required env vars:
#   K8S_API            e.g. https://my-cluster.example.com:6443
#   SPARK_IMAGE        Spark image reachable from the cluster (must contain the same JARs as ./spark)
#   MINIO_ACCESS_KEY   S3A creds (same as docker-compose .env)
#   MINIO_SECRET_KEY
#   S3_ENDPOINT        Where MinIO/S3 is reachable from inside the cluster (NOT http://minio:9000)
#
# Optional:
#   K8S_NAMESPACE      (default: default)
#   K8S_SA             (default: spark)
#   JOB_NAME           (default: demo-job)
#
# Usage:  scripts/k8s-spark-submit.sh path/to/job.py [extra spark-submit args...]
#
# Requires `spark-submit` on PATH (use any matching Spark 3.5.x install) and a valid kubeconfig.
set -euo pipefail

: "${K8S_API:?set K8S_API to https://<host>:<port>}"
: "${SPARK_IMAGE:?set SPARK_IMAGE to the cluster-side Spark image}"
: "${MINIO_ACCESS_KEY:?}"
: "${MINIO_SECRET_KEY:?}"
: "${S3_ENDPOINT:?set S3_ENDPOINT to the S3/MinIO URL reachable from the cluster}"

JOB_FILE="${1:?usage: $0 <job.py> [extra spark-submit args...]}"
shift || true

K8S_NAMESPACE="${K8S_NAMESPACE:-default}"
K8S_SA="${K8S_SA:-spark}"
JOB_NAME="${JOB_NAME:-demo-job}"

exec spark-submit \
    --master "k8s://${K8S_API}" \
    --deploy-mode cluster \
    --name "${JOB_NAME}" \
    --conf "spark.kubernetes.container.image=${SPARK_IMAGE}" \
    --conf "spark.kubernetes.namespace=${K8S_NAMESPACE}" \
    --conf "spark.kubernetes.authenticate.driver.serviceAccountName=${K8S_SA}" \
    --conf "spark.hadoop.fs.s3a.endpoint=${S3_ENDPOINT}" \
    --conf "spark.hadoop.fs.s3a.access.key=${MINIO_ACCESS_KEY}" \
    --conf "spark.hadoop.fs.s3a.secret.key=${MINIO_SECRET_KEY}" \
    --conf "spark.hadoop.fs.s3a.path.style.access=true" \
    --conf "spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem" \
    "$@" \
    "${JOB_FILE}"
