# Local Spark + Jupyter Demo Stack

Self-contained Docker Compose stack for local Apache Spark development and demos:

- Spark 3.5.3 standalone (master + 1 worker)
- Spark History Server
- JupyterLab with matching PySpark, **Delta Lake 3.2.0** and **Apache Iceberg 1.6.1**
- MinIO (S3-compatible object store) with three pre-created buckets
- Iceberg REST catalog (`tabular/iceberg-rest`), `demo` namespace pre-created
- Helper script for submitting jobs to a **remote Kubernetes** cluster

Everything is wired so `docker compose up -d` produces a working stack — no manual configuration.

---

## Prerequisites

- Docker Desktop ≥ 4.30 (or Docker Engine 25+ on Linux)
- ≥ 8 GB RAM available to Docker (Settings → Resources)
- Free local ports: `7077, 8080, 8081, 8181, 8888, 9000, 9001, 18080`
- macOS Apple Silicon and Linux x86_64 both work. Only `iceberg-rest` is amd64-only and runs under Rosetta.

## Quick start

```bash
cp .env.example .env
docker compose up -d --build      # first build downloads ~1 GB of JARs
docker compose ps                 # wait until all services show "(healthy)"
```

Then open **http://localhost:8888/lab** and run the notebooks in order:

1. `00_setup_check.ipynb` — proves Spark + S3A + Delta + Iceberg all work.
2. `01_delta_lake_demo.ipynb` — Delta CRUD + time travel.
3. `02_iceberg_demo.ipynb` — Iceberg via the REST catalog.
4. `03_spark_ui_guide.ipynb` — annotated tour of the Spark UI.

End-to-end smoke test (after the stack is healthy):

```bash
./scripts/test-stack.sh
```

## Service URLs

| Service | URL | Credentials |
|---|---|---|
| JupyterLab | http://localhost:8888/lab | none (token disabled — demo only) |
| Spark master UI | http://localhost:8080 | — |
| Spark worker UI | http://localhost:8081 | — |
| Spark History Server | http://localhost:18080 | — |
| MinIO console | http://localhost:9001 | `minioadmin / minioadmin` |
| MinIO S3 API | http://localhost:9000 | (same) |
| Iceberg REST catalog | http://localhost:8181/v1/config | — |
| Spark master URL | `spark://localhost:7077` | — |

## Connecting from host-side PySpark

Install matching PySpark on the host (`pip install pyspark==3.5.3`), then:

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
        # Bundle the same JARs the cluster has:
        .config("spark.jars.packages",
                "org.apache.hadoop:hadoop-aws:3.3.4,"
                "io.delta:delta-spark_2.12:3.2.0,"
                "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.6.1,"
                "org.apache.iceberg:iceberg-aws-bundle:1.6.1")
        .getOrCreate()
)
```

Note: the host process must be able to reach the worker on its internal Docker IP — the standard standalone protocol opens reverse connections from the worker back to the driver. If that fails, run the driver inside the `jupyter` container (the supported path) or use `spark.driver.host=host.docker.internal`.

## Submitting to a remote Kubernetes cluster

The helper script `scripts/k8s-spark-submit.sh` wraps `spark-submit` with the right K8s + S3A flags.

```bash
export K8S_API=https://my-cluster.example.com:6443
export SPARK_IMAGE=ghcr.io/my-org/spark:3.5.3        # must contain the same JARs as ./spark/Dockerfile
export S3_ENDPOINT=https://s3.eu-west-1.amazonaws.com  # what your cluster pods can reach
export MINIO_ACCESS_KEY=...
export MINIO_SECRET_KEY=...

./scripts/k8s-spark-submit.sh path/to/job.py
```

### Required RBAC (one-time, per namespace)

```bash
kubectl create serviceaccount spark
kubectl create clusterrolebinding spark-role \
    --clusterrole=edit \
    --serviceaccount=default:spark
```

The driver pod uses serviceaccount `spark` (override via `K8S_SA=...`). For production-grade scoping, replace `edit` with a custom role granting only `pods/exec`, `configmaps`, and `services` in the target namespace.

A commented `SparkSession.builder` example for `k8s://` mode lives in `00_setup_check.ipynb`.

## Swapping MinIO for real AWS S3

Edit `.env`:

```bash
MINIO_ACCESS_KEY=AKIA...           # real IAM access key
MINIO_SECRET_KEY=...
```

Then change two configs:

