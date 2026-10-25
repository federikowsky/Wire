module wire.parser;

import wire.bindings;
import wire.types;
import core.exception : onOutOfMemoryError;
import core.stdc.stdlib : calloc, free;

/**
 * Internal Parser Wrapper.
 * Wraps the C llhttp_t handle and settings.
 */
struct Parser {
    llhttp_t* handle;
    llhttp_settings_t* settings;
    ParsedHttpRequest request; // The request being parsed
    
    // Internal state for header parsing
    StringView currentHeaderName;
    
    // Reset for new request
    void reset(Parser* self) @nogc nothrow {
        llhttp_reset(handle);
        request.reset();
        currentHeaderName = StringView.makeNull();
        // Ensure data pointer is still valid after reset
        handle.data = cast(void*)self;
    }
}

/**
 * Safe setup that checks all allocations before dereferencing.
 * Used by createParser() for both cached and explicitly owned parsers.
 *
 * Params:
 *   self = Parser to initialize (must not be null)
 *
 * Returns: true on success, false on allocation failure
 */
private bool setupChecked(Parser* self) @nogc nothrow {
    // Allocate handle - check before dereferencing
    self.handle = cast(llhttp_t*) calloc(1, llhttp_t.sizeof);
    if (self.handle is null) {
        return false;
    }

    // Allocate settings - check before dereferencing
    self.settings = cast(llhttp_settings_t*) calloc(1, llhttp_settings_t.sizeof);
    if (self.settings is null) {
        return false;
    }

    // Initialize settings with callbacks
    self.settings.on_message_begin = &cb_on_message_begin;
    self.settings.on_url = &cb_on_url;
    self.settings.on_method = &cb_on_method;
    self.settings.on_version = &cb_on_version;
    self.settings.on_header_field = &cb_on_header_field;
    self.settings.on_header_value = &cb_on_header_value;
    self.settings.on_headers_complete = &cb_on_headers_complete;
    self.settings.on_body = &cb_on_body;
    self.settings.on_message_complete = &cb_on_message_complete;

    // Initialize parser
    llhttp_init(self.handle, llhttp_type.HTTP_REQUEST, self.settings);

    // Set data pointer to Parser instance
    self.handle.data = cast(void*) self;

    return true;
}

// --- C Callbacks (Static, extern(C)) ---

extern(C) int cb_on_message_begin(llhttp_t* p) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    parser.request.reset();
    return 0;
}

extern(C) int cb_on_method(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    parser.request.routing.method = StringView(at[0 .. length]);
    return 0;
}

extern(C) int cb_on_url(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    
    // Find '?' to separate path from query string
    size_t queryStart = length; // Default: no query
    for (size_t i = 0; i < length; i++) {
        if (at[i] == '?') {
            queryStart = i;
            break;
        }
    }
    
    // Path is everything before '?'
    parser.request.routing.path = StringView(at[0 .. queryStart]);
    
    // Query is everything after '?' (excluding the '?' itself)
    if (queryStart < length) {
        parser.request.routing.query = StringView(at[queryStart + 1 .. length]);
    } else {
        parser.request.routing.query = StringView.makeNull();
    }
    
    return 0;
}

extern(C) int cb_on_version(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    // No-op: We read version directly from struct in on_headers_complete
    return 0;
}

extern(C) int cb_on_header_field(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    parser.currentHeaderName = StringView(at[0 .. length]);
    return 0;
}

extern(C) int cb_on_header_value(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    auto req = &parser.request;
    
    // Access numHeaders from routing (Hot)
    if (req.routing.numHeaders < ParsedHttpRequest.ContentInfo.MAX_HEADERS) {
        auto idx = req.routing.numHeaders;
        req.content.headers[idx].name = parser.currentHeaderName;
        req.content.headers[idx].value = StringView(at[0 .. length]);
        req.routing.numHeaders++;
    } else {
        return llhttp_errno.HPE_USER; // Overflow
    }
    return 0;
}

extern(C) int cb_on_headers_complete(llhttp_t* p) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    
    // Read Version directly from C struct
    parser.request.routing.versionMajor = p.http_major;
    parser.request.routing.versionMinor = p.http_minor;
    
    // Check Keep-Alive
    if (llhttp_should_keep_alive(p)) {
        parser.request.routing.flags |= 0x01; // Bit 0 = KeepAlive
    }
    
    // Check Upgrade
    if (p.upgrade) {
        parser.request.routing.flags |= 0x02; // Bit 1 = Upgrade
    }
    
    return 0;
}

extern(C) int cb_on_body(llhttp_t* p, const(char)* at, size_t length) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    parser.request.content.body = StringView(at[0 .. length]);
    return 0;
}

extern(C) int cb_on_message_complete(llhttp_t* p) @nogc nothrow {
    Parser* parser = cast(Parser*) p.data;
    // Set completion flag - used by Aurora to detect complete requests
    parser.request.routing.messageComplete = true;
    return 0;
}

/**
 * Exclusive RAII lease for a Parser.
 * Other parseHTTP calls cannot reuse this parser until the wrapper is released.
 * Request views still borrow the input buffer, which must outlive their use.
 */
struct ParserWrapper {
    Parser* parser;
    
    // Disable copying to prevent double-free
    @disable this(this);
    
    // Destructor: Release back to pool
    ~this() @nogc nothrow {
        if (parser) {
            ParserPool.release(parser);
            parser = null;
        }
    }
    
    // The reference is valid only while this wrapper owns its parser.
    ref ParsedHttpRequest request() return @nogc nothrow {
        return parser.request;
    }
    
