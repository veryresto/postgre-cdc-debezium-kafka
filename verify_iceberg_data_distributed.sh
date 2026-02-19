#!/bin/bash
set -e

echo "Verifying Iceberg data using Spark SQL..."
docker compose -f docker-compose-etl.yaml exec -T spark spark-shell \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  --conf spark.jars.ivy=/tmp/.ivy \
  --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.local.type=hive \
  --conf spark.sql.catalog.local.uri=thrift://hive-metastore:9083 \
  --conf spark.sql.catalog.local.warehouse=s3a://warehouse \
  --conf spark.sql.catalog.local.io-impl=org.apache.iceberg.hadoop.HadoopFileIO \
  --conf spark.sql.defaultCatalog=local \
  <<EOF

println("Quering Iceberg table local.db.orders...")
spark.sql("SELECT * FROM local.db.orders").show(false)

:quit
EOF
