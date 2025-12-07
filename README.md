# Wire

High-performance, zero-allocation HTTP parser for D.

Built on [llhttp](https://github.com/nodejs/llhttp), the HTTP parser that powers Node.js.

[![DUB](https://img.shields.io/dub/v/wire)](https://code.dlang.org/packages/wire)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![D](https://img.shields.io/badge/D-2.105%2B-red.svg)](https://dlang.org/)

## Overview

Wire provides a `@nogc nothrow` HTTP/1.x parser with zero heap allocations. All string data is accessed via `StringView` slices into the original request buffer.

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

Returns a `ParserWrapper` with RAII cleanup. The parser is automatically returned to the thread-local pool on scope exit.

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
- Per thread: ~1 KB (parser pool)
- Per request: 0 bytes (zero allocation)
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