#!/bin/bash
set -e

echo "Running Spark verification..."
# Use -T to disable pseudo-tty allocation for piping input
docker compose exec -T spark spark-shell <<EOF
import org.apache.hadoop.fs._
val fs = FileSystem.get(new java.net.URI("s3a://warehouse/"), sc.hadoopConfiguration)
fs.listStatus(new Path("/"))
:quit
EOF

echo "Verification complete!"
