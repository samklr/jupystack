# Custom Spark image: Spark 3.5.3 on Temurin 17 with Delta + Iceberg + S3A JARs bundled.
# Bundling avoids runtime --packages downloads so the demo stack boots offline-clean.
FROM eclipse-temurin:17-jre-jammy

ARG SPARK_VERSION=3.5.8
ARG HADOOP_PROFILE=3
ARG HADOOP_AWS_VERSION=3.3.4
ARG AWS_SDK_VERSION=1.12.262
ARG DELTA_VERSION=3.2.0
ARG ICEBERG_VERSION=1.6.1
ARG SCALA_BINARY=2.12
# dlcdn serves only "current" Spark versions at high throughput (~60 MB/s).
# archive.apache.org serves everything but is ~200 KB/s — unusable for 400 MB tarballs.
ARG SPARK_TARBALL_URL=https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_PROFILE}.tgz

ENV SPARK_HOME=/opt/spark \
    PATH=/opt/spark/bin:/opt/spark/sbin:$PATH \
    SPARK_NO_DAEMONIZE=true

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash curl ca-certificates gettext-base procps tini python3 python3-pip; \
    rm -rf /var/lib/apt/lists/*

# Spark — --retry survives transient mirror hiccups; -# prints progress to the build log.
RUN set -eux; \
    echo "Downloading Spark from ${SPARK_TARBALL_URL}"; \
    curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 -# \
        "${SPARK_TARBALL_URL}" -o /tmp/spark.tgz; \
    mkdir -p /opt; \
    tar -xzf /tmp/spark.tgz -C /opt; \
    mv "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_PROFILE}" "${SPARK_HOME}"; \
    rm /tmp/spark.tgz

# S3A + Delta + Iceberg JARs — versions must match Hadoop 3.3.4 / Spark 3.5 / Scala 2.12.
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

COPY spark-defaults.conf /opt/spark-defaults.conf.tmpl
COPY log4j2.properties   ${SPARK_HOME}/conf/log4j2.properties
COPY entrypoint.sh       /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Logs + event log dir (local fallback if S3A is briefly unreachable on first boot)
RUN mkdir -p /tmp/spark-events ${SPARK_HOME}/logs

EXPOSE 7077 8080 8081 18080

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]
