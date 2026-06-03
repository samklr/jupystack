# How-to recipes

Short, copy-pasteable tasks. Assumes you've done the quick-start in the README (`cp .env.example .env && docker compose up -d --build`).

## 1. Run the demo notebooks (the golden path)

1. Open http://localhost:8888/lab — no token by default.
2. In the file browser open `00_setup_check.ipynb`.
3. Run all cells (`Cell → Run All`). The last cell should print bucket names from `boto3.list_buckets()`.
4. Repeat for `01_delta_lake_demo.ipynb` → `02_iceberg_demo.ipynb` → `03_spark_ui_guide.ipynb`.
5. Then the open-data pipeline (run in this exact order — 05 and 06 read what 04 wrote):
   - `04_ingest_open_data.ipynb` — pulls MovieLens (~1 MB CSV bundle) and 7 days of Wikipedia pageviews (~400 KB JSON) into `s3a://raw-data/`.
   - `05_etl_delta_lakehouse.ipynb` — bronze → silver → gold in Delta, ending with a `MERGE INTO` and `DESCRIBE HISTORY`.
   - `06_etl_iceberg_lakehouse.ipynb` — same pipeline in Iceberg, ending with snapshot-id time travel.
6. Watch each running job in the master UI at http://localhost:8080. After a notebook finishes (stops its `SparkSession`), refresh http://localhost:18080 — the app appears in the History Server within ~15 s.

Smoke-test all of them headlessly (CI-style):

```bash
./scripts/test-stack.sh
```

### Where the open data comes from

| Notebook | Dataset | Format | Source URL | Notes |
|---|---|---|---|---|
| `04` | MovieLens `ml-latest-small` | 4 CSVs in a ZIP | https://files.grouplens.org/datasets/movielens/ml-latest-small.zip | Stable since 2019. ~100K ratings, ~10K movies. |
| `04` | Wikipedia top-1000 pageviews | JSON per day | https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia/all-access/YYYY/MM/DD | Wikimedia REST API; requires a `User-Agent` header. Notebook fetches 7 consecutive days (2025-01-01 → 2025-01-07) so re-runs are deterministic. |

Both are public, no API key required.

## 2. Connect host-side PySpark to the cluster

Useful when you'd rather use your local IDE than the in-container Lab.

```bash
pip install pyspark==3.5.8
```

```python
from pyspark.sql import SparkSession

spark = (
    SparkSession.builder
        .master("spark://localhost:7077")
        .appName("from-host")
        .config("spark.hadoop.fs.s3a.endpoint", "http://localhost:9000")
        .config("spark.hadoop.fs.s3a.access.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.secret.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        # Pull the same JAR set the cluster has:
        .config("spark.jars.packages",
                "org.apache.hadoop:hadoop-aws:3.3.4,"
                "io.delta:delta-spark_2.12:3.2.0,"
                "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.6.1,"
                "org.apache.iceberg:iceberg-aws-bundle:1.6.1")
        .getOrCreate()
)
spark.read.parquet("s3a://raw-data/setup-check/").show()
```

If the worker can't connect back to your host driver, set `spark.driver.host=host.docker.internal` (macOS / Windows) or your machine's LAN IP (Linux).

## 3. Submit a job to a remote Kubernetes cluster

Pre-flight:

```bash
kubectl create serviceaccount spark
kubectl create clusterrolebinding spark-role \
    --clusterrole=edit \
    --serviceaccount=default:spark
```

Build and push a Spark image to a registry your cluster can pull from — use this repo's `spark/Dockerfile` as the base.

Then on the host (not in a container):

```bash
export K8S_API=https://my-cluster.example.com:6443
export SPARK_IMAGE=ghcr.io/my-org/spark:3.5.8
export S3_ENDPOINT=https://s3.eu-west-1.amazonaws.com   # cluster-reachable
export MINIO_ACCESS_KEY=AKIA...
export MINIO_SECRET_KEY=...

./scripts/k8s-spark-submit.sh path/to/job.py
```

Override defaults via `K8S_NAMESPACE`, `K8S_SA`, `JOB_NAME` env vars. Anything after the `<job.py>` argument is passed straight to `spark-submit`:

```bash
./scripts/k8s-spark-submit.sh job.py \
    --conf spark.executor.instances=4 \
    --conf spark.executor.memory=4g
```

## 4. Use real AWS S3 instead of MinIO

Edit `.env`:

```bash
MINIO_ACCESS_KEY=AKIA...           # real IAM access key
MINIO_SECRET_KEY=...               # real secret
```

