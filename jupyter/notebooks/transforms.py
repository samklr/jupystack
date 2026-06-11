"""Shared transformations for the medallion notebooks (05 Delta, 06 Iceberg).

Lives next to the notebooks so the JupyterLab kernel (cwd = /home/jovyan/work)
can import it straight from the bind mount, without an image rebuild.
"""
from pyspark.sql import DataFrame, functions as F


def explode_pageviews(bronze: DataFrame) -> DataFrame:
    """Flatten raw Wikimedia top-pageviews JSON into one row per (day, article)."""
    return (
        bronze.select(F.explode("items").alias("i"))
        .select(
            F.to_date(F.concat_ws("-", "i.year", "i.month", "i.day")).alias("day"),
            F.col("i.project").alias("project"),
            F.explode("i.articles").alias("a"),
        )
        .select(
            "day",
            "project",
            F.col("a.article").alias("article"),
            F.col("a.views").cast("long").alias("views"),
            F.col("a.rank").cast("int").alias("rank"),
        )
    )
