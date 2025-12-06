# Wire

**High-performance, zero-allocation HTTP parser for D**

Wire is a D language wrapper around the battle-tested [llhttp](https://github.com/nodejs/llhttp) C library, designed for extreme performance with zero allocations and cache-aware data structures.

## Features

- ✅ **Zero Allocations**: Complete parsing without GC pressure
- ✅ **@nogc Compatible**: All core APIs marked `@nogc nothrow`
- ✅ **Cache Optimized**: 64-byte aligned hot data for L1 cache efficiency
- ✅ **Thread-Safe Pooling**: Thread-local parser reuse
- ✅ **Comprehensive API**: All HTTP methods, headers, versions supported
- ✅ **Battle-Tested**: Built on Node.js's llhttp (billions of requests/day)

## Quick Start

```d
import wire;

void handleRequest(const(ubyte)[] data) @nogc nothrow {
    auto req = parseHTTP(data);
    
    if (!req) {
        // Handle parse error
        return;
    }
    
    // Zero-copy access to parsed data
    auto method = req.getMethod();        // "GET"
    auto path = req.getPath();            // "/api/users"
    auto query = req.getQuery();          // "page=2&limit=10"
    auto host = req.getHeader("Host");    // "example.com"
    auto keepAlive = req.shouldKeepAlive(); // true/false
    
    // Parser automatically released on scope exit
}
```

## Building

### Requirements

- **D Compiler**: LDC 1.35+ (recommended) or DMD 2.105+
- **C Compiler**: clang or gcc
- **llhttp**: v9.3.0 (included)

### Build & Test

```bash
make          # Build and run tests
make lib      # Build static library (libwire.a)
make clean    # Clean build artifacts
make debug    # Build with debug symbols
make help     # Show all targets
```

## API Reference

### Parsing

```d
auto parseHTTP(const(ubyte)[] data) @nogc nothrow
```

Returns a `ParserWrapper` with RAII cleanup. Parser automatically released when wrapper goes out of scope.

### Request Methods

```d
StringView getMethod()              // HTTP method (GET, POST, etc.)
StringView getPath()                // Request path
StringView getQuery()               // Query string (if any)
StringView getBody()                // Request body

ubyte getVersionMajor()            // HTTP major version (1)
ubyte getVersionMinor()            // HTTP minor version (0 or 1)
StringView getVersion()            // Full version string ("1.1")

StringView getHeader(string name)  // Get header (case-insensitive)
bool hasHeader(string name)        // Check header existence
auto getHeaders()                  // Iterate all headers

StringView getQueryParam(string name)  // Get query parameter value
bool hasQueryParam(string name)        // Check query parameter existence

bool shouldKeepAlive()             // Connection: keep-alive
bool isUpgrade()                   // Connection: upgrade

int getErrorCode()                 // Parse error code (0 = success)
const(char)* getErrorReason()      // Error description
```

All methods are `@nogc nothrow` and return zero-copy `StringView` or primitives.

### Query Parameter Example

```d
// URL: /search?q=hello&page=2&limit=10
auto req = parseHTTP(data);

if (req.hasQueryParam("q")) {
    auto query = req.getQueryParam("q");  // "hello"
    auto page = req.getQueryParam("page"); // "2"
}
```

## Performance

### Zero-Allocation Design

- **Parser Pool**: Thread-local, reused via `calloc` (C heap)
- **StringView**: Zero-copy slice (pointer + length)
- **Fixed Arrays**: Pre-allocated header storage (64 max)
- **Cache-Aligned**: Hot data in first 64 bytes

### Memory Footprint

- **Per-thread overhead**: ~1 KB (parser + llhttp state)
- **Per-request**: 0 bytes (zero allocations)
- **Header limit**: 64 headers per request

## Testing

Comprehensive test suite with 45 tests covering happy paths, edge cases, error handling, and security scenarios:

```bash
$ make test

╔══════════════════════════════════════════════════════════╗
║         Wire - Comprehensive Test Suite                 ║
╚══════════════════════════════════════════════════════════╝

Happy Path Tests
================
  Simple GET request                                 ... PASS
  GET with path and query                            ... PASS
  POST with body                                     ... PASS
  PUT request                                        ... PASS
  DELETE request                                     ... PASS
  HEAD request                                       ... PASS
  OPTIONS request                                    ... PASS

... (38 more tests)

✓ All tests passed! (45/45)
```

## Architecture

```
source/wire/
├── bindings.d    # C interface to llhttp
├── types.d       # StringView, ParsedHttpRequest
├── parser.d      # ParserPool, parseHTTP()
├── package.d     # Public API exports
└── c/
    ├── llhttp.c  # Node.js llhttp implementation
    ├── llhttp.h  # C header
    ├── api.c     # llhttp API functions
    └── http.c    # HTTP protocol parsing
```

## Thread Safety

- ❌ **Not thread-safe**: Each thread must use separate parser
- ✅ **Thread-local pooling**: Automatic via `ParserPool`
- ✅ **No shared state**: Complete isolation

## Error Handling

```d
auto req = parseHTTP(data);

if (!req) {
    // Parse failed
    writeln("Error: ", req.getErrorCode());
    writeln("Reason: ", req.getErrorReason());
    return;
}

// Success - use req
```

Errors are returned via codes, no exceptions thrown.

## Contributing

Wire is a focused wrapper around llhttp. Contributions should:

1. Maintain `@nogc` compatibility
2. Add tests for new features
3. Follow D best practices
4. Keep zero-allocation guarantee

## License

MIT License - see [LICENSE](LICENSE)

Built on [llhttp](https://github.com/nodejs/llhttp) (MIT License)

## Acknowledgments

- **llhttp**: Node.js HTTP parser by Fedor Indutny
- **D Language**: Walter Bright, Andrei Alexandrescu, and community
- **Inspiration**: High-performance parsing from Rust's httparse

---

**Wire** - Zero-allocation HTTP parsing for D 🚀
