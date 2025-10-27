# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AttackBlob is a lightweight blob storage server (MINIO alternative) built with Phoenix and Elixir. It provides:
- Public read-only access to blobs via HTTP GET
- AWS S3-compliant signed uploads via PUT requests
- No database - file-based storage with in-memory caching
- Access keys paired directly to buckets

Uses Phoenix 1.8 with Bandit as the HTTP server adapter.

## Key Architecture Components

### KeyManager GenServer
Located in `lib/attack_blob/key_manager.ex`, manages access keys in memory:
- Loads keys from `data/keys/*.json` at startup
- Uses ETS for fast concurrent lookups
- Provides `lookup/2`, `list_keys/1`, `reload/1`, `count/1` functions
- Started in application supervision tree

### Data Storage
- Keys: `./data/keys/{access_key_id}.json` (0600 permissions, plaintext with file security)
- Buckets: `./data/buckets/{bucket_name}/{object_path}`
- Configurable via `ATTACK_BLOB_DATA_DIR` environment variable

## Development Commands

### Setup
```bash
mix setup              # Install and setup dependencies
```

### Running the Application
```bash
mix phx.server         # Start Phoenix server
iex -S mix phx.server  # Start server with IEx console
```

Server runs at http://localhost:4000

### Testing
```bash
mix test                      # Run all tests
mix test test/path/file.exs   # Run specific test file
mix test --failed             # Run only previously failed tests
```

### Code Quality
```bash
mix precommit          # Run full precommit checks (compile with warnings-as-errors,
                       # unlock unused deps, format, and test)
mix format             # Format code according to .formatter.exs
mix compile --warnings-as-errors  # Compile with strict warnings
```

### Administrative Tasks
```bash
mix attack_blob.gen.key BUCKET_NAME  # Generate access key for bucket
                                     # Displays secret ONCE - save it securely!
```

## Project Architecture

### Application Structure

- **AttackBlob.Application** - OTP application supervisor that starts:
  - Telemetry for metrics
  - DNSCluster for DNS-based service discovery
  - Phoenix.PubSub for pub/sub messaging
  - AttackBlobWeb.Endpoint for HTTP requests

- **AttackBlobWeb** - Web layer entry point that provides `use` macros for:
  - `:router` - Router functionality
  - `:controller` - Controller with JSON/HTML format support
  - `:channel` - Phoenix channels
  - `:verified_routes` - Compile-time verified routes

- **Router** - Currently defines only an `/api` scope with JSON pipeline

### Key Configuration

- **Endpoint**: Uses Bandit.PhoenixAdapter instead of Cowboy
- **JSON**: Uses Jason library for JSON encoding/decoding
- **Sessions**: Cookie-based session storage with signing
- **Static files**: Served from `priv/static` at `/` with gzip support in production

## Project Guidelines

### HTTP Requests
Use the `:req` (Req) library for HTTP requests. **Avoid** `:httpoison`, `:tesla`, and `:httpc`.

### Pre-commit Workflow
Always run `mix precommit` when done with changes to ensure:
- Code compiles without warnings
- No unused dependencies
- Code is properly formatted
- All tests pass

### Elixir Best Practices

#### List Access
Lists do not support bracket notation. Use `Enum.at/2` or pattern matching:
```elixir
# INVALID
mylist[0]

# VALID
Enum.at(mylist, 0)
```

#### Variable Rebinding in Blocks
Variables are immutable but rebindable. Bind block results to variables:
```elixir
# INVALID
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# VALID
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  end
```

#### Struct Access
Never use map access syntax on structs. Use dot notation or specialized APIs:
```elixir
# INVALID
changeset[:field]

# VALID
changeset.field
Ecto.Changeset.get_field(changeset, :field)
```

#### Other Guidelines
- Never nest multiple modules in the same file (causes cyclic dependencies)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate functions should end with `?` (e.g., `active?` not `is_active`)
- OTP primitives like `DynamicSupervisor` require names in child specs
- Use `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration
- Use standard library `Date`, `Time`, `DateTime`, `Calendar` for date/time work

### Phoenix-Specific Guidelines

#### Router Scopes
Scope blocks include an optional alias prefix. Don't duplicate prefixes:
```elixir
scope "/admin", AppWeb.Admin do
  pipe_through :browser

  # This routes to AppWeb.Admin.UserLive, not AppWeb.Admin.Admin.UserLive
  live "/users", UserLive, :index
end
```

#### Phoenix 1.8 Changes
- `Phoenix.View` is no longer needed or included - don't use it
- Use function components and the new component model

### Mix Commands
- Read task docs before using: `mix help task_name`
- Debug specific test failures: `mix test test/my_test.exs`
- Avoid `mix deps.clean --all` unless absolutely necessary

### Testing Guidelines
- Use ExUnit for all tests (no manual testing)
- Use dependency injection for mocking (inject filesystem, HTTP clients, etc.)
- Prefer async tests when possible
- Use temporary directories in tests (no shared state)
- E2E tests: Use Req library to make real HTTP requests against running server
- When testing GenServers started in supervision tree, use unique names in tests

**Current test gaps:**
- AWS Signature V4 validation (complex to test with Plug.Test, needs AWS SDK integration test)
- PUT endpoint (requires signed requests, deferred until AWS SDK available for testing)
