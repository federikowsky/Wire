# Wire - Core Specifications

**Version**: 1.0.0  
**Type**: Zero-allocation HTTP/1.1 parser for D  
**Backend**: llhttp (Node.js HTTP parser)

---

## Architecture

### Component Structure

```
wire/
├── types.d       # StringView (16B), ParsedHttpRequest (cache-aligned)
├── bindings.d    # llhttp C FFI
├── parser.d      # Parser, ParserPool, parseHTTP()
└── package.d     # Public exports
```

---

## Core Data Structures

### StringView (16 bytes)

Zero-copy string representation optimized for register passing (RDI, RSI on x86-64):

```d
struct StringView {
    const(char)* ptr;     // 8 bytes
    size_t length;        // 8 bytes
}
```

**Properties**:
- `@nogc @safe pure nothrow` all operations
- Case-sensitive `opEquals`
- Case-insensitive `equalsIgnoreCase` (ASCII only, SIMD target)
- Range interface (empty, front, popFront)
- Slicing without allocation

---

### ParsedHttpRequest (cache-optimized, 64-byte aligned)

**Layout Strategy**: Hot data in first cache line (64 bytes), cold data separate.

```d
align(64) struct ParsedHttpRequest {
    // CACHE LINE 0 (0-63 bytes): HOT PATH
    RoutingInfo {
        StringView method;      // 16 bytes [0-15]
        StringView path;        // 16 bytes [16-31]
        StringView query;       // 16 bytes [32-47]
        ushort statusCode;      // 2 bytes  [48-49]
        ubyte versionMajor;     // 1 byte   [50]
        ubyte versionMinor;     // 1 byte   [51]
        ubyte flags;            // 1 byte   [52] (bit 0=keepAlive, bit 1=upgrade)
        ubyte numHeaders;       // 1 byte   [53]
        ubyte[10] _padding;     // 10 bytes [54-63]
    }
    
    // CACHE LINE 1+: COLD PATH
    ContentInfo {
        Header[64] headers;     // 2048 bytes (32 bytes × 64)
        StringView body;        // 16 bytes
        const(char)* errorPos;  // 8 bytes
        int errorCode;          // 4 bytes
    }
}
```

**Design Rationale**:
- Routing decisions (method/path) use only 1 cache line fetch
- Header scanning deferred until `getHeader()` called
- 64-header limit (compile-time constant, changeable)

---

## API Surface

### Entry Point

```d
@nogc nothrow
ParserWrapper parseHTTP(const(ubyte)[] data);
```

Returns RAII wrapper. Parser auto-released on scope exit.

---

### Request Line Access

```d
@nogc @safe pure nothrow
{
    StringView getMethod();           // "GET", "POST", etc.
    StringView getPath();             // "/api/users"
    StringView getQuery();            // "page=2" (if present)
    StringView getVersion();          // "1.1" or "1.0"
    ubyte getVersionMajor();          // 1
    ubyte getVersionMinor();          // 0 or 1
}
```

---

### Header Access

```d
@nogc @trusted pure nothrow
{
    StringView getHeader(const(char)[] name);  // Case-insensitive, O(n)
    bool hasHeader(const(char)[] name);        // Existence check
    auto getHeaders();                          // Range for iteration
}
```

**Implementation**: Linear scan with `equalsIgnoreCase`. Cache-friendly (~1 μs for 20 headers).

---

### Content & Metadata

```d
@nogc @safe pure nothrow
{
    StringView getBody();          // Request body (if present)
    bool shouldKeepAlive();        // Connection: keep-alive flag
    bool isUpgrade();              // Connection: upgrade flag
}
```

---

### Error Handling

```d
@nogc @safe pure nothrow
{
    int getErrorCode();            // 0 = success
    const(char)* getErrorReason(); // Error message from llhttp
}
```

**Error Codes** (from llhttp_errno):
- `0` = HPE_OK
- `6` = HPE_INVALID_METHOD
- `7` = HPE_INVALID_URL
- `11` = HPE_INVALID_CONTENT_LENGTH
- `24` = HPE_USER (custom, e.g. header overflow)

---

## Memory Management

### Allocation Strategy

**Zero GC**:
- All production code is `@nogc nothrow`
- C heap used (calloc/free) for parser structures
- Thread-local pooling for parser reuse

