# ADR 009: Litestream & SQLite Integration

## Context
As part of the initiative to reduce reliance on geo-replicated Longhorn storage and improve Multi-Cloud High Availability, we are migrating SQLite-based applications (e.g., `wishlist`, `actualbudget`) to use **Litestream** for continuous streaming replication to S3 (OCI Object Storage).

## Decision
We utilize a sidecar pattern to deploy Litestream alongside the main application. A generic Helm template file (`litestream_sidecar.yaml.tpl`) is used to inject the necessary sidecar and initialization logic into the `app-template` values for each relevant service.

### General Pattern
The Litestream integration relies on the following components:
1. **InitContainer (`01-litestream-restore`):** Restores the SQLite database from S3 before the main application starts. It uses the flags `-if-replica-exists` and `-if-db-not-exists` to ensure it only restores when necessary (e.g., on a fresh node or volume).
2. **Sidecar Container (`litestream`):** Runs continuously alongside the main application, using the `replicate` command to stream WAL (Write-Ahead Log) changes to S3.

## Known Edge Cases & Troubleshooting

### 1. Database Locking During Startup (Prisma & Migration Engines)
Litestream takes an exclusive read lock momentarily when it computes checksums and copies the WAL during its initial startup. If an application (like Prisma or Django) automatically runs database migrations immediately on startup, it will collide with Litestream, resulting in `database is locked` (`SQLITE_BUSY`) errors.

**Solution:**
When this collision occurs, disable the automatic migrations in the main container's entrypoint, and instead extract them into a separate `initContainer` (e.g., `02-app-migrate`) that runs *after* the Litestream restore but *before* the Litestream sidecar starts. This guarantees the migration engine has exclusive access to the database.

### 2. Connection Strings and `better-sqlite3` Query Parameters
When attempting to mitigate locking issues by appending SQLite query parameters (e.g., `?connection_limit=1&socket_timeout=15`) to the `DATABASE_URL`, be extremely cautious if the application uses Node.js and the `better-sqlite3` driver.

**The Split-Brain Bug:**
- Native tools (like the Rust-based Prisma migration engine) parse the URI correctly, strip the query parameters, and connect to the actual `prod.db`.
- `better-sqlite3` (unless explicitly configured with `uri: true`) treats the entire connection string as a literal file path. It will create a new, empty database named exactly `prod.db?connection_limit=1&socket_timeout=15`.
- This results in migrations applying to the real database, while the application starts on an empty database and crashes with "Table does not exist" errors.

**Best Practice:**
Rely on the driver's default busy timeout (e.g., `better-sqlite3` defaults to 5000ms), which is sufficient for Litestream's quick periodic checks. Do not append query string configurations to the SQLite file path unless you are certain the application's underlying driver supports URI parsing.
