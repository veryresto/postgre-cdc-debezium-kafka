#!/bin/bash
set -e

echo "Waiting for Trino to be ready..."
until docker compose exec trino trino --execute "SELECT 1" > /dev/null 2>&1; do
  echo "Trino is starting..."
  sleep 5
done

echo "Trino is ready!"

echo "--- Catalogs ---"
docker compose exec trino trino --execute "SHOW CATALOGS"

echo "--- Schemas in iceberg ---"
docker compose exec trino trino --execute "SHOW SCHEMAS FROM iceberg"

echo "--- Tables in iceberg.db ---"
docker compose exec trino trino --execute "SHOW TABLES FROM iceberg.db"

echo "--- Data from orders ---"
docker compose exec trino trino --execute "SELECT * FROM iceberg.db.orders ORDER BY __ingest_ts DESC LIMIT 5"
