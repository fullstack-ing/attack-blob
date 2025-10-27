# AttackBlob Design Document

## Project Vision

AttackBlob is a lightweight, minimal blob storage server designed as a MINIO alternative focusing on a small subset of features. It provides public read-only blob storage with AWS-compliant signed upload capabilities.

## Core Requirements

### Interface
- **HTTP API only** - No web UI
- **Mix tasks** - For administrative operations
- **No database** - File-based configuration with in-memory caching

### Storage Model
- **Public read-only buckets** - Anyone can GET blobs
- **Signed PUT uploads** - AWS S3-compliant signed requests for uploads
- **No users** - Authentication via access keys only
- **Key-to-bucket pairing** - Each access key is directly paired to a specific bucket

### Data Management

#### Access Keys
- Stored as files on disk
- Loaded into GenServer at startup for in-memory access
- Each key contains:
  - Access key ID
  - Secret key
  - Bucket name (single bucket per key)
  - Permissions (upload capability)

#### Blob Storage
- Blobs/objects stored on disk in bucket directories
- Folder structure parsed at application startup
- GenServer maintains in-memory cache of:
  - Object paths
  - Object metadata (size, content type, etc.)
  - Fast lookup for reconciliation and serving

## Architecture Overview

### GenServer Components

#### 1. KeyManager GenServer
- Manages access keys in memory
- Loads keys from disk at startup
- Validates signed requests
- Lookup: `access_key_id -> {secret_key, bucket_name}`

#### 2. BlobCache GenServer
- Maintains in-memory index of all objects
- Scans disk storage at startup
- Provides fast path lookups
- Handles reconciliation between disk and cache
- Tracks metadata per object

### HTTP API Endpoints

#### Public Read Endpoints
- `GET /:bucket/*key` - Download object ✅
- `HEAD /:bucket/*key` - Get object metadata ✅
- `GET /:bucket` - List objects ✅

#### Authenticated Write Endpoints (AWS Signature V4)
- `PUT /:bucket/*key` - Upload object ✅
- `DELETE /:bucket/*key` - Delete object ✅

#### Health Check
- `GET /health` - Health check endpoint ✅

### Mix Tasks

#### Key Management
- `mix attack_blob.gen.key` - Generate new access key for a bucket
- `mix attack_blob.list.keys` - List all access keys
- `mix attack_blob.revoke.key` - Revoke an access key

#### Bucket Management
- `mix attack_blob.gen.bucket` - Create new bucket directory
- `mix attack_blob.list.buckets` - List all buckets

#### Maintenance
- `mix attack_blob.rebuild.cache` - Rebuild blob cache from disk

## File Structure

### On-Disk Layout
```
/data
  /keys
    /{access_key_id}.json          # Individual key files
  /buckets
    /{bucket_name}
      /{object_key}                # Actual blob files
      /{nested/object/key}         # Nested paths supported
```

### Key File Format (JSON)
```json
{
  "access_key_id": "AKIA...",
  "secret_key": "wJalrXUtn...",
  "bucket": "my-bucket",
  "created_at": "2025-10-26T12:00:00Z",
  "permissions": ["put", "delete"]
}
```

## AWS S3 Compatibility

### Request Signing
- Support AWS Signature Version 4
- Two authentication methods supported:
  - **Authorization Header**: Standard AWS auth with `Authorization: AWS4-HMAC-SHA256 ...` header
  - **Presigned URLs**: Query string authentication with signature in URL parameters
- Validate signatures against stored secret keys
- Verify bucket permission for the access key

### Headers
- `Content-Type` - Set and returned correctly
- `Content-Length` - Required for uploads
- `ETag` - MD5 hash of object
- `Last-Modified` - File modification time
- `x-amz-*` headers - Support essential AWS headers

## Implementation Phases

### Phase 1: Foundation
- [x] Directory structure and configuration (`./data/keys`, `./data/buckets`)
- [x] Configuration in `runtime.exs` (data_dir, max_upload_size)
- [x] Mix task: `mix attack_blob.gen.key` - Generate bucket + access key
- [x] KeyManager GenServer (load keys, lookup, reload)
- [x] Application supervision tree (KeyManager added)
- [ ] BlobCache GenServer (basic scan and cache)

### Phase 2: Public Read API
- [x] GET object endpoint (`GET /:bucket/*key`)
- [x] HEAD object metadata endpoint (`HEAD /:bucket/*key`)
- [x] Basic error handling (404, 400, 500)
- [x] Content-Type detection (via MIME library)
- [x] ETag calculation (MD5 hash)
- [x] Last-Modified header
- [x] Cache-Control headers
- [x] Path traversal protection
- [x] Comprehensive test coverage (15 tests)

### Phase 3: Signed Upload API
- [x] AWS Signature V4 validation (AttackBlob.AWS.Signature module)
  - [x] Authorization header authentication
  - [x] Presigned URL authentication (query string parameters)
  - [x] Presigned URL expiry validation
