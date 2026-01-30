#!/bin/bash
set -e

echo "Read Kafka as streaming DataFrame..."
# Use -T to disable pseudo-tty allocation for piping input
docker compose exec -T spark spark-shell --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 --conf spark.jars.ivy=/tmp/.ivy <<EOF
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import java.util.Base64
import scala.math.BigInt
import java.math.BigDecimal

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
    new BigDecimal(new BigInt(bytes).bigInteger, scale)
  }
}

val rawKafka = spark.read.
  format("kafka").
  option("kafka.bootstrap.servers", "kafka:9092").
  option("subscribe", "pgserver1.public.orders").
  option("startingOffsets", "earliest").
  load()

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

normalized.show(5, false)
:quit
EOF

echo "Read complete!"
