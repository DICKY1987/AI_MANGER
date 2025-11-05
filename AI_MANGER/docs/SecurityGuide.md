# Security Guide

## Module Hardening

All core modules have been hardened with the following features:

### Cross-Volume Linking with Fallbacks

The system attempts to create directory links in order of preference:
1. **Symlinks** - Best option, requires Developer Mode on Windows
2. **Junctions** - Works across volumes on same drive
3. **Copy** - Last resort fallback, warns user

This ensures the system works even in restricted environments.

### Race Condition Safety

All modules use resource locking to prevent race conditions:
- File-based locks with configurable timeouts
- Automatic lock cleanup even on exceptions
- Sequential retry logic for transient failures

### Quarantine Mechanism

When replacing directories with links, the original content is moved to quarantine rather than deleted:
- Timestamped quarantine paths with unique IDs
- Preserves data in case of misconfiguration
- Default location: `%LOCALAPPDATA%\CLI_Quarantine`

### Collision Resolution

The MasterBin plugin handles executable name collisions:
- Priority-based source ordering
- Collision tracking and reporting
- DenyList support for system executables

### Error Handling & Retry Logic

All operations include comprehensive error handling:
- Automatic retry with exponential backoff
- Detailed error logging and reporting
- Graceful degradation when possible

### Validation & Reporting

Enhanced validation throughout:
- Input validation for secret names and values
- Configuration validation before operations
- JSON reports include error details
- Health status indicators

## Security Best Practices

### Secrets Management

The Secrets vault uses DPAPI (Data Protection API):
- User-scoped encryption (tied to Windows user account)
- Never displays secrets in console output
- Clipboard-only for secret retrieval
- Locked file access to prevent race conditions

### Audit Alerts

File access monitoring with Event 4663:
- Allow-list based filtering
- Optional webhook notifications
- JSONL append-only audit log
- Locked writes to prevent corruption

### Reports Security

All JSON reports are written safely:
- Directory creation with error handling
- Atomic write operations where possible
- Error details included without sensitive data
- Timestamped for audit trails

## Task Definition of Done (DoD)

Each hardened task ensures:
1. **Input Validation** - All parameters validated before use
2. **Error Handling** - Try-catch blocks with meaningful warnings
3. **Resource Cleanup** - Locks released, temp files removed
4. **Retry Logic** - Transient failures retried automatically
5. **Reporting** - Success/failure status clearly communicated
6. **Logging** - Verbose logging for troubleshooting
7. **Testing** - Unit tests verify hardening features

## Known Limitations

- Symlinks require Developer Mode on Windows 10/11
- Junctions don't work across different physical volumes
- DPAPI secrets are tied to Windows user profile
- File locking may timeout in high-contention scenarios
- Event 4663 auditing requires Administrator privileges to configure

