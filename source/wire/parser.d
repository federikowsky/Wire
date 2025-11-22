module wire.parser;

import wire.bindings;
import wire.types;
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
    
    // Initialize C structures (One-time setup)
    // Takes a Parser* to set as the data pointer
    void setup(Parser* self) @nogc nothrow {
        // Allocate C structs on heap (stable addresses) and ZERO them
        handle = cast(llhttp_t*) calloc(1, llhttp_t.sizeof); 
        settings = cast(llhttp_settings_t*) calloc(1, llhttp_settings_t.sizeof); 
        
        // CRITICAL: Set the data pointer to the ALLOCATED Parser instance
        handle.data = cast(void*)self;
        
        // Initialize settings with callbacks
        settings.on_message_begin = &cb_on_message_begin;
        settings.on_url = &cb_on_url;
        settings.on_method = &cb_on_method;
        settings.on_version = &cb_on_version;
        settings.on_header_field = &cb_on_header_field;
        settings.on_header_value = &cb_on_header_value;
        settings.on_headers_complete = &cb_on_headers_complete;
        settings.on_body = &cb_on_body;
        settings.on_message_complete = &cb_on_message_complete;
        
        // Initialize parser
        llhttp_init(handle, llhttp_type.HTTP_REQUEST, settings);
        
        // Re-set data after init (in case llhttp_init clears it)
        handle.data = cast(void*)self;
    }
    
    // Reset for new request
    void reset(Parser* self) @nogc nothrow {
        llhttp_reset(handle);
        request.reset();
        currentHeaderName = StringView.makeNull();
        // Ensure data pointer is still valid after reset
        handle.data = cast(void*)self;
    }
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
    parser.request.routing.path = StringView(at[0 .. length]);
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
    return 0;
}

/**
 * RAII Wrapper for the Parser.
 * Returns the parser to the pool when it goes out of scope.
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
    
    // Accessor for the request
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
 * Thread-Local Parser Pool.
 * Each thread gets exactly one parser instance lazily initialized.
 */
struct ParserPool {
    // Thread-Local State
    static Parser* t_parser;
    static bool t_busy;
    
    // Acquire the thread's parser
    static Parser* acquire() @nogc nothrow {
        if (t_busy) {
            return null; // Should not happen in correct architecture
        }
        
        if (t_parser is null) {
            // Lazy Initialization: Use calloc to ZERO the memory
            t_parser = cast(Parser*) calloc(1, Parser.sizeof);
            // Pass the actual allocated pointer to setup
            t_parser.setup(t_parser);
        }
        
        t_busy = true;
        // Pass the actual pointer to reset
        t_parser.reset(t_parser);
        return t_parser;
    }
    
    // Release the parser
    static void release(Parser* p) @nogc nothrow {
        if (p == t_parser) {
            t_busy = false;
        }
    }
}

/**
 * Main Entry Point.
 * Parses HTTP data and returns a RAII handle.
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