**Per-Thread**:
```d
static Parser* t_parser;   // TLS variable
static bool t_busy;         // TLS flag
```

**Lifecycle**:
1. First request: `calloc(Parser)` + `llhttp_init()`
2. Subsequent: `llhttp_reset()` + reuse
3. Scope exit: Release to pool (not freed)
4. Thread exit: Parser leaked intentionally (TLS cleanup)

**Per-Request**:
- Allocations: **0 bytes**
- Stack: ~64 bytes (ParsedHttpRequest on stack in callbacks)

---

## Thread Safety

**Model**: Thread-local pool, no shared state.

- ❌ Not thread-safe: Don't share parser across threads
- ✅ Thread-local: Each thread gets own parser (TLS)
- ✅ No locking: Zero synchronization overhead

**Implications**:
- Safe for multi-threaded servers (one parser per worker thread)
- Not safe for thread-pool with shared parsers

---

## Performance Characteristics

### Timing (LDC 1.41, ARM64 M2)

| Metric | Value |
|--------|-------|
| Simple GET (37B) | 7 μs |
| Browser request (1KB, 20 headers) | 1 μs |
| REST API (1.5KB, JWT) | 1 μs |
| Webhook (2.1KB, 19 headers) | 1 μs |

### Complexity

| Operation | Time | Notes |
|-----------|------|-------|
| Parse | O(n) | n = request size |
| Header lookup | O(h) | h = header count (linear scan) |
| Header iteration | O(h) | Sequential access |
| Body access | O(1) | Pointer copy only |

### Memory

| Component | Size |
|-----------|------|
| StringView | 16 bytes |
| RoutingInfo | 64 bytes |
| Header | 32 bytes |
| ParsedHttpRequest | ~2.1 KB |
| Parser (C structs) | ~800 bytes |
| **Total per thread** | ~3 KB |

---

## Design Decisions

### 1. Cache Alignment

**Problem**: Random header access causes cache misses.  
**Solution**: Pack routing info (method, path, version) in first 64 bytes.  
**Result**: Routing decisions = 1 L1 cache line fetch.

### 2. Zero Allocation

**Problem**: GC pauses in high-throughput scenarios.  
**Solution**: `@nogc` + C heap + thread-local pooling.  
**Result**: Zero GC pressure, predictable latency.

### 3. Linear Header Scan

**Problem**: Hash table overhead (allocation, collisions).  
**Solution**: Sequential scan with cache-friendly layout.  
**Result**: Fast for typical request (5-20 headers), no allocation.

### 4. StringView vs string

**Problem**: D strings require GC allocation.  
**Solution**: Zero-copy view (ptr + length).  
**Result**: No allocation, register-passed (2 registers on x86-64).

### 5. Thread-Local Pool

**Problem**: Lock contention on shared parser pool.  
**Solution**: Each thread owns one parser (TLS).  
**Result**: Zero synchronization, ~3KB memory/thread.

---

## Limitations

### Protocol Support

- ✅ HTTP/1.0, HTTP/1.1
- ❌ HTTP/2 (requires nghttp2 wrapper)
- ❌ HTTP/3 (requires QUIC + QPACK)

### Features

- ✅ All standard methods (GET, POST, PUT, DELETE, etc.)
- ✅ Headers (case-insensitive, iteration)
- ✅ Body (zero-copy view)
- ❌ Chunked encoding parsing (detected, not parsed)
- ❌ Multipart parsing (raw body only)
- ❌ WebSocket protocol (upgrade detected only)

### Constraints

- Max 64 headers (compile-time constant)
- ASCII-only case-insensitive comparison (no UTF-8)
- Single request per parse (no pipelining)

---

## llhttp Integration

**Version**: 9.3.0  
**Role**: Core HTTP parsing logic (state machine)

**Callbacks** (extern(C) @nogc nothrow):
- `cb_on_message_begin`
- `cb_on_url`, `cb_on_method`, `cb_on_version`
- `cb_on_header_field`, `cb_on_header_value`
- `cb_on_headers_complete`
- `cb_on_body`
- `cb_on_message_complete`

**Data Flow**:
1. Wire calls `llhttp_execute(data)`
2. llhttp invokes callbacks as it parses
3. Callbacks populate `ParsedHttpRequest` fields
4. On error, set `errorCode` and return
5. On success, user accesses via API methods
