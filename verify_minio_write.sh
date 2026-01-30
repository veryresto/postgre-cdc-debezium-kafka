#!/bin/bash
set -e
echo "Verifying MinIO write access..."
docker compose exec -T spark spark-shell <<EOF
import org.apache.hadoop.fs._
val fs = FileSystem.get(new java.net.URI("s3a://warehouse/"), sc.hadoopConfiguration)
try {
  val path = new Path("/test_write.txt")
  val os = fs.create(path, true)
  os.write("hello".getBytes)
  os.close()
  println("Write successful to " + path)
  
  // Verify list
  val status = fs.listStatus(path)
  println("File exists: " + status(0).getPath)
} catch {
  case e: Exception => 
    println("Write failed: " + e.getMessage)
    e.printStackTrace()
}
:quit
EOF
