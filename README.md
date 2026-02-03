# End-to-End CDC Pipeline: Postgres to Iceberg

This repository implements a complete Change Data Capture (CDC) pipeline using:
- **Source**: PostgreSQL (System of Record)
- **Ingestion**: Debezium & Kafka
- **Processing**: Apache Spark (Structured Streaming)
- **Storage**: Apache Iceberg on MinIO (S3-compatible object storage)

It demonstrates how to stream database changes in real-time into an Iceberg data lake across a distributed 4-server architecture.

## Prerequisites

- Docker and Docker Compose installed.

## Distributed Deployment Guide

This project is configured to run across 4 servers:

1.  **AI-MASTER-DB** (`172.16.13.158`): Source PostgreSQL.
2.  **AI-LANDING-DB** (`172.16.13.159`): Kafka & Debezium Connect.
3.  **AI-ETL** (`172.16.13.160`): Spark & MinIO.
4.  **AI-SERVING** (`172.16.13.161`): Dormant (Future use).

### Step 0: Preparation

Clone this repository to **ALL 4 servers** to ensure all configuration files are present.

```bash
# On all servers
git clone <your-repo-url> .
```

### Step 1: AI-MASTER-DB (Source DB)

Host: `172.16.13.158`

1.  Start the database:
    ```bash
    docker compose -f docker-compose-master-db.yaml up -d
    ```

2.  Initialize the database and user (Run inside the container):
    ```bash
    docker exec -it pgsource psql -U postgres
    ```

3.  Paste the following SQL to create the user and table:
    ```sql
    -- Create CDC user
    CREATE ROLE cdc_user WITH LOGIN PASSWORD 'cdcpass';
    ALTER ROLE cdc_user REPLICATION;
    GRANT CONNECT ON DATABASE postgres TO cdc_user;

    -- Create Demo Database
    CREATE DATABASE cdc_demo;
    \c cdc_demo;

    -- Create Table and Permissions
    CREATE TABLE orders (
      id SERIAL PRIMARY KEY,
      customer_name TEXT,
      amount NUMERIC,
      status TEXT,
      created_at TIMESTAMP DEFAULT now()
    );
    INSERT INTO orders (customer_name, amount, status) VALUES ('Alice', 100, 'NEW');
    
    CREATE PUBLICATION cdc_pub FOR ALL TABLES;
    ALTER TABLE public.orders OWNER to cdc_user;
    ```
    Exit with `\q`.

### Step 2: AI-LANDING-DB (Kafka & Connect)

Host: `172.16.13.159`

1.  Start the services:
    ```bash
    docker compose -f docker-compose-landing-db.yaml up -d
    ```
    *Wait ~30 seconds for Kafka and Connect to start.*

2.  Register the Connector:
    Uses `connector-source-distributed.json` which points to `172.16.13.158`.

    ```bash
    curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
      http://localhost:8083/connectors/ \
      -d @connector-source-distributed.json
    ```

3.  Check Status:
    ```bash
    curl http://localhost:8083/connectors/pg-cdc-source/status
    ```
    Ensure `state` is `RUNNING`.

### Step 3: AI-ETL (Processing)

Host: `172.16.13.160`

1.  Start Spark and MinIO:
    ```bash
    docker compose -f docker-compose-etl.yaml up -d
    ```

2.  Run the verification job:
    This script reads from Kafka (`172.16.13.159`) and writes to local MinIO.

    ```bash
    # Grant execution permission
    chmod +x write_kafka_to_iceberg_distributed.sh
    
    # Run the job
    ./write_kafka_to_iceberg_distributed.sh
    ```

### Step 4: Verification

1.  **Generate Data**:
    On **AI-MASTER-DB**:
    ```bash
    docker exec -it pgsource psql -U postgres -d cdc_demo -c "INSERT INTO orders (customer_name, amount, status) VALUES ('Bob', 250, 'PAID');"
    ```

2.  **Check Processing**:
    Watch the output of the Spark script on **AI-ETL**. It should process the new event.

3.  **Check Storage**:
    Open MinIO Console on `http://172.16.13.160:9001` (if port mapped) or check files via CLI:
    ```bash
    # On AI-ETL
    docker exec -it minio ls -R /data/warehouse
    ```

## Troubleshooting

- **Check Logs**:
  - `docker compose -f <file> logs -f <service>`
- **Portainer**: If installed, inspect containers visually.
