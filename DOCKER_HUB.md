# AttackBlob - Lightweight S3-Compatible Blob Storage

A minimal, production-ready blob storage server designed as a MINIO alternative. AttackBlob provides public read-only blob storage with AWS S3-compliant signed upload capabilities.

## Features

- **Public Read Access** - Anyone can GET blobs via HTTP
- **AWS S3-Compatible Uploads** - Signed PUT/DELETE requests using AWS Signature V4
- **Multipart Uploads** - Chunked uploads for large files (up to 5TB)
- **Presigned URLs** - Support for time-limited upload URLs
- **Key-Based Authentication** - Simple access key to bucket pairing
- **No Database** - File-based configuration with in-memory caching
- **CORS Support** - Configurable cross-origin resource sharing

## Quick Start

```bash
# Pull and run
docker pull fullstacking/attack-blob:latest

docker run -d \
  --name attack-blob \
  -p 4004:4004 \
  -v attack_blob_data:/app/data \
  -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
  fullstacking/attack-blob:latest
```

## Management CLI

```bash
# Generate an access key and bucket
docker exec attack-blob /app/bin/gen_key my-bucket

# List all access keys
docker exec attack-blob /app/bin/list_keys

# List all buckets
docker exec attack-blob /app/bin/list_buckets

# Revoke an access key
docker exec attack-blob /app/bin/revoke_key AKIAXXXXXXXX
```

## Docker Compose

```yaml
version: '3.8'
services:
  attack-blob:
    image: fullstacking/attack-blob:latest
    ports:
      - "4004:4004"
    volumes:
      - attack_blob_data:/app/data
    environment:
      SECRET_KEY_BASE: "your-secret-key-here"
      PHX_HOST: "blobs.example.com"
      CORS_ALLOWED_ORIGINS: "*"

volumes:
  attack_blob_data:
```

## Environment Variables

### Required
- `SECRET_KEY_BASE` - Secret key for signing (generate with `openssl rand -base64 48`)

### Optional
- `PHX_HOST` - Hostname for URL generation (default: localhost)
- `PORT` - HTTP port (default: 4004)
- `ATTACK_BLOB_DATA_DIR` - Data directory (default: /app/data)
- `ATTACK_BLOB_MAX_UPLOAD_SIZE` - Max upload size in bytes (default: 5GB)
- `CORS_ALLOWED_ORIGINS` - Comma-separated allowed origins (default: *)
- `CORS_MAX_AGE` - CORS preflight cache in seconds (default: 600)
- `CORS_ALLOW_CREDENTIALS` - Allow credentials (default: true)

## Volumes

Mount `/app/data` for persistent storage:
- `/app/data/keys/` - Access key configurations
- `/app/data/buckets/` - Blob storage by bucket
- `/app/data/multipart/` - Temporary multipart upload storage

## Usage Example

```bash
# 1. Start container
docker-compose up -d

# 2. Generate access key
docker-compose exec attack-blob /app/bin/gen_key test-bucket

# 3. Upload (with AWS SDK)
# Use the access key and secret from step 2

# 4. Download (public, no auth)
curl http://localhost:4004/test-bucket/myfile.txt
```

## Links

- **GitHub**: https://github.com/fullstacking/attack-blob
- **Documentation**: https://github.com/fullstacking/attack-blob/blob/main/README.md
- **Issues**: https://github.com/fullstacking/attack-blob/issues

## License

MIT
