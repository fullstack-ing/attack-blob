# AttackBlob

![Attack blob logo](https://raw.githubusercontent.com/fullstack-ing/attack-blob/refs/heads/main/priv/static/logo.png)

[![Docker Hub](https://img.shields.io/docker/v/fullstacking/attack-blob?label=Docker%20Hub&logo=docker)](https://hub.docker.com/r/fullstacking/attack-blob)
[![Docker Pulls](https://img.shields.io/docker/pulls/fullstacking/attack-blob?logo=docker)](https://hub.docker.com/r/fullstacking/attack-blob)

A lightweight, minimal blob storage server designed as a MINIO alternative. AttackBlob provides public read-only blob storage with AWS S3-compliant signed upload capabilities.

**Production-ready Docker images available on [Docker Hub](https://hub.docker.com/r/fullstacking/attack-blob)**

## Features

- **Public Read Access** - Anyone can GET blobs via HTTP
- **AWS S3-Compatible Uploads** - Signed PUT/DELETE requests using AWS Signature V4
- **Multipart Uploads** - Chunked uploads for large files (up to 5TB)
- **Presigned URLs** - Support for time-limited upload URLs
- **Key-Based Authentication** - Simple access key to bucket pairing
- **No Database** - File-based configuration with in-memory caching
- **CORS Support** - Configurable cross-origin resource sharing

## Quick Start

### Installation

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

The server will start on `http://localhost:4000` by default.

### Generate Access Keys

```bash
# Create a bucket and generate an access key
mix attack_blob.gen.key my-bucket

# List all access keys
mix attack_blob.list.keys

# List all buckets
mix attack_blob.list.buckets

# Revoke an access key
mix attack_blob.revoke.key AKIAXXXXXXXX
```

## Docker Deployment

AttackBlob is available as a Docker image for easy deployment in production environments.

### Quick Start with Docker

```bash
# Pull the latest image
docker pull fullstacking/attack-blob:latest

# Run with persistent storage
docker run -d \
  --name attack-blob \
  -p 4004:4004 \
  -v attack_blob_data:/app/data \
  -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
  -e PHX_HOST=blobs.example.com \
  fullstacking/attack-blob:latest
```

### Docker CLI Commands

AttackBlob includes CLI tools for managing keys and buckets in production:

```bash
# Generate a new access key and bucket
docker exec attack-blob /app/bin/gen_key my-bucket

# List all access keys
docker exec attack-blob /app/bin/list_keys

# List all buckets
docker exec attack-blob /app/bin/list_buckets

# Revoke an access key
docker exec attack-blob /app/bin/revoke_key AKIAXXXXXXXX
```

### Docker Compose

For local development or testing, use Docker Compose:

```bash
# Start the service
docker-compose up -d

# View logs
docker-compose logs -f

# Generate a test key
docker-compose exec attack-blob /app/bin/gen_key test-bucket

# Stop the service
docker-compose down
```

See the included `docker-compose.yml` for a complete example with volume mounting and environment configuration.

#### Complete Docker Compose Workflow

Here's a complete example of setting up AttackBlob with Docker Compose:

```bash
# 1. Clone the repository (or download docker-compose.yml)
git clone https://github.com/fullstacking/attack-blob.git
cd attack-blob

# 2. (Optional) Copy and customize environment variables
cp .env.example .env
# Edit .env with your preferred settings

# 3. Start the service
docker-compose up -d

# 4. Wait for the service to be healthy
docker-compose ps

# 5. Generate an access key
docker-compose exec attack-blob /app/bin/gen_key my-first-bucket

# Example output:
# Access key created successfully!
#
# Bucket: my-first-bucket
# Access Key ID: AKIAEXAMPLE123456789
# Secret Key: ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijk12
#
# Permissions: put, delete
#
# IMPORTANT: Save the secret key now! It won't be displayed again.

# 6. Test uploading a file (requires AWS CLI or SDK)
# See "Usage Examples" section below for upload instructions

# 7. Test public download
curl http://localhost:4004/my-first-bucket/test.txt

# 8. View all keys
docker-compose exec attack-blob /app/bin/list_keys

# 9. View logs
docker-compose logs -f attack-blob

# 10. Stop the service (keeps data)
docker-compose down

# To remove data as well:
docker-compose down -v
```

### Docker Volumes

AttackBlob stores data in `/app/data` inside the container. This directory contains:

- `/app/data/keys/` - Access key configurations (JSON files)
- `/app/data/buckets/` - Blob storage organized by bucket
- `/app/data/multipart/` - Temporary storage for in-progress multipart uploads

**Important:** Always mount a volume to `/app/data` for persistent storage:

```bash
# Using a named volume (recommended)
docker run -v attack_blob_data:/app/data fullstacking/attack-blob:latest

# Using a bind mount (for direct access)
docker run -v /path/on/host:/app/data fullstacking/attack-blob:latest
```

### Docker Environment Variables

See the [Environment Variables](#environment-variables) section below for all available configuration options. Key variables for Docker:

```bash
docker run -d \
  -e SECRET_KEY_BASE=your-secret-key-here \
  -e PHX_HOST=blobs.example.com \
  -e PORT=4004 \
  -e ATTACK_BLOB_DATA_DIR=/app/data \
  -e ATTACK_BLOB_MAX_UPLOAD_SIZE=5368709120 \
  -e CORS_ALLOWED_ORIGINS="*" \
  fullstacking/attack-blob:latest
```

### Building Your Own Image

```bash
# Build from source
docker build -t attack-blob:custom .

# Run your custom build
docker run -d -p 4004:4004 attack-blob:custom
```

### Testing Your Docker Setup

A test script is included to verify your Docker setup:

```bash
# Make the script executable (first time only)
chmod +x test-docker.sh

# Run the test
./test-docker.sh
```

This script will:
- Start AttackBlob with docker-compose
- Generate a test bucket and access key
- List keys and buckets
- Test the health endpoint
- Display instructions for next steps

## Environment Variables

### Storage Configuration

- **`ATTACK_BLOB_DATA_DIR`** (default: `./data`)
  Directory where buckets and access keys are stored

- **`ATTACK_BLOB_MAX_UPLOAD_SIZE`** (default: `5368709120` = 5GB)
  Maximum upload size in bytes

### CORS Configuration

- **`CORS_ALLOWED_ORIGINS`** (default: `*`)
  Comma-separated list of allowed origins for CORS requests
  - `*` - Allow all origins (default)
  - `https://example.com,https://app.example.com` - Specific origins
  - `` (empty) - Disable CORS

- **`CORS_MAX_AGE`** (default: `600`)
  Maximum age in seconds for CORS preflight cache

- **`CORS_ALLOW_CREDENTIALS`** (default: `true`)
  Allow credentials in CORS requests (`true` or `false`)

### Server Configuration

- **`PHX_SERVER`** (default: not set)
  Set to `true` to start the server when using releases

- **`PORT`** (default: `4000` in dev, `4004` in prod)
  HTTP port to listen on

- **`PHX_HOST`** (default: `localhost` in dev)
  Hostname for URL generation in production

- **`SECRET_KEY_BASE`** (required in production)
  Secret key for signing sessions and cookies

## Usage Examples

### Upload a File (with presigned URL)

```bash
# Generate a presigned URL (using AWS SDK or similar)
# Then upload with curl:
curl -X PUT "http://localhost:4000/my-bucket/file.txt?X-Amz-Algorithm=..." \
  --data-binary @file.txt
```

### Download a File

```bash
# Public read access - no authentication required
curl http://localhost:4000/my-bucket/file.txt
```

### Multipart Upload (for large files)

AttackBlob supports AWS S3-compatible multipart uploads for efficiently uploading large files in chunks.

**Workflow:**
1. Initiate multipart upload - get an upload ID
2. Upload parts (chunks) - each part gets an ETag
3. Complete multipart upload - assemble all parts into final file

**Example using AWS SDK:**
```javascript
// Using AWS SDK for JavaScript
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
  endpoint: 'http://localhost:4000',
  accessKeyId: 'AKIATEST...',
  secretAccessKey: 'your-secret-key',
  region: 'us-east-1',
  s3ForcePathStyle: true
});

// Initiate multipart upload
const params = {
  Bucket: 'my-bucket',
  Key: 'large-file.zip'
};

const multipart = await s3.createMultipartUpload(params).promise();
const uploadId = multipart.UploadId;

// Upload parts (5MB minimum per part except last)
const partSize = 5 * 1024 * 1024; // 5MB
const parts = [];

for (let i = 0; i < totalParts; i++) {
  const partParams = {
    Bucket: 'my-bucket',
    Key: 'large-file.zip',
    PartNumber: i + 1,
    UploadId: uploadId,
    Body: fileChunk
  };

  const part = await s3.uploadPart(partParams).promise();
  parts.push({ ETag: part.ETag, PartNumber: i + 1 });
}

// Complete multipart upload
const completeParams = {
  Bucket: 'my-bucket',
  Key: 'large-file.zip',
  UploadId: uploadId,
  MultipartUpload: { Parts: parts }
};

await s3.completeMultipartUpload(completeParams).promise();
```

**Features:**
- Supports files up to 5TB (10,000 parts × 5GB max part size)
- Parts can be uploaded in parallel for faster speeds
- Failed parts can be retried independently
- Automatic cleanup of abandoned uploads after 24 hours

### List Bucket Contents

```bash
# List all objects in a bucket
curl http://localhost:4000/my-bucket

# List with prefix filter
curl "http://localhost:4000/my-bucket?prefix=images/"

# Hierarchical listing with delimiter
curl "http://localhost:4000/my-bucket?delimiter=/"
```

## CORS Configuration Examples

### Allow All Origins (Default)

```bash
# No configuration needed - this is the default
mix phx.server
```

### Allow Specific Origins

```bash
# Allow only specific domains
CORS_ALLOWED_ORIGINS="https://app.example.com,https://www.example.com" mix phx.server
```

### Disable CORS

```bash
# Set to empty string to disable CORS
CORS_ALLOWED_ORIGINS="" mix phx.server
```

### Custom CORS Settings

```bash
# Full CORS configuration example
CORS_ALLOWED_ORIGINS="https://app.example.com" \
CORS_MAX_AGE="3600" \
CORS_ALLOW_CREDENTIALS="false" \
mix phx.server
```

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/attack_blob_web/controllers/blob_controller_test.exs

# Run with coverage
mix test --cover
```

### Precommit Checks

```bash
# Run all precommit checks (compile, format, test, dialyzer)
mix precommit
```

### Type Checking

```bash
# Run Dialyzer for static type analysis
mix dialyzer
```

## Production Deployment

### Nginx Configuration

AttackBlob works great behind Nginx for caching, compression, and SSL termination. Here's a complete configuration example:

```nginx
# Upstream to AttackBlob
upstream attack_blob {
    server 127.0.0.1:4004;
    keepalive 32;
}

# Cache configuration for blob content
proxy_cache_path /var/cache/nginx/attack_blob
    levels=1:2
    keys_zone=attack_blob_cache:10m
    max_size=10g
    inactive=24h
    use_temp_path=off;

server {
    listen 80;
    listen [::]:80;
    server_name blobs.example.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name blobs.example.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/blobs.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/blobs.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Max upload size (should match ATTACK_BLOB_MAX_UPLOAD_SIZE)
    client_max_body_size 5G;
    client_body_buffer_size 10M;

    # Timeouts for large uploads
    client_body_timeout 300s;
    send_timeout 300s;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;

    # Logging
    access_log /var/log/nginx/attack_blob_access.log;
    error_log /var/log/nginx/attack_blob_error.log;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/xhtml+xml
        image/svg+xml;

    # Health check endpoint (no caching)
    location /health {
        proxy_pass http://attack_blob;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_cache off;
    }

    # GET requests - cache aggressively
    location / {
        # Only cache GET requests
        limit_except GET HEAD OPTIONS {
            proxy_pass http://attack_blob;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";

            # Preserve AWS signature headers
            proxy_pass_request_headers on;

            # No caching for PUT/DELETE
            proxy_cache off;
        }

        # Proxy to AttackBlob
        proxy_pass http://attack_blob;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";

        # Caching for GET requests
        proxy_cache attack_blob_cache;
        proxy_cache_key "$scheme$request_method$host$request_uri";
        proxy_cache_valid 200 24h;
        proxy_cache_valid 404 5m;
        proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
        proxy_cache_background_update on;
        proxy_cache_lock on;

        # Add cache status header
        add_header X-Cache-Status $upstream_cache_status;

        # Don't cache if there's a Cache-Control: no-cache header
        proxy_cache_bypass $http_cache_control;
    }
}
```

### Nginx Configuration Breakdown

**Caching Strategy:**
- GET/HEAD requests are cached for 24 hours
- PUT/DELETE requests bypass cache entirely
- 404s cached for 5 minutes to prevent repeated lookups
- Stale content served during backend issues

**Compression:**
- Gzip enabled for text and JSON responses
- Minimum 1KB file size before compression
- Level 6 compression (good balance of speed/size)

**Upload Handling:**
- 5GB max body size (matches default `ATTACK_BLOB_MAX_UPLOAD_SIZE`)
- Extended timeouts for large uploads (5 minutes)
- AWS signature headers preserved for authentication

**Security:**
- HTTPS with modern TLS configuration
- HSTS header for HTTPS enforcement
- Content-Type sniffing prevention

### Testing Nginx Configuration

```bash
# Test configuration syntax
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx

# View cache statistics
ls -lh /var/cache/nginx/attack_blob/

# Clear cache if needed
sudo rm -rf /var/cache/nginx/attack_blob/*
```

### Monitoring Cache Performance

```bash
# Watch cache hits in real-time
tail -f /var/log/nginx/attack_blob_access.log | grep -o "X-Cache-Status: [A-Z]*"

# Check cache size
du -sh /var/cache/nginx/attack_blob/
```

See [DESIGN.md](DESIGN.md) for architecture details and [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for deployment instructions.

## API Reference

See [DESIGN.md](DESIGN.md) for detailed API endpoint documentation.
