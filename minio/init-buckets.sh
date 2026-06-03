#!/bin/sh
# One-shot bucket bootstrap. Runs in the `minio-init` container (image: minio/mc).
# All other services wait on this container completing successfully.
set -eu

: "${MINIO_ROOT_USER:?}"
: "${MINIO_ROOT_PASSWORD:?}"

# Wait until MinIO is actually serving (compose only knows the container started).
echo "Waiting for MinIO to accept connections..."
for i in $(seq 1 60); do
    if mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1 \
        && mc ready local >/dev/null 2>&1; then
        echo "  ready after ${i}s"
        break
    fi
    sleep 1
    if [ "$i" = "60" ]; then
        echo "MinIO did not become ready within 60s" >&2
        exit 1
    fi
done

for b in spark-warehouse spark-logs raw-data; do
    mc mb --ignore-existing "local/$b"
done

# Spark History Server expects this prefix to exist; create a zero-byte marker.
echo "" | mc pipe "local/spark-logs/events/.keep" || true

echo "Buckets ready:"
mc ls local
