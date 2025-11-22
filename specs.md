# Wire - High-Performance HTTP Parser for D

**Version**: 1.0.0  
**Status**: Production Ready  
**License**: MIT  
**Repository**: [github.com/federikowsky/Wire](https://github.com/federikowsky/Wire)

---

## Executive Summary

Wire is a zero-allocation, high-performance HTTP/1.1 parser for the D programming language. Built as a wrapper around the battle-tested [llhttp](https://github.com/nodejs/llhttp) C library (used by Node.js), Wire achieves **1-7 microsecond** parsing times with throughput exceeding **2 GB/sec** while maintaining complete `@nogc` compatibility.

### Key Metrics

- **Parse Time**: 1-7 μs per request (typical)
- **Throughput**: 300-2,000 MB/sec depending on complexity
- **Memory**: ~1 KB per thread (thread-local pool)
- **Allocations**: Zero (complete `@nogc` implementation)
- **Header Limit**: 64 headers per request
- **Supported Methods**: GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH, etc.

---

## Architecture

### Design Principles

1. **Zero Allocation**: No GC pressure during parsing
2. **Cache Optimization**: Hot data in first 64 bytes (L1 cache line)
3. **Zero-Copy**: `StringView` for all string data
4. **Thread-Local Pooling**: Parser reuse without synchronization
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
    const(char)* ptr;    // 8 bytes
    size_t length;       // 8 bytes
}
```

**Features**:
- `@nogc` all methods
- Case-insensitive comparison
- Slicing without allocation
- Implicit conversion to `string` only when needed

#### ParsedHttpRequest (64-byte aligned)

Cache-optimized request structure with hot/cold data separation:

```d
align(64) struct ParsedHttpRequest {
    // HOT PATH DATA (first 64 bytes - L1 cache line)
    RoutingInfo {
        StringView method;        // GET, POST, etc.
        StringView path;          // /api/users
        StringView query;         // ?page=2
        ubyte versionMajor;       // 1
        ubyte versionMinor;       // 1 or 0
        ubyte numHeaders;         // 0-64
        ubyte flags;              // keep-alive, upgrade
    }
    
    // COLD PATH DATA (separate cache lines)
    ContentInfo {
        Header[64] headers;       // name/value pairs
        StringView body;          // request body
        int errorCode;            // 0 = success
        const(char)* errorPos;    // error position
    }
}
```

**Benefits**:
- Routing decisions use only first cache line
- Header scanning deferred until needed
- Predictable memory layout

---

## API Reference

### Parsing Entry Point

```d
@nogc nothrow
auto parseHTTP(const(ubyte)[] data);
```

Returns a `ParserWrapper` with RAII cleanup. Parser is automatically released when wrapper goes out of scope.

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

**Per-Thread Overhead**:
- Parser struct: ~200 bytes
- llhttp_t: ~576 bytes
- llhttp_settings_t: ~208 bytes
- **Total**: ~1 KB

**Per-Request**:
- Allocations: **0 bytes** (zero-allocation design)
- Stack usage: ~64 bytes (ParsedHttpRequest)

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
make test         # Run test suite (23 tests)
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

**Standard Tests** (23 tests):
- ✅ HTTP methods (GET, POST, PUT, DELETE, HEAD, OPTIONS)
- ✅ Headers (multiple, case-insensitive, iteration, overflow)
- ✅ HTTP versions (1.0, 1.1, keep-alive, close)
- ✅ Edge cases (long paths, long values, header limits)
- ✅ Error handling (invalid version, malformed headers)
- ✅ Real-world scenarios (browser, API, chunked encoding)

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
# Quick test (23 tests, ~220 μs total)
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

1. **Parser Pool** (once per thread):
   ```d
   t_parser = cast(Parser*) calloc(1, Parser.sizeof);
   ```

2. **llhttp Structures** (once per parser):
   ```d
   handle = cast(llhttp_t*) calloc(1, llhttp_t.sizeof);
   settings = cast(llhttp_settings_t*) calloc(1, llhttp_settings_t.sizeof);
   ```

3. **During Parsing**: **Zero allocations** ✓

### Thread Safety

- ❌ **Not thread-safe**: Each thread must use separate parser
- ✅ **Thread-local pooling**: Automatic via `ParserPool`
- ✅ **No shared state**: Complete isolation between threads

**Thread-Local Model**:
```d
static Parser* t_parser;  // TLS variable
static bool t_busy;        // TLS flag

// Acquire parser (reuses if available)
auto wrapper = parseHTTP(data);  // Gets t_parser

// Automatically released on scope exit
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

### Future Enhancements

- [ ] SIMD optimization for `StringView.equalsIgnoreCase` (AVX2/SSE4.2)
- [ ] Configurable header limit
- [ ] HTTP/2 support
- [ ] Fuzzing integration (afl, libFuzzer)
- [ ] Dub package publication

---

## License

MIT License

Copyright (c) 2024 Federico Filippi

Built on [llhttp](https://github.com/nodejs/llhttp) (MIT License) by Fedor Indutny and Node.js contributors.

---

## Benchmarking Methodology

All benchmarks use:
- **Compiler**: LDC 1.41 with `-O3 -mcpu=native`
- **Platform**: macOS ARM64 (M2 chip)
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
4. Preserve zero-allocation guarantee

**Contact**: [@federikowsky](https://github.com/federikowsky)

---

**Wire** - Zero-allocation HTTP parsing for D 🚀