#!/bin/bash
# Final build script - compile in the extracted JAR context

set -e

echo "🚀 Building custom source-postgres connector (v3)..."

# Create working directory
WORK_DIR="/tmp/airbyte-postgres-build-v3"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "📦 Step 1: Extract official JAR from Docker image..."
CONTAINER_ID=$(docker create docker.io/airbyte/source-postgres:3.7.0)
docker cp "$CONTAINER_ID":/airbyte/lib/io.airbyte.airbyte-integrations.connectors-source-postgres.jar ./original.jar
docker rm "$CONTAINER_ID"

echo "📁 Step 2: Extract JAR contents..."
mkdir -p jar-contents
cd jar-contents
jar -xf ../original.jar

echo "📚 Step 3: Get all dependencies..."
CONTAINER_ID=$(docker create docker.io/airbyte/source-postgres:3.7.0)
mkdir -p ../libs
docker cp "$CONTAINER_ID":/airbyte/lib/ ../
mv ../lib/* ../libs/
rmdir ../lib
docker rm "$CONTAINER_ID"

echo "🔄 Step 4: Replace source and compile in Docker with Java 21..."
# Replace the source file in the extracted structure
cp "/Users/hanslemm/GitHub/airbyte-source/airbyte-integrations/connectors/source-postgres/src/main/java/io/airbyte/integrations/source/postgres/PostgresSourceOperations.java" \
   ../PostgresSourceOperations.java

# Use Docker to compile with the exact same environment
docker run --rm \
    -v "$WORK_DIR":/workspace \
    -w /workspace \
    openjdk:21-jdk-slim bash -c '
        # Create classpath
        CLASSPATH=""
        for jar in /workspace/libs/*.jar; do
            CLASSPATH="$CLASSPATH:$jar"
        done

        # Compile the modified class
        javac -cp "$CLASSPATH" \
            -d /workspace/jar-contents \
            /workspace/PostgresSourceOperations.java

        echo "✅ Compilation successful"
    '

echo "📦 Step 5: Create new JAR..."
jar -cfm ../custom.jar META-INF/MANIFEST.MF .

echo "🐳 Step 6: Build Docker image..."
cd "$WORK_DIR"

cat > Dockerfile << 'EOF'
FROM docker.io/airbyte/source-postgres:3.7.0

# Replace the JAR with our custom version
COPY custom.jar /airbyte/lib/io.airbyte.airbyte-integrations.connectors-source-postgres.jar

LABEL io.airbyte.version=3.7.0-json-fix
LABEL io.airbyte.name=airbyte/source-postgres
EOF

# Build the custom image
docker build -t airbyte/source-postgres:3.7.0-custom .

echo "✅ Custom image built successfully!"
echo "🎯 Image: airbyte/source-postgres:3.7.0-custom"
echo "🧪 Test with: docker run --rm airbyte/source-postgres:3.7.0-custom spec"
