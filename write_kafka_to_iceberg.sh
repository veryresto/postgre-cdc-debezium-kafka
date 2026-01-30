#!/bin/bash
set -e

echo "Starting generic Iceberg CDC write job..."

# Helper to run spark-shell with necessary packages and configuration
# Added software.amazon.awssdk:bundle:2.20.160 to support S3FileIO (AWS SDK v2)
docker compose exec -T spark spark-shell \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,software.amazon.awssdk:bundle:2.20.160 \
  --conf spark.jars.ivy=/tmp/.ivy \
  --conf spark.sql.catalog.local=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.local.type=hadoop \
  --conf spark.sql.catalog.local.warehouse=s3a://warehouse \
  --conf spark.sql.catalog.local.io-impl=org.apache.iceberg.aws.s3.S3FileIO \
  --conf spark.sql.catalog.local.s3.endpoint=http://minio:9000 \
  --conf spark.sql.catalog.local.s3.path-style-access=true \
  --conf spark.sql.defaultCatalog=local \
  <<EOF

import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import java.util.Base64
import scala.math.BigInt
import java.math.BigDecimal

// --- STEP 1: Define Schemas and UDFs ---

val decimalSchema = StructType(Seq(
  StructField("scale", IntegerType, false),
  StructField("value", StringType, false) // base64
))

val orderSchema = StructType(Seq(
  StructField("id", IntegerType, false),
  StructField("customer_name", StringType, true),
  StructField("amount", decimalSchema, true),
  StructField("status", StringType, true),
  StructField("created_at", LongType, true)
))

val payloadSchema = StructType(Seq(
  StructField("before", orderSchema, true),
  StructField("after", orderSchema, true),
  StructField("op", StringType, false)
))

val decodeDecimal = udf { (value: String, scale: Int) =>
  if (value == null) null
  else {
    val bytes = Base64.getDecoder.decode(value)
    new BigDecimal(BigInt(bytes).bigInteger, scale)
  }
}

// --- STEP 2: Create Iceberg Table (Idempotent) ---

spark.sql("""
  CREATE TABLE IF NOT EXISTS local.db.orders (
    id INT,
    customer_name STRING,
    amount DECIMAL(18,6),
    status STRING,
    created_at TIMESTAMP,
    __op STRING,
    __ingest_ts TIMESTAMP
  )
  USING iceberg
  PARTITIONED BY (days(created_at))
""")

println("Iceberg table created/verified.")

// --- STEP 3: Read from Kafka ---

val rawKafka = spark.readStream.
  format("kafka").
  option("kafka.bootstrap.servers", "kafka:9092").
  option("subscribe", "pgserver1.public.orders").
  option("startingOffsets", "earliest").
  load()

// --- STEP 4: Parse and Transform ---

val parsed = rawKafka.
  selectExpr("CAST(value AS STRING)").
  select(from_json(col("value"), StructType(Seq(
    StructField("payload", payloadSchema)
  ))).as("data")).
  select("data.payload.*")

val normalized = parsed.select(
  col("op"),
  when(col("op") === "d", col("before.id")).
    otherwise(col("after.id")).as("id"),
  col("after.customer_name").as("customer_name"),
  decodeDecimal(
    col("after.amount.value"),
    col("after.amount.scale")
  ).as("amount"),
  col("after.status").as("status"),
  (col("after.created_at") / 1000000).
    cast(TimestampType).
    as("created_at")
)

// --- STEP 5: Enrich with Metadata ---

val enriched = normalized.
  withColumn("__op", col("op")).
  withColumn("__ingest_ts", current_timestamp()).
  drop("op")

// --- STEP 6: Write to Iceberg ---

println("Starting streaming write to Iceberg...")

try {
  val query = enriched.writeStream.
    format("iceberg").
    outputMode("append").
    option("checkpointLocation", "s3a://warehouse/checkpoints/orders").
    toTable("local.db.orders")

  query.awaitTermination(90000) // Run for 90 seconds to process data
} catch {
  case e: Exception => println("Streaming query stopped or failed: " + e.getMessage)
}

println("Streaming job completed.")
:quit
EOF
