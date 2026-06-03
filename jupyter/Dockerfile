# JupyterLab + PySpark 3.5.8 (matches cluster) + Delta/Iceberg/S3A JARs.
# minimal-notebook ships only Python + Lab — we install PySpark ourselves so the version
# pins exactly to the cluster (quay's pyspark-notebook trails by months).
FROM quay.io/jupyter/minimal-notebook:python-3.11

ARG SPARK_VERSION=3.5.8
ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_VERSION=1.12.262
ARG DELTA_VERSION=3.2.0
ARG ICEBERG_VERSION=1.6.1
ARG SCALA_BINARY=2.12

USER root

# Java is needed to run the local PySpark client driver.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-17-jre-headless curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # Compute JAVA_HOME from the actual java binary so this works on both arm64 and amd64.
    && JAVA_BIN="$(readlink -f /usr/bin/java)" \
    && JAVA_HOME="${JAVA_BIN%/bin/java}" \
    && echo "JAVA_HOME=${JAVA_HOME}" >> /etc/environment \
    && ln -sfn "${JAVA_HOME}" /opt/java-home

ENV JAVA_HOME=/opt/java-home

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# PySpark wheel bundles its own Spark distribution; we drop matching support JARs into its jars/ dir.
ENV SPARK_HOME=/opt/conda/lib/python3.11/site-packages/pyspark
RUN set -eux; \
    cd "${SPARK_HOME}/jars"; \
    for url in \
        "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
        "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_VERSION}/aws-java-sdk-bundle-${AWS_SDK_VERSION}.jar" \
        "https://repo1.maven.org/maven2/io/delta/delta-spark_${SCALA_BINARY}/${DELTA_VERSION}/delta-spark_${SCALA_BINARY}-${DELTA_VERSION}.jar" \
        "https://repo1.maven.org/maven2/io/delta/delta-storage/${DELTA_VERSION}/delta-storage-${DELTA_VERSION}.jar" \
        "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_${SCALA_BINARY}/${ICEBERG_VERSION}/iceberg-spark-runtime-3.5_${SCALA_BINARY}-${ICEBERG_VERSION}.jar" \
        "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/${ICEBERG_VERSION}/iceberg-aws-bundle-${ICEBERG_VERSION}.jar" \
    ; do \
        echo "  $url"; \
        curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 -sS "$url" -O; \
    done

# Make spark_session importable from any notebook.
COPY spark_session.py /opt/conda/lib/python3.11/site-packages/spark_session.py

USER ${NB_UID}

COPY --chown=${NB_UID}:${NB_GID} notebooks/ /home/${NB_USER}/work/