- [x] PUT object endpoint (`PUT /:bucket/*key`)
- [x] DELETE object endpoint (`DELETE /:bucket/*key`)
- [x] Access key authorization (KeyManager integration)
- [x] Bucket access control (key-to-bucket pairing)
- [x] Permission checking ("put"/"delete" permissions required)
- [x] File writing with proper directory creation
- [x] Request body size limits (configurable max_upload_size)
- [x] ETag calculation and response
- [x] Presigned URL support verified with real-world uploader
- [x] Comprehensive integration tests (10 tests) using real HTTP requests
  - PUT with presigned URLs (text, binary, with headers)
  - DELETE with presigned URLs
  - Signature validation (rejects wrong signatures)
  - Expiry validation (rejects expired URLs)
  - Bucket access control
- [ ] File writing updates cache (BlobCache not yet implemented)

### Phase 4: Mix Tasks
- [x] `mix attack_blob.gen.key` - Generate access keys and create buckets
- [x] `mix attack_blob.list.keys` - List all access keys (11 tests)
- [x] `mix attack_blob.list.buckets` - List all buckets (13 tests)
- [x] `mix attack_blob.revoke.key` - Revoke an access key (10 tests)

### Phase 5: Polish
- [x] DELETE endpoint (`DELETE /:bucket/*key`)
  - AWS Signature V4 authentication
  - Bucket access control
  - Permission checking ("delete" required)
  - Returns 204 No Content on success
  - Test coverage (4 tests for error cases)
- [x] LIST bucket endpoint (`GET /:bucket`) (13 tests)
  - Returns JSON list of objects with metadata
  - Query parameters: prefix, delimiter, max_keys
  - Supports hierarchical listing with common prefixes
  - Pagination with is_truncated flag
- [x] Comprehensive error handling (401, 403, 404, 400, 413, 500)
- [x] Logging and telemetry (warnings for security events, errors for failures)
- [x] Health check endpoint (`GET /health`) (8 tests)
  - Reports status of KeyManager
  - Reports status of data directory
  - Returns 200 for healthy, 503 for unhealthy
  - No authentication required
- [ ] Cache reconciliation on file system changes (BlobCache not implemented - serving directly from disk)

## Open Questions

1. **Object naming**: Should we enforce S3 object key restrictions?
2. **Bucket creation**: Auto-create buckets on first upload or require explicit creation?
3. **Cache invalidation**: How to handle external file system modifications?
4. **Multipart uploads**: Support for large files?
5. **Storage limits**: Per-bucket quotas?
6. **Presigned URLs**: Support for time-limited public upload URLs?
7. **CORS**: Support for cross-origin requests?

## Configuration

### Runtime Configuration (runtime.exs)
```elixir
config :attack_blob,
  data_dir: System.get_env("ATTACK_BLOB_DATA_DIR", "./data"),
  max_upload_size: 5_000_000_000  # 5GB default

config :attack_blob, :cors,
  origins: ~r/.*/ | ["https://example.com"],  # "*" or list of origins
  max_age: 600,  # seconds
  allow_credentials: true
```

### Environment Variables
- `ATTACK_BLOB_DATA_DIR` - Data directory path (default: `./data`)
- `ATTACK_BLOB_MAX_UPLOAD_SIZE` - Max upload size in bytes (default: `5368709120`)
- `CORS_ALLOWED_ORIGINS` - Comma-separated origins or `*` for all (default: `*`)
- `CORS_MAX_AGE` - CORS preflight cache time in seconds (default: `600`)
- `CORS_ALLOW_CREDENTIALS` - Allow credentials (`true`/`false`, default: `true`)

## Development Guidelines

### Testing
- Use ExUnit tests for all functionality (not manual testing)
- Use dependency injection for testing and mocks
  - Inject filesystem operations for GenServers
  - Inject HTTP clients for external requests
  - Use behaviours to define contracts
- Prefer async tests when possible
- Use temporary directories in tests (no shared state)
- Conn-based tests (via `ConnCase`) effectively test the full request/response cycle
- E2E tests with Req can be added later if needed for full HTTP stack testing

## Security Considerations

- Validate all object keys for path traversal attacks
- Limit upload sizes to prevent DoS
- Rate limiting on uploads (future consideration)
- Ensure secret keys are never exposed in responses
- Validate bucket names (no special characters, path traversal)

## Performance Considerations

- In-memory cache should speed up object lookups
- Consider ETS for large-scale object indexes
- Stream large file uploads/downloads
- Use file system efficiently (avoid deep nesting)

## Future Enhancements

- Metrics and monitoring
- Background workers for cache reconciliation
- Object versioning
- Access logs
- Bucket policies
- Object tagging
- Storage analytics
