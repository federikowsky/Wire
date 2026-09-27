# Wire - High-Performance HTTP Parser for D

> **Version**: 1.0.4  
> **Status**: Production Ready  
> **License**: MIT  
> **Repository**: [github.com/federikowsky/Wire](https://github.com/federikowsky/Wire)  
> **Last Updated**: 2025-12-15

---

## Executive Summary

Wire is a zero-GC-allocation, high-performance HTTP/1.1 parser for the D programming language. Built as a wrapper around the battle-tested [llhttp](https://github.com/nodejs/llhttp) C library (used by Node.js), Wire achieves **1-7 microsecond** parsing times with throughput exceeding **2 GB/sec** while maintaining complete `@nogc` compatibility.

### Key Metrics

- **Parse Time**: 1-7 μs per request (typical)
- **Throughput**: 300-2,000 MB/sec depending on complexity
- **Memory**: One parser per live wrapper, plus at most one idle parser per thread
- **Allocations**: No GC allocations; native allocations when creating a parser
- **Header Limit**: 64 headers per request
- **Supported Methods**: GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH, etc.

---

## Architecture

### Design Principles

1. **Zero GC Allocation**: No GC pressure during parsing
2. **Cache Optimization**: Hot data in first 64 bytes (L1 cache line)
3. **Zero-Copy**: `StringView` for all string data
4. **Dual API Design**: 
   - **TLS API** (`parseHTTP`): Exclusive request leases with a thread-local idle cache
   - **Owned API** (`createParser`): Per-instance parsers for fiber-safe, per-connection use
5. **Battle-Tested**: llhttp handles billions of requests/day in Node.js

### Component Structure

```
wire/
├── types.d          # StringView, ParsedHttpRequest (core data structures)
├── bindings.d       # C FFI to llhttp (extern declarations)
├── parser.d         # Parser, ParserPool, parseHTTP() (main logic)
└── package.d        # Public API exports

c/
├── llhttp.c         # llhttp core implementation
├── llhttp.h         # llhttp C header
├── api.c            # llhttp API functions
└── http.c           # HTTP protocol parsing logic
```

### Data Structures

#### StringView (16 bytes)

Zero-copy string representation optimized for register passing:

```d
struct StringView {
    const(char)* ptr;    // 8 bytes - pointer to string data
    size_t length;       // 8 bytes - string length

    // --- Constructors ---
    this(const(char)[] s) pure nothrow @nogc @trusted;
    static StringView makeNull() pure nothrow @nogc @safe;
    
    // --- Operators ---
    StringView opSlice(size_t start, size_t end) const pure nothrow @nogc @trusted;
    bool opEquals(const(char)[] other) const pure nothrow @nogc @trusted;
    
    // --- Comparison ---
    bool equalsIgnoreCase(const(char)[] other) const pure nothrow @nogc @trusted;
    
    // --- Range Interface ---
    bool empty() const pure nothrow @nogc @safe;
    char front() const pure nothrow @nogc @trusted;
    void popFront() pure nothrow @nogc @trusted;
    
    // --- Null Check ---
    bool isNull() const pure nothrow @nogc @safe;  // ptr is null (not found vs empty)
    
    // --- Debug ---
    string toString() const;  // uses GC, for debugging only
}
```

**Key Methods**:
- `makeNull()` - Creates a null view (indicates "not found")
- `isNull()` - Returns true if ptr is null (distinguishes "not found" from "empty string")
- `equalsIgnoreCase()` - Case-insensitive ASCII comparison
- `opSlice()` - Zero-allocation substring

#### ParsedHttpRequest (64-byte aligned)

Cache-optimized request structure with hot/cold data separation:

```d
align(64) struct ParsedHttpRequest {
    // --- CACHE LINE 0: ROUTING INFO (0-63 bytes) ---
    align(64) struct RoutingInfo {
        StringView method;      // [0-15]  GET, POST, etc.
        StringView path;        // [16-31] /api/users
        StringView query;       // [32-47] page=2&limit=10 (without '?')
        ushort statusCode;      // [48-49] HTTP status (for responses)
        ubyte versionMajor;     // [50]    1
        ubyte versionMinor;     // [51]    0 or 1
        ubyte flags;            // [52]    keep-alive (0x01), upgrade (0x02)
        ubyte numHeaders;       // [53]    0-64
        bool messageComplete;   // [54]    set by on_message_complete callback
        ubyte[9] _padding;      // [55-63] alignment padding
    }
    RoutingInfo routing;
    
    static assert(RoutingInfo.sizeof == 64);  // Exactly one cache line
    
    // --- CACHE LINE 1+: CONTENT INFO ---
    align(64) struct ContentInfo {
        align(32) struct HttpHeader {
            StringView name;    // Header name
            StringView value;   // Header value
        }
        
        enum MAX_HEADERS = 64;
        HttpHeader[MAX_HEADERS] headers;  // Fixed array
        
        StringView body;        // Request body
        const(char)* errorPos;  // Error position in input
        int errorCode;          // 0 = success
    }
    ContentInfo content;
}
```

**Benefits**:
- Routing decisions use only first cache line (64 bytes)
- Header scanning deferred until needed
- Predictable memory layout for SIMD optimization

> [!NOTE]
> The `messageComplete` flag in `RoutingInfo` is set by the `on_message_complete` callback and can be used by server integrations (e.g., Aurora) to detect when a full HTTP message has been received.

---

## API Reference

### Parsing Entry Point

```d
@nogc nothrow
auto parseHTTP(const(ubyte)[] data);
```

Returns a move-only `ParserWrapper` with RAII cleanup. Each live wrapper exclusively owns its parser; later calls do not overwrite its result. The parser is cached or freed when the wrapper goes out of scope. Native allocation failure raises `OutOfMemoryError`; a parse error returns a non-null wrapper with error details.

The request reference is valid only while its wrapper owns the parser. `StringView` values borrow the input buffer, which must remain alive and unchanged during use. Moving a wrapper transfers parser ownership, not buffer ownership.

**Example**:
```d
auto req = parseHTTP(httpData);
if (!req) {
    // Parse failed
    writeln("Error: ", req.getErrorCode());
    return;
}

// Successfully parsed
auto method = req.getMethod();
auto path = req.getPath();
```

### Owned Parser API (Per-Instance)

For use cases requiring dedicated parser instances (e.g., Aurora fibers, per-connection parsers), Wire provides an owned parser API that allocates a parser on the heap.

**Functions**:
```d
@nogc nothrow
{
    ParserHandle createParser();                                    // Create dedicated parser
    void destroyParser(ParserHandle handle);                        // Free parser
    llhttp_errno parseHTTPWith(ParserHandle handle, const(ubyte)[] data);  // Parse with owned parser
    ref ParsedHttpRequest getRequest(ParserHandle handle);          // Get parsed request
}
```

**Type**:
```d
alias ParserHandle = void*;  // Opaque handle to parser instance
```

**Usage Pattern** (Aurora/fiber-safe):
```d
// Create parser per connection/fiber
ParserHandle conn = createParser();
assert(conn !is null, "Failed to allocate parser");

// Parse requests
llhttp_errno err = parseHTTPWith(conn, requestData);
if (err == llhttp_errno.HPE_OK) {
    ref ParsedHttpRequest req = getRequest(conn);
    // Use req.routing.path, req.getHeader(), etc.
    // StringView slices point into requestData buffer
} else {
    // Handle parse error
    ref ParsedHttpRequest req = getRequest(conn);
    writeln("Error: ", req.getErrorCode());
}

// Cleanup when connection closes
destroyParser(conn);
```

**Key Differences from TLS API**:

| Feature | TLS API (`parseHTTP`) | Owned API (`createParser`) |
|---------|----------------------|---------------------------|
| **Allocation** | Native allocation when no idle parser is available | Per-instance native allocation |
| **Lifetime** | RAII (automatic) | Manual (`destroyParser`) |
| **Use Case** | Independent RAII requests, including overlapping fibers | Explicit per-connection reuse |
| **Memory** | One parser per live wrapper plus at most one idle parser per thread | One parser per handle |
| **Thread Safety** | Exclusive ownership; synchronize transfer between threads | Exclusive ownership; synchronize transfer between threads |

**When to Use Owned API**:
- ✅ Per-connection parsers (one parser per TCP connection)
- ✅ Aurora fiber-based servers (fiber-safe, no TLS dependencies)
- ✅ Long-lived connections with multiple requests
- ✅ When you need explicit control over parser lifetime

**When to Use TLS API**:
- ✅ Single-threaded request handling
- ✅ Sequential request processing
- ✅ Overlapping request lifetimes, including interleaved fibers
- ✅ Default choice for most applications

### Request Line Methods

```d
@nogc @safe pure nothrow
{
    StringView getMethod();              // "GET", "POST", etc.
    StringView getPath();                // "/api/users"
    StringView getQuery();               // "page=2&limit=10"
    
    ubyte getVersionMajor();             // 1
    ubyte getVersionMinor();             // 0 or 1
    StringView getVersion();             // "1.0" or "1.1"
}
```

### Query Parameter Methods

```d
@nogc @trusted pure nothrow
{
    StringView getQueryParam(const(char)[] name);  // Get parameter value
    bool hasQueryParam(const(char)[] name);        // Check parameter existence
}
```

**Query Parameter Example**:
```d
// URL: /search?q=hello&page=2&limit=10
auto req = parseHTTP(data);

auto query = req.getQueryParam("q");      // "hello"
auto page = req.getQueryParam("page");    // "2"
auto limit = req.getQueryParam("limit");  // "10"

if (req.hasQueryParam("debug")) {
    // ?debug flag was present
}
```

### Header Methods

```d
@nogc @trusted pure nothrow
{
    StringView getHeader(const(char)[] name);     // Case-insensitive lookup
    bool hasHeader(const(char)[] name);           // Check existence
    
    auto getHeaders();                            // Iterate all headers
}
```

**Header Iteration Example**:
```d
foreach (header; req.getHeaders()) {
    writeln(header.name, ": ", header.value);
}
```

### Content Methods

```d
@nogc @safe pure nothrow
{
    StringView getBody();                // Request body (if any)
    
    bool shouldKeepAlive();              // Connection: keep-alive
    bool isUpgrade();                    // Connection: upgrade
}
```

### Error Handling

```d
@nogc @safe pure nothrow
{
    int getErrorCode();                  // 0 = success, >0 = error
    const(char)* getErrorReason();       // Error description
}
```

**Error Codes** (subset):
- `0` = Success
- `6` = Invalid method
- `7` = Invalid URL
- `9` = Invalid version
- `10` = Invalid header token
- `11` = Invalid Content-Length
- `24` = Header overflow (>64 headers)

### HTTP Utility Functions

Wire provides utility functions for HTTP header normalization and buffer operations:

```d
@nogc nothrow pure @safe
{
    bool isWhitespace(char c);                                    // Check if char is space or tab (OWS)
    const(char)[] trimWhitespace(const(char)[] s);                // Trim OWS (zero-copy)
    size_t findHeaderEnd(const(ubyte)[] existing, const(ubyte)[] append);  // Find \r\n\r\n across buffers
}
```

**Functions**:

- **`isWhitespace(char c)`**: Checks if a character is Optional Whitespace (space or tab) according to RFC 7230.
- **`trimWhitespace(const(char)[] s)`**: Removes Optional Whitespace from the beginning and end of a string (zero-copy, returns slice).
- **`findHeaderEnd(const(ubyte)[] existing, const(ubyte)[] append)`**: Finds the HTTP header terminator (`\r\n\r\n`) even if split across two buffers. Returns number of bytes from append buffer needed to complete the terminator (0 if not found).

**Example**:
```d
import wire.types;

// Check whitespace
if (isWhitespace(' ')) { /* true */ }
if (isWhitespace('\t')) { /* true */ }

// Trim header value
auto value = trimWhitespace("  Content-Type  ");  // "Content-Type" (zero-copy)

// Find header end across buffer boundary
const(ubyte)[] existing = cast(ubyte[])"GET / HTTP/1.1\r\nHost: example.com\r\n";
const(ubyte)[] append = cast(ubyte[])"\r\nbody";
size_t bytesNeeded = findHeaderEnd(existing, append);  // Returns 2 (bytes from append)
```

---

## Performance Characteristics

### Benchmark Results

All benchmarks run on: **LDC 1.41, macOS ARM64, M2 chip**

| Request Type | Size | Headers | Parse Time | Throughput |
|-------------|------|---------|------------|-----------|
| Simple GET | 37 B | 1 | 7 μs | 5 MB/s |
| Chrome Browser | 1.0 KB | 20 | 1 μs | 983 MB/s |
| REST API + JWT | 1.5 KB | 11 | 1 μs | 1,442 MB/s |
| GraphQL Query | 753 B | 7 | <1 μs | ∞ MB/s |
| Stripe Webhook | 2.1 KB | 19 | 1 μs | 2,023 MB/s |
| Multipart Upload | 1.1 KB | 19 | 1 μs | 1,081 MB/s |
| SOAP XML | 1.0 KB | 6 | <1 μs | ∞ MB/s |

### Memory Profile

Each parser owns a `Parser` structure (including all 64 header entries), a
`llhttp_t` handle and `llhttp_settings_t` settings on the native heap. Sizes depend
on the target ABI. Every live wrapper owns one parser, and each thread caches at
most one additional idle parser. Sequential reuse needs no new allocations;
cold or overlapping calls may allocate. No request strings are copied.

### Scaling Characteristics

- **Header Count**: O(n) linear scan, no hash table overhead
- **Header Lookup**: ~1 μs regardless of position (cache-efficient)
- **Body Size**: O(1) copy pointer and length only
- **Thread Safety**: Thread-local pools, no locking

---

## Build System

### Prerequisites

- **D Compiler**: LDC 1.35+ (recommended) or DMD 2.105+
- **C Compiler**: clang or gcc with C99 support
- **Make**: Standard GNU make

### Build Targets

```bash
make              # Build and run tests
make test         # Run test suite (45 tests)
make test-verbose # Run tests with detailed timing
make test-debug   # Run debug tests with step-by-step analysis
make lib          # Build static library (libwire.a)
make clean        # Remove all build artifacts
make debug        # Build with debug symbols
make help         # Show all targets
```

### Build Output

All artifacts go to `build/` directory:

```
build/
├── api.o           # C object files
├── http.o
├── llhttp.o
├── bindings.o      # D object files
├── package.o
├── parser.o
├── types.o
├── tests           # Test executable
├── debug_tests     # Debug test executable
└── libwire.a       # Static library (when built)
```

### Integration with Dub

```json
{
    "dependencies": {
        "wire": "~>1.0.0"
    }
}
```

Then:
```d
import wire;

void handleRequest(const(ubyte)[] data) @nogc nothrow {
    auto req = parseHTTP(data);
    // Use req...
}
```

---

## Test Suite

### Test Coverage

**Standard Tests** (50 tests):
- ✅ HTTP methods (GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH, TRACE, CONNECT)
- ✅ Query strings (parsing, getQueryParam, flags, URL encoding)
- ✅ Headers (multiple, case-insensitive, empty values, iteration, overflow)
- ✅ HTTP versions (1.0, 1.1, keep-alive, close)
- ✅ Edge cases (long paths, long values, header limits, null bytes)
- ✅ Error handling (invalid version, malformed requests, invalid headers)
- ✅ Security (multiple same-name headers, special characters, URL encoding)
- ✅ Real-world scenarios (browser, API, chunked encoding)
- ✅ Owned Parser API (per-instance parsers, reuse, error handling, cleanup)
- ✅ HTTP Utility Functions (isWhitespace, trimWhitespace, findHeaderEnd)

**Debug Tests** (7 complex scenarios):
- Simple GET (baseline)
- Chrome browser request (20+ headers)
- REST API with JWT token + large JSON
- GraphQL query with variables
- Stripe webhook (2KB payload, 19 headers)
- Multipart file upload
- SOAP XML request

### Running Tests

```bash
# Quick test (45 tests)
make test

# Verbose mode (with timing stats)
make test-verbose

# Debug mode (step-by-step analysis)
make test-debug
```

**Debug Test Output Example**:
```
🔍 DEBUG TEST: REST API POST with JWT Token & Large JSON Payload
📥 RAW INPUT:
  Length: 1512 bytes
  Hex dump: [shown]
  ASCII: [shown with \r\n escaped]

⏱️  PARSING PHASES:
  [Phase 1] Acquiring parser... ✓ <1 μs
  [Phase 2] llhttp parsing...   ✓ 1 μs
  Total: 1 μs

✅ PARSE RESULT: Successful

📋 REQUEST LINE:
  Method: 'POST' (4 bytes) [<1 μs]
  Path: '/api/v2/users/bulk-create' (24 bytes) [<1 μs]
  Version: HTTP/1.1 => '1.1' [<1 μs]

📨 HEADERS: [11 headers shown with sizes]
🔎 HEADER LOOKUP TESTS: [timing shown]
📦 BODY: [612 bytes JSON shown]
🔌 CONNECTION FLAGS: [keep-alive, upgrade shown]

📊 PERFORMANCE SUMMARY:
  Total time:      1 μs
  Throughput:      1,442 MB/sec
```

---

## Technical Details

### @nogc Compatibility

**100% of production code is `@nogc nothrow`**:

- ✅ All `types.d` methods
- ✅ All `parser.d` functions and callbacks
- ✅ All `bindings.d` C declarations
- ❌ Tests use GC for convenience (intentional)

### Memory Management

**Allocation Points** (all C heap, not GC):

1. **Parser Cache** (TLS API - on a cold call or while all parsers are leased):
   ```d
   Parser* p = cast(Parser*) createParser();
   ```

2. **llhttp Structures** (once per parser):
   ```d
   handle = cast(llhttp_t*) calloc(1, llhttp_t.sizeof);
   settings = cast(llhttp_settings_t*) calloc(1, llhttp_settings_t.sizeof);
   ```

3. **Owned Parser** (Owned API - per-instance):
   ```d
   Parser* p = cast(Parser*) calloc(1, Parser.sizeof);
   // Plus handle and settings (same as above)
   // Freed via destroyParser()
   ```

4. **During llhttp execution**: No allocations. `parseHTTP()` first acquires an
   exclusive parser, which can require native allocation. Releasing a wrapper
   caches its parser if the current thread's idle slot is empty, otherwise frees
   it. Thread exit frees the idle slot only.

### Thread Safety

**TLS API** (`parseHTTP`):
- ✅ **Exclusive leases**: Nested and overlapping calls use independent parsers
- ✅ **Thread-local idle cache**: A live lease is never stored in the cache
- ✅ **Thread transfer**: A wrapper may outlive its originating thread when moved
  with synchronization; its eventual release uses the receiving thread's cache
- ❌ **Concurrent sharing**: Do not access or destroy the same wrapper concurrently

**Owned API** (`createParser`):
- ✅ **Fiber-safe**: Each parser instance is independent
- ✅ **Per-connection**: One parser per connection/fiber
- ✅ **No TLS dependencies**: Suitable for Aurora fibers

**Thread-Local Model** (TLS API):
```d
static Parser* t_parser;  // TLS idle slot only

// Acquire parser (reuses if available)
auto wrapper = parseHTTP(data);  // Detaches idle slot, or creates a parser

// Automatically released on scope exit
```

**Per-Instance Model** (Owned API):
```d
// Each connection/fiber gets its own parser
ParserHandle conn = createParser();  // Independent instance
parseHTTPWith(conn, data);
destroyParser(conn);  // Explicit cleanup
```

### Safety Attributes

```d
// Public API (user-facing)
@safe pure nothrow @nogc
{
    getMethod(), getPath(), getHeader(), etc.
}

// Internal operations (pointer manipulation)
@trusted pure nothrow @nogc
{
    StringView constructor, header lookup, iteration
}

// C callbacks (FFI boundary)
extern(C) @nogc nothrow
{
    cb_on_url, cb_on_header_field, etc.
}
```

---

## Usage Examples

### Basic Parsing

```d
import wire;

void handleRequest(const(ubyte)[] data) @nogc nothrow {
    auto req = parseHTTP(data);
    
    if (!req) {
        // Handle parse error
        return;
    }
    
    // Access parsed data (zero-copy)
    auto method = req.getMethod();
    auto path = req.getPath();
    auto host = req.getHeader("Host");
    
    // Parser auto-released on scope exit
}
```

### Header Iteration

```d
foreach (header; req.getHeaders()) {
    writefln("%s: %s", header.name, header.value);
}
```

### Connection Handling

```d
if (req.shouldKeepAlive()) {
    // Reuse connection
} else {
    // Close connection
}
```

### Error Handling

```d
auto req = parseHTTP(data);

if (!req) {
    auto errorCode = req.getErrorCode();
    auto errorMsg = req.getErrorReason();
    
    writefln("Parse error %d: %s", errorCode, errorMsg);
    return;
}
```

### Integration with Server

```d
@nogc nothrow
void handleConnection(Socket socket) {
    ubyte[8192] buffer;
    
    auto n = socket.receive(buffer);
    if (n <= 0) return;
    
    auto req = parseHTTP(buffer[0..n]);
    if (!req) return;
    
    // Route based on method and path
    if (req.getMethod() == "GET" && req.getPath() == "/") {
        sendResponse(socket, "200 OK", "Hello World");
    }
}
```

---

## Known Limitations

### HTTP Spec Compliance

Wire follows llhttp's strict HTTP spec compliance:

1. **Header whitespace trimming**: llhttp trims leading/trailing spaces per HTTP spec
2. **Content-Length validation**: Strict matching required
3. **Header count limit**: Maximum 64 headers (configurable in `types.d`)

### Not Supported

- ❌ HTTP/2, HTTP/3 (HTTP/1.1 only)
- ❌ WebSocket upgrade handling (headers parsed, but no WebSocket protocol)
- ❌ Chunked encoding parsing (headers detected, body as-is)
- ❌ Multipart body parsing (body provided as raw bytes)

> [!NOTE]
> The `getVersion()` method contains placeholder code for HTTP/2.0 return value, but this is **not** actual HTTP/2 support. The parser is configured for HTTP/1.x only.

### Future Enhancements

- [ ] SIMD optimization for `StringView.equalsIgnoreCase` (AVX2/SSE4.2)
- [ ] Configurable header limit
- [ ] HTTP/2 support
- [ ] Fuzzing integration (afl, libFuzzer)

---

## License

MIT License

Copyright (c) 2024 Federico Filippi

Built on [llhttp](https://github.com/nodejs/llhttp) (MIT License) by Fedor Indutny and Node.js contributors.

---

## Benchmarking Methodology

All benchmarks use:
- **Compiler**: LDC 1.41 with `-O3 -mcpu=native`
- **Platform**: macOS ARM64 (M4 chip)
- **Timing**: `core.time.MonoTime` (microsecond precision)
- **Measurement**: Median of 3 runs per test
- **Overhead**: Framework overhead (~171 μs total) excluded from per-test times

Run your own benchmarks:
```bash
make test-verbose    # Shows per-test timing
make test-debug      # Shows detailed breakdown
```

---

## Contributing

Wire is a focused, production-ready HTTP parser. Contributions should:

1. Maintain `@nogc` compatibility
2. Add tests for new features
3. Follow D best practices
4. Preserve the no-GC-allocation guarantee and sequential parser reuse

**Contact**: [@federikowsky](https://github.com/federikowsky)

---

**Wire** - Zero-GC-allocation HTTP parsing for D 🚀
