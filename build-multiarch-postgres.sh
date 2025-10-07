#!/bin/bash
# Multi-architecture build script for custom source-postgres connector

set -e

echo "🚀 Building multi-arch custom source-postgres connector..."

# Create working directory
WORK_DIR="/tmp/airbyte-postgres-multiarch"
rm -rf $WORK_DIR
mkdir -p $WORK_DIR
cd $WORK_DIR

echo "📦 Step 1: Extract official JAR from Docker image..."
CONTAINER_ID=$(docker create --platform linux/amd64 docker.io/airbyte/source-postgres:3.7.0)
docker cp "$CONTAINER_ID":/airbyte/lib/io.airbyte.airbyte-integrations.connectors-source-postgres.jar ./original.jar
docker rm "$CONTAINER_ID"

echo "📁 Step 2: Extract JAR contents..."
mkdir -p jar-contents
cd jar-contents
jar -xf ../original.jar

echo "📚 Step 3: Get all dependencies..."
CONTAINER_ID=$(docker create --platform linux/amd64 docker.io/airbyte/source-postgres:3.7.0)
mkdir -p ../libs
docker cp "$CONTAINER_ID":/airbyte/lib/ ../
mv ../lib/* ../libs/
rmdir ../lib
docker rm "$CONTAINER_ID"

echo "🔄 Step 4: Replace source and compile..."
# Replace the source file in the extracted structure
cp "/Users/hanslemm/GitHub/airbyte-source/airbyte-integrations/connectors/source-postgres/src/main/java/io/airbyte/integrations/source/postgres/PostgresSourceOperations.java" \
   ../PostgresSourceOperations.java

# Use Docker to compile with the exact same environment
docker run --rm \
    --platform linux/amd64 \
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

echo "🐳 Step 6: Create multi-platform Dockerfile..."
cd "$WORK_DIR"

cat > Dockerfile << 'EOF'
FROM docker.io/airbyte/source-postgres:3.7.0

# Replace the JAR with our custom version
COPY custom.jar /airbyte/lib/io.airbyte.airbyte-integrations.connectors-source-postgres.jar

LABEL io.airbyte.version=3.7.0-json-fix
LABEL io.airbyte.name=airbyte/source-postgres
EOF

echo "🔧 Step 7: Setup buildx for multi-platform..."
# Create a new buildx instance if it doesn't exist
docker buildx create --name multiarch-builder --use 2>/dev/null || docker buildx use multiarch-builder

echo "🏗️ Step 8: Build and push multi-platform image..."
# Build for both AMD64 and ARM64
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    -t ghcr.io/hanslemm/airbyte/source-postgres:3.7.0-dev \
    -t ghcr.io/hanslemm/airbyte/source-postgres:latest \
    --push \
    .

echo "✅ Multi-architecture image built and pushed successfully!"
echo "🎯 Images:"
echo "   - ghcr.io/hanslemm/airbyte/source-postgres:3.7.0-dev"
echo "   - ghcr.io/hanslemm/airbyte/source-postgres:latest"
echo ""
echo "🧪 Test on any platform with:"
echo "   docker run --rm ghcr.io/hanslemm/airbyte/source-postgres:3.7.0-dev spec"
echo ""
echo "📱 Supports: linux/amd64, linux/arm64"
