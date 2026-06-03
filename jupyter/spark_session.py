"""Shared SparkSession factory for the demo notebooks.

Usage in any notebook:
    from spark_session import get_spark
    spark = get_spark("my-app")

Reads MINIO_ACCESS_KEY / MINIO_SECRET_KEY from the environment (injected by
docker-compose) so notebooks never embed credentials.
"""
from __future__ import annotations

import os

from pyspark.sql import SparkSession


def get_spark(app_name: str = "jupyter-demo") -> SparkSession:
    access_key = os.environ.get("MINIO_ACCESS_KEY", "minioadmin")
    secret_key = os.environ.get("MINIO_SECRET_KEY", "minioadmin")
    master_url = os.environ.get("SPARK_MASTER_URL", "spark://spark-master:7077")
    minio_endpoint = os.environ.get("S3_ENDPOINT", "http://minio:9000")

    builder = (
        SparkSession.builder.appName(app_name)
        .master(master_url)
        # S3A → MinIO
        .config("spark.hadoop.fs.s3a.endpoint", minio_endpoint)
        .config("spark.hadoop.fs.s3a.access.key", access_key)
        .config("spark.hadoop.fs.s3a.secret.key", secret_key)
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .config(
            "spark.hadoop.fs.s3a.aws.credentials.provider",
            "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider",
        )
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        # Delta Lake
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        # Iceberg via REST catalog
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg.type", "rest")
        .config("spark.sql.catalog.iceberg.uri", "http://iceberg-rest:8181")
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://spark-warehouse/iceberg")
        # HadoopFileIO reuses the S3A connector (same as Delta). S3FileIO via
        # AWS SDK v2 has native bits that crash with SIGABRT on Apple Silicon.
        .config("spark.sql.catalog.iceberg.io-impl", "org.apache.iceberg.hadoop.HadoopFileIO")
        # Iceberg's vectorized Arrow reader crashes the JIT compiler on aarch64+JDK17.
        .config("spark.sql.iceberg.vectorization.enabled", "false")
        # Event logs → MinIO so the History Server picks them up
        .config("spark.eventLog.enabled", "true")
        .config("spark.eventLog.dir", "s3a://spark-logs/events")
        .config("spark.sql.adaptive.enabled", "true")
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
    )

    return builder.getOrCreate()
