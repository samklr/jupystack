# JupyterLab with PySpark 3.5.3 (matches the cluster) + Delta/Iceberg/S3A JARs.
# Base image already ships matching PySpark — we only layer libs + JARs + notebooks.
FROM quay.io/jupyter/pyspark-notebook:spark-3.5.3

ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_VERSION=1.12.262
ARG DELTA_VERSION=3.2.0
ARG ICEBERG_VERSION=1.6.1
ARG SCALA_BINARY=2.12

USER root

# Same JAR set as the cluster image — keeps client and cluster classpaths aligned.
RUN set -eux; \
    cd "${SPARK_HOME}/jars"; \
    for url in \
        "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
        "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" \
        "https://repo1.maven.org/maven2/io/delta/delta-spark_${SCALA_BINARY}/${DELTA_VERSION}/delta-spark_${SCALA_BINARY}-${DELTA_VERSION}.jar" \
        "https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_VERSION}/delta-storage-${DELTA_VERSION}.jar" \
        "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_${SCALA_BINARY}/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_${SCALA_BINARY}-${ICEBERG_VERSION}.jar" \
        "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar" \
    ; do curl -fsSL "$url" -O; done

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Make spark_session importable from anywhere.
COPY spark_session.py /opt/conda/lib/python3.11/site-packages/spark_session.py

USER ${NB_UID}

COPY --chown=${NB_UID}:${NB_GID} notebooks/ /home/${NB_USER}/work/

ENV PYTHONPATH=/opt/conda/lib/python3.11/site-packages
