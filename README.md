# AttackBlob

A lightweight, minimal blob storage server designed as a MINIO alternative. AttackBlob provides public read-only blob storage with AWS S3-compliant signed upload capabilities.

## Features

- **Public Read Access** - Anyone can GET blobs via HTTP
- **AWS S3-Compatible Uploads** - Signed PUT/DELETE requests using AWS Signature V4
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