1. In `spark/spark-defaults.conf`, set `spark.hadoop.fs.s3a.endpoint` to `https://s3.<region>.amazonaws.com` and remove `spark.hadoop.fs.s3a.path.style.access` (or set it to `false`).
2. In `iceberg-rest/catalog.env`, update `CATALOG_S3_ENDPOINT` and `CATALOG_WAREHOUSE` to your real S3 bucket.

Rebuild only the Spark image: `docker compose build spark-master && docker compose up -d`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `S3AFileSystem` ClassNotFound | hadoop-aws JAR missing from classpath | Rebuild image: `docker compose build spark-master jupyter` |
| **403 Forbidden** on S3A writes | Version skew between `hadoop-aws` and `aws-java-sdk-bundle` | Don't change the versions in the Dockerfile ARGs — they're pinned together on purpose |
| Iceberg REST returns 500 on namespace create | MinIO creds wrong in `iceberg-rest/catalog.env` or env vars | `docker compose logs iceberg-rest`; check `AWS_ACCESS_KEY_ID` matches `.env` |
| Worker container OOMs under load | Default 2 GiB too small | Bump `SPARK_WORKER_MEMORY=4g` in `.env`, restart `spark-worker` |
| Delta JAR conflict (`NoSuchMethodError`) | A notebook is trying `--packages io.delta:delta-spark` | Don't — the JARs are already bundled; remove the package coordinate |
| `spark.read("s3a://...")` hangs on first call | S3A trying default `s3.amazonaws.com` because `path.style.access` is false | Confirm `path.style.access=true` (default in this stack); only flip it off for real AWS S3 |
| History Server shows no apps | App is still running; or event log dir doesn't exist | Stop the SparkSession (`spark.stop()`), then refresh after ~15 s |

## Architecture

```
                  ┌────────────────────────┐
   :8888 ────────►│  JupyterLab (PySpark)  │
                  └────────────┬───────────┘
                               │ spark://spark-master:7077
                               ▼
       :8080 ┌──────────────────────────────┐
             │       Spark Master           │
             └────────────┬─────────────────┘
                          │
                          ▼
       :8081 ┌──────────────────────────────┐
             │       Spark Worker           │
             └──────────────┬───────────────┘
                            │                       :18080
                            │       ┌──────────────────────────────┐
                            │       │     Spark History Server     │
                            │       └──────────────┬───────────────┘
                            │                      │
                            ▼  s3a://              ▼  s3a://spark-logs/events
                  ┌────────────────────────────────────────┐
                  │            MinIO  (S3 API)             │  :9000 / :9001
                  │   spark-warehouse / spark-logs / raw   │
                  └────────────────────────────────────────┘
                            ▲
                            │ S3FileIO
                            │
                  ┌─────────┴──────────────┐
                  │ Iceberg REST Catalog   │  :8181
                  │ namespace: demo        │
                  └────────────────────────┘
```

## Out of scope (deliberately)

- **Multi-tenant JupyterHub auth** — the demo runs single-user JupyterLab. Bolting on JupyterHub adds 3 services for no demo benefit.
- **TLS** — every port is plaintext loopback. Don't expose this stack on a routable network.
- **Spark Connect** — Spark 3.5 supports it, but the spec asked for `spark://...`. Adding it is a small change to the worker entrypoint if you need it later.
- **Hive Metastore** — Iceberg REST replaces it.

## File layout

```
.
├── docker-compose.yml
├── .env.example
├── README.md
├── spark/
│   ├── Dockerfile             # Spark 3.5.3 + Delta/Iceberg/hadoop-aws JARs
│   ├── spark-defaults.conf    # rendered with envsubst at container start
│   ├── log4j2.properties
│   └── entrypoint.sh          # SPARK_ROLE -> master | worker | history
├── jupyter/
│   ├── Dockerfile             # pyspark-notebook + delta-spark, pyiceberg
│   ├── requirements.txt
│   ├── spark_session.py       # get_spark(app_name) factory
│   └── notebooks/
│       ├── 00_setup_check.ipynb
│       ├── 01_delta_lake_demo.ipynb
│       ├── 02_iceberg_demo.ipynb
│       └── 03_spark_ui_guide.ipynb
├── minio/
│   └── init-buckets.sh        # creates spark-warehouse, spark-logs, raw-data
├── iceberg-rest/
│   └── catalog.env            # REST catalog config (MinIO-backed)
└── scripts/
    ├── k8s-spark-submit.sh    # remote K8s submit helper
    └── test-stack.sh          # end-to-end smoke test
```
