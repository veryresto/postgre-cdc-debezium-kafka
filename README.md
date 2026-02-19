# End-to-End CDC Pipeline: Postgres to Iceberg

This repository implements a complete Change Data Capture (CDC) pipeline using:
- **Source**: PostgreSQL (System of Record)
- **Ingestion**: Debezium & Kafka
- **Processing**: Apache Spark (Structured Streaming)
- **Storage**: Apache Iceberg on MinIO (S3-compatible object storage)

It demonstrates how to stream database changes in real-time into an Iceberg data lake across a distributed 4-server architecture.

## Prerequisites

- Docker and Docker Compose installed.

## Deployment Guide

You can deploy this pipeline either in a **Single VM** (Recommended for dev/test) or across **4 Distributed Servers**.

### Configuration (.env)

Before deploying, create a `.env` file from the example:
```bash
cp .env-example .env
```

Edit `.env` and set the IP address of your VM (or the specific server IPs if distributed).

---

### Option A: Single VM Deployment

1.  **Set IPs to Localhost**:
    In `.env`, set all hosts to your VM's private IP (e.g., `172.16.13.158`) or `127.0.0.1`.

2.  **Start All Services**:
    ```bash
    docker compose -f docker-compose-master-db.yaml \
                   -f docker-compose-landing-db.yaml \
                   -f docker-compose-etl.yaml up -d
    ```

3.  **Register Connector**:
    ```bash
    # Load .env variables and substitute placeholder in JSON
    export $(grep -v '^#' .env | xargs)
    envsubst < connector-source-distributed.json | curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
      http://localhost:8083/connectors/ -d @-
    ```

4.  **Run Spark Job**:
    ```bash
    ./write_kafka_to_iceberg_distributed.sh
    ```

---

### Option B: Distributed Deployment Guide

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
    # Load .env and substitute IPs
    export $(grep -v '^#' .env | xargs)
    envsubst < connector-source-distributed.json | curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" \
      http://localhost:8083/connectors/ -d @-
    ```

3.  Check Status:
    ```bash
    curl http://localhost:8083/connectors/pg-cdc-source/status
    ```
    Ensure `state` is `RUNNING`.

### Step 3: AI-ETL (Processing)

Host: `172.16.13.160`

1.  **Prepare Hive Metastore (One-time Setup)**:
    Download the required AWS JARs to enable S3 access for Hive:
    ```bash
    # Create lib directory
    mkdir -p hive/lib

    # Download Hadoop AWS and AWS SDK Bundle
    curl -L -o hive/lib/hadoop-aws-3.3.6.jar https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.6/hadoop-aws-3.3.6.jar
    curl -L -o hive/lib/aws-java-sdk-bundle-1.12.367.jar https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar
    ```

2.  Start Spark, MinIO, Trino, and Hive Metastore:
    ```bash
    docker compose -f docker-compose-etl.yaml up -d
    ```

3.  Create Bucket:
    ```bash
    # Create valid bucket for warehouse
    docker exec minio mkdir -p /data/warehouse
    ```

3.  Run the verification job:
    This script reads from Kafka (using `LANDING_DB_HOST` from `.env`) and writes to local MinIO.

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

4.  **Check Content via Spark SQL**:
    Run the distributed verification script to query the Iceberg table:

    ```bash
    ./verify_iceberg_data_distributed.sh
    ```

### Step 5: Querying with Trino (SQL Interface)

Trino provides a powerful SQL interface to query your Iceberg tables.

1.  **Start Trino CLI**:
    ```bash
    docker compose exec trino trino
    ```

2.  **Verify Tables**:
    ```sql
    SHOW SCHEMAS FROM iceberg;
    SHOW TABLES FROM iceberg.db;
    SELECT * FROM iceberg.db.orders;
    ```

    > **Note:** If the `orders` table is missing (e.g., after restarting Hive Metastore), you can register the existing data from MinIO:
    > ```sql
    > CALL iceberg.system.register_table('db', 'orders', 's3://warehouse/db/orders');
    > ```

3.  **Run Automated Verification**:
    ```bash
    ./verify_trino.sh
    ```


## Troubleshooting

- **Check Logs**:
  - `docker compose -f <file> logs -f <service>`
- **Portainer**: If installed, inspect containers visually.
