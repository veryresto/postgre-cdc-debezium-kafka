#!/bin/bash
set -e

echo "Read Kafka as streaming DataFrame..."
# Use -T to disable pseudo-tty allocation for piping input
docker compose exec -T spark spark-shell <<EOF
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

val rawKafka = spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "kafka:9092")
  .option("subscribe", "pgserver1.public.orders")
  .option("startingOffsets", "earliest")
  .load()
:quit
EOF

echo "Read complete!"