In `spark/spark-defaults.conf`:
- Change `spark.hadoop.fs.s3a.endpoint` to `https://s3.<region>.amazonaws.com`.
- Set `spark.hadoop.fs.s3a.path.style.access` to `false`.
- Change `spark.sql.catalog.iceberg.s3.endpoint` to the same regional URL.
- Update the two `*.region` values to your real AWS region (e.g. `eu-west-1`).
- Point `spark.eventLog.dir` / `spark.history.fs.logDirectory` at an existing S3 prefix you own.
- Change `spark.sql.catalog.iceberg.warehouse` to a real bucket you own.

In `iceberg-rest/catalog.env`:
- Set `CATALOG_WAREHOUSE` to the same real bucket.
- Set `CATALOG_S3_ENDPOINT` to the regional URL, `CATALOG_S3_PATH__STYLE__ACCESS=false`.
- Set `AWS_REGION=<your-region>`.

Then:

```bash
docker compose build spark-master jupyter
docker compose up -d
```

The MinIO + minio-init services can be deleted from `docker-compose.yml` once you no longer need them.

## 5. Add a new bucket

```bash
docker compose exec -T minio-init sh -c "mc alias set local http://minio:9000 \$MINIO_ROOT_USER \$MINIO_ROOT_PASSWORD && mc mb local/<bucket-name>"
```

For permanent buckets, append the bucket name to `minio/init-buckets.sh` so it re-creates on every `compose up`.

## 6. Open a Spark shell inside a worker

Handy for ad-hoc PySpark or `spark-sql` outside the notebook:

```bash
docker compose exec spark-worker /opt/spark/bin/pyspark \
    --master spark://spark-master:7077 \
    --conf spark.eventLog.enabled=true
```

`spark-defaults.conf` is already loaded inside the container, so Delta/Iceberg/S3A configs are present.

## 7. Inspect the History Server

1. Stop the SparkSession in your notebook (`spark.stop()`) so the event log uploads.
2. Wait ~15 s; open http://localhost:18080.
3. Click an app name → drill into Jobs / Stages / SQL / Executors.
4. The list is populated from `s3a://spark-logs/events/`. You can browse the raw `.json`-on-disk events via the MinIO console at http://localhost:9001.

## 8. Reset the stack (wipe everything)

```bash
docker compose down -v       # -v drops named volumes (minio-data, iceberg-data)
docker compose up -d --build
```

Notebook outputs in `jupyter/notebooks/` survive because they live on the host bind mount, not in a volume.

## 9. Tail logs for one service

```bash
docker compose logs -f spark-worker
docker compose logs -f --tail=100 jupyter
```

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `PYTHON_VERSION_MISMATCH` in a Spark task | Driver / worker Python minor versions differ | Both images pin Python 3.11; verify with `docker compose exec spark-worker python3 --version` and `docker compose exec jupyter python --version`. Rebuild if mismatched. |
| `Unable to load region from any of the providers` (Iceberg) | AWS SDK v2 needs a region even for MinIO | `spark.sql.catalog.iceberg.client.region` and `.s3.region` are set in `spark-defaults.conf` — confirm with `docker compose exec spark-worker cat /opt/spark/conf/spark-defaults.conf | grep region`. |
| `pull access denied for tabular/iceberg-rest` | Wrong org name | Image is `tabulario/iceberg-rest` (trailing `o`). |
| `403 Forbidden` on S3A writes | Stale hadoop-aws / aws-sdk-bundle versions | Don't change the version ARGs in `spark/Dockerfile` — they're pinned together for a reason. |
| Build hangs on Spark tarball curl | Mirror is `archive.apache.org` (~200 KB/s on a 400 MB file) | Already fixed — `SPARK_TARBALL_URL` defaults to `dlcdn.apache.org` (~60 MB/s). |
| `NoSuchMethodError` on Delta | `--packages io.delta:...` clashes with bundled JARs | Don't add `--packages`; bundled JARs are authoritative. |
| Worker OOM under load | Default 2 GiB | Bump `SPARK_WORKER_MEMORY=4g` in `.env`, then `docker compose up -d spark-worker`. |
| History Server is empty | App is still running, or hasn't `stop()`'d | Call `spark.stop()` in the notebook, refresh after ~15 s. |
| `iceberg-init` exits non-zero | REST catalog never came up | `docker compose logs iceberg-rest` — usually a missing `CATALOG_S3_*` env var. |
