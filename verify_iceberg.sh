#!/bin/bash
set -e

echo "--- Verifying Iceberg Table via Spark SQL ---"
docker compose exec -T spark spark-shell \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
  --conf spark.jars.ivy=/tmp/.ivy \
  --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.local.type=hadoop \
  --conf spark.sql.catalog.local.warehouse=s3a://warehouse \
  --conf spark.sql.catalog.local.io-impl=org.apache.iceberg.hadoop.HadoopFileIO \
  --conf spark.sql.defaultCatalog=local \
  <<EOF

println("\n=== Iceberg Snapshots ===")
spark.sql("SELECT snapshot_id, committed_at, operation, summary FROM local.db.orders.snapshots ORDER BY committed_at DESC").show(false)

println("\n=== Iceberg Data (Top 20) ===")
spark.sql("SELECT * FROM local.db.orders ORDER BY __ingest_ts DESC LIMIT 20").show(false)
:quit
EOF

echo -e "\n--- Verifying Physical Files in MinIO ---"
docker compose exec minio ls -R /data/warehouse/db/orders || echo "Could not list MinIO files directly"