    // Alias to allow direct access to request methods (req.getMethod())
    alias request this;
    
    // Cast to bool for "if (req)" checks
    T opCast(T : bool)() const {
        return parser !is null && parser.request.content.errorCode == 0;
    }
}

/**
 * Thread-local cache containing at most one idle parser.
 * A leased parser is detached from the cache, so overlapping requests remain
 * independent and a lease can move to another thread with synchronized ownership.
 */
struct ParserPool {
    // Thread-local idle slot; never points to a parser held by a live wrapper.
    static Parser* t_parser;
    
    // Reuse an idle parser or allocate an independent lease.
    static Parser* acquire() @nogc nothrow {
        if (t_parser !is null) {
            auto p = t_parser;
            t_parser = null;
            p.reset(p);
            return p;
        }

        auto p = cast(Parser*) createParser();
        if (p is null) onOutOfMemoryError();
        return p;
    }
    
    // Cache on the releasing thread, or free if its idle slot is occupied.
    static void release(Parser* p) @nogc nothrow {
        if (t_parser is null) t_parser = p;
        else destroyParser(p);
    }
}

// D runs this for each thread. Active leases are not in the idle slot and may
// safely outlive the thread on which they were acquired.
static ~this() @nogc nothrow {
    auto p = ParserPool.t_parser;
    ParserPool.t_parser = null;
    destroyParser(p);
}

/**
 * Main Entry Point.
 * Parses HTTP data and returns an exclusive RAII handle.
 * Cold/overlapping calls may allocate on the C heap; no GC allocation is used.
 * Allocation failure raises OutOfMemoryError rather than returning a null handle.
 */
auto parseHTTP(const(ubyte)[] data) @nogc nothrow {
    Parser* p = ParserPool.acquire();

    // Execute Parsing
    llhttp_errno err = llhttp_execute(p.handle, cast(const(char)*)data.ptr, data.length);

    if (err != llhttp_errno.HPE_OK) {
        p.request.content.errorCode = cast(int)err;
        p.request.content.errorPos = llhttp_get_error_reason(p.handle);
    }

    return ParserWrapper(p);
}

// ============================================================================
// Owned Parser API - Per-instance parser for Aurora (fiber-safe)
// ============================================================================

/**
 * Opaque handle to a dedicated parser instance.
 * Use createParser() to create, destroyParser() to free.
 *
 * Lifetime: Create one parser per connection/fiber. Use parseHTTPWith() for each request.
 * Call destroyParser() when done (e.g., connection close).
 *
 * Aurora usage pattern:
 *   ParserHandle conn = createParser();
 *   assert(conn !is null);
 *
 *   llhttp_errno err = parseHTTPWith(conn, requestData);
 *   if (err == llhttp_errno.HPE_OK) {
 *       ref ParsedHttpRequest req = getRequest(conn);
 *       // Use req.routing.path, req.getHeader(), etc.
 *   }
 *
 *   destroyParser(conn);
 */
alias ParserHandle = void*;

/**
 * Create a dedicated parser instance.
 *
 * Allocates a Parser on the heap with calloc and initializes it.
 * The caller owns the parser and must call destroyParser() to free resources.
 *
 * Returns: Opaque parser handle, or null on allocation failure.
 */
ParserHandle createParser() @nogc nothrow {
    // Allocate Parser struct
    Parser* p = cast(Parser*) calloc(1, Parser.sizeof);
    if (p is null) {
        return null;
    }

    // Safe setup with allocation checks
    if (!setupChecked(p)) {
        // Cleanup partial allocations
        if (p.handle) free(p.handle);
        if (p.settings) free(p.settings);
        free(p);
        return null;
    }

    return cast(ParserHandle) p;
}

/**
 * Destroy a parser created with createParser().
 *
 * Frees all C allocations (handle, settings) and the Parser itself.
 * Safe to call with null handle.
 *
 * Params:
 *   handle = Parser handle to destroy, or null
 */
void destroyParser(ParserHandle handle) @nogc nothrow {
    if (handle is null) {
        return;
    }

    Parser* p = cast(Parser*) handle;

    if (p.handle) {
        free(p.handle);
    }
    if (p.settings) {
        free(p.settings);
    }
    free(p);
}

/**
 * Parse HTTP request data using the given parser handle.
 *
 * Resets the parser state before parsing (clears previous request).
 * Fills parser.request with parsed data (zero-copy StringView slices).
 *
 * Params:
 *   handle = Parser handle (must not be null)
 *   data = Raw HTTP request bytes
 *
 * Returns: llhttp_errno (0 = HPE_OK = success)
 */
llhttp_errno parseHTTPWith(ParserHandle handle, const(ubyte)[] data) @nogc nothrow {
    Parser* p = cast(Parser*) handle;

    // Reset for new request
    p.reset(p);

    // Execute parsing
    llhttp_errno err = llhttp_execute(p.handle, cast(const(char)*)data.ptr, data.length);

    if (err != llhttp_errno.HPE_OK) {
        p.request.content.errorCode = cast(int)err;
        p.request.content.errorPos = llhttp_get_error_reason(p.handle);
    }

    return err;
}

/**
 * Get reference to the parsed request.
 *
 * Valid only while the input buffer passed to parseHTTPWith() remains valid.
 * ParsedHttpRequest contains StringView slices pointing into that buffer.
 *
 * Params:
 *   handle = Parser handle (must not be null)
 *
 * Returns: Reference to parsed request data
 */
ref ParsedHttpRequest getRequest(ParserHandle handle) @nogc nothrow {
    Parser* p = cast(Parser*) handle;
    return p.request;
}
