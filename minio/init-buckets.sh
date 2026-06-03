#!/bin/sh
# One-shot bucket bootstrap. Runs in the `minio-init` container (image: minio/mc).
# All other services wait on this container completing successfully.
set -eu

: "${MINIO_ROOT_USER:?}"
: "${MINIO_ROOT_PASSWORD:?}"

# mc needs the server reachable; the compose healthcheck on minio already gated us here.
mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

for b in spark-warehouse spark-logs raw-data; do
    mc mb --ignore-existing "local/$b"
done

# History Server expects the event-log prefix to exist.
mc mb --ignore-existing local/spark-logs/events || true

echo "Buckets ready:"
mc ls local
