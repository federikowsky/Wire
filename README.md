# Wire

High-performance, zero-GC-allocation HTTP parser for D.

Built on [llhttp](https://github.com/nodejs/llhttp), the HTTP parser that powers Node.js.

[![DUB](https://img.shields.io/dub/v/wire)](https://code.dlang.org/packages/wire)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![D](https://img.shields.io/badge/D-2.105%2B-red.svg)](https://dlang.org/)

## Overview

Wire provides a `@nogc nothrow` HTTP/1.x parser. All string data is accessed via `StringView` slices into the original request buffer. Parser creation uses native heap allocations; sequential calls reuse a cached parser.

**Key characteristics:**

- Zero GC allocations during parsing
- Complete `@nogc nothrow` API
- 64-byte aligned structures for cache efficiency
- Thread-local parser pool with automatic reuse

## Installation

Add to your `dub.json`:

```json
"dependencies": {
    "wire": "~>1.0.0"
}
```

Or with `dub.sdl`:

```sdl
dependency "wire" version="~>1.0.0"
```

### Building from Source

```bash
git clone https://github.com/federikowsky/Wire.git
cd Wire
make        # Build and run tests
make lib    # Build static library only
```

## Quick Start

```d
import wire;

void handleRequest(const(ubyte)[] data) @nogc nothrow {
    auto req = parseHTTP(data);
    
    if (!req) return;  // Parse error
    
    auto method = req.getMethod();     // "GET"
    auto path = req.getPath();         // "/api/users"
    auto host = req.getHeader("Host"); // "example.com"
    
    auto page = req.getQueryParam("page");
    
    if (req.shouldKeepAlive()) {
        // Reuse connection
    }
}
```

## API Reference

### Parsing

```d
auto parseHTTP(const(ubyte)[] data) @nogc nothrow;
```

Returns a move-only `ParserWrapper` that exclusively owns its parser until scope exit. Multiple live wrappers, including nested or interleaved fiber requests, retain independent results. Assignment and moves transfer ownership; references returned by `request()` remain valid only while the receiving wrapper owns the parser.

Each thread caches at most one **idle** parser. Acquisition removes it from the cache; cold or overlapping calls allocate a separate parser using the native heap. Release caches the parser on the releasing thread if its idle slot is empty, otherwise frees it. Thread exit frees only the idle parser, so a live wrapper can outlive its originating thread when ownership is transferred with synchronization. Concurrent access to the same wrapper is not supported.

The input buffer remains borrowed: keep it alive and unchanged for as long as any request view is used. Native allocation failure raises `OutOfMemoryError`; parse errors still return a wrapper whose boolean conversion is false and whose error details can be inspected.

### Request Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `getMethod()` | `StringView` | HTTP method |
| `getPath()` | `StringView` | Request path |
| `getQuery()` | `StringView` | Query string (without `?`) |
| `getHeader(name)` | `StringView` | Header value (case-insensitive) |
| `getQueryParam(name)` | `StringView` | Query parameter value |
| `getBody()` | `StringView` | Request body |
| `shouldKeepAlive()` | `bool` | Connection keep-alive status |
| `isUpgrade()` | `bool` | WebSocket upgrade request |
| `getErrorCode()` | `int` | Error code (0 = success) |

All methods are `@nogc nothrow` and return zero-copy views.

### Header Iteration

```d
foreach (header; req.getHeaders()) {
    writeln(header.name, ": ", header.value);
}
```

## Performance

Benchmarked on Apple M2 with LDC 1.41:

| Request Type | Size | Parse Time | Throughput |
|--------------|------|------------|------------|
| Simple GET | 37 B | 7 μs | 5 MB/s |
| Browser (Chrome) | 1.0 KB | 1 μs | 983 MB/s |
| REST API + JWT | 1.5 KB | 1 μs | 1,442 MB/s |
| Stripe Webhook | 2.1 KB | 1 μs | 2,023 MB/s |

**Memory usage:**
- Per thread: at most one cached idle parser, freed on thread exit
- Per live wrapper: one exclusive parser; cold/overlapping calls allocate the parser, llhttp handle and settings on the native heap
- Sequential reuse: no new native allocations; parsing uses no GC allocations
- Header limit: 64 headers

## Building

### Requirements

- **D Compiler**: LDC 1.35+ (recommended) or DMD 2.105+
- **C Compiler**: clang or gcc (C99)

### Make Targets

| Target | Description |
|--------|-------------|
| `make` | Build and run tests |
| `make lib` | Build `libwire.a` |
| `make test-verbose` | Tests with timing |
| `make debug` | Debug build |
| `make clean` | Clean artifacts |

## Documentation

- [Technical Specifications](docs/specs.md) — Complete API reference
- [llhttp](https://github.com/nodejs/llhttp) — Underlying parser

## Contributing

Contributions are welcome. Please ensure:

1. All code maintains `@nogc nothrow` compatibility
2. Tests pass (`make test`)
3. Code follows D style guidelines

## License

MIT License — see [LICENSE](LICENSE) for details.
