#!/bin/bash
set -e

echo "=========================================="
echo "AttackBlob Docker Test Script"
echo "=========================================="
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed"
    exit 1
fi

echo "✓ docker-compose found"
echo ""

# Start the service
echo "Starting AttackBlob with docker-compose..."
docker-compose up -d

echo ""
echo "Waiting for service to start (15 seconds)..."
sleep 15

# Check if container is running
if ! docker-compose ps | grep -q "Up"; then
    echo "Error: Container failed to start"
    docker-compose logs
    exit 1
fi

echo "✓ Container is running"
echo ""

# Generate a test bucket and access key
echo "Generating test access key..."
BUCKET_NAME="docker-test-bucket-$(date +%s)"
KEY_OUTPUT=$(docker-compose exec -T attack-blob /app/bin/gen_key "$BUCKET_NAME" 2>&1)

echo "$KEY_OUTPUT"
echo ""

# Extract access key ID from output
ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep "Access Key ID:" | awk '{print $NF}')

if [ -z "$ACCESS_KEY" ]; then
    echo "Error: Failed to extract access key"
    exit 1
fi

echo "✓ Access key created: $ACCESS_KEY"
echo ""

# List keys
echo "Listing all access keys..."
docker-compose exec -T attack-blob /app/bin/list_keys
echo ""

# List buckets
echo "Listing all buckets..."
docker-compose exec -T attack-blob /app/bin/list_buckets
echo ""

# Test health endpoint
echo "Testing health endpoint..."
HEALTH_RESPONSE=$(curl -s http://localhost:4004/health)
echo "Health check response: $HEALTH_RESPONSE"
echo ""

# Create a test file for upload
TEST_FILE=$(mktemp)
echo "This is a test file created at $(date)" > "$TEST_FILE"
echo "✓ Created test file: $TEST_FILE"
echo ""

echo "=========================================="
echo "Basic Docker Setup Test Complete!"
echo "=========================================="
echo ""
echo "Your AttackBlob instance is running on http://localhost:4004"
echo ""
echo "Bucket: $BUCKET_NAME"
echo "Access Key: $ACCESS_KEY"
echo ""
echo "Note: To upload files, you'll need to use the AWS SDK"
echo "with the access key and secret key shown above."
echo ""
echo "To stop the service:"
echo "  docker-compose down"
echo ""
echo "To view logs:"
echo "  docker-compose logs -f"
echo ""
echo "To cleanup (including data):"
echo "  docker-compose down -v"
echo ""

# Cleanup temp file
rm -f "$TEST_FILE"
