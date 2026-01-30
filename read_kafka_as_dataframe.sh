#!/bin/bash
set -e

echo "Read Kafka as streaming DataFrame..."
# Use -T to disable pseudo-tty allocation for piping input
docker compose exec -T spark spark-shell --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 --conf spark.jars.ivy=/tmp/.ivy <<EOF
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

val rawKafka = spark.read.
  format("kafka").
  option("kafka.bootstrap.servers", "kafka:9092").
  option("subscribe", "pgserver1.public.orders").
  option("startingOffsets", "earliest").
  load()

rawKafka.printSchema()
rawKafka.show(5, false)
:quit
EOF

echo "Read complete!"
