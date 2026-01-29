# Manual Verification

Follow these steps to verify the Spark configuration fixes.

### 1. Rebuild and Start Services
Rebuild the Spark image and start the container:
```bash
docker compose build spark
docker compose up -d
```

### 2. Verify Container Status
Ensure the `spark` container is running:
```bash
docker compose ps
```

### 3. Interactive Verification
Enter the Spark container:
```bash
docker compose exec spark bash
```

Inside the container, launch `spark-shell` and test S3 access:
```scala
spark-shell

// Once inside the Spark shell, run:
import org.apache.hadoop.fs._
val fs = FileSystem.get(new java.net.URI("s3a://warehouse/"), sc.hadoopConfiguration)
fs.listStatus(new Path("/"))
```