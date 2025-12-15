module wire;

// Types and utilities
public import wire.types;

// Parser API - both TLS and owned variants
public import wire.parser :
    // TLS API (existing)
    parseHTTP,
    ParserWrapper,
    // Owned Parser API (new - per-instance for Aurora/fiber use)
    ParserHandle,
    createParser,
    destroyParser,
    parseHTTPWith,
    getRequest;
