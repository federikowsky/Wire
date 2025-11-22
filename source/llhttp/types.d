module llhttp.types;

import core.stdc.string : memcmp;

/**
 * Rappresenta una vista non-owning su un buffer di caratteri.
 * Size: 16 bytes (ptr + len).
 * ABI: Passata in 2 registri (RDI, RSI su System V AMD64).
 */
struct StringView {
    const(char)* ptr;
    size_t length;

    // --- Costruttori ---
    
    // Da stringa letterale o slice D
    this(const(char)[] s) pure nothrow @nogc @trusted {
        this.ptr = s.ptr;
        this.length = s.length;
    }
    
    // Null view (stato iniziale)
    static StringView makeNull() pure nothrow @nogc @safe {
        return StringView(cast(const(char)*)null, 0);
    }

    // --- Python-Style API (Inlined) ---
    
    // Slice: view[1..3] -> StringView(ptr+1, 2)
    StringView opSlice(size_t start, size_t end) const pure nothrow @nogc @trusted {
        // In release mode with -boundscheck=off, this assert is removed
        assert(start <= end && end <= length, "Slice out of bounds");
        return StringView(ptr + start, end - start);
    }
    
    // Private constructor for internal slicing
    private this(const(char)* p, size_t l) pure nothrow @nogc @safe {
        this.ptr = p;
        this.length = l;
    }
    
    // Equality: view == "GET"
    bool opEquals(const(char)[] other) const pure nothrow @nogc @trusted {
        if (length != other.length) return false;
        if (ptr == other.ptr) return true;
        return memcmp(ptr, other.ptr, length) == 0;
    }
    
    // Case-Insensitive Equality (Placeholder for SIMD implementation)
    bool equalsIgnoreCase(const(char)[] other) const pure nothrow @nogc @trusted {
        if (length != other.length) return false;
        // TODO: Implement SIMD version in Layer 2
        // Scalar fallback for now
        for (size_t i = 0; i < length; i++) {
            char a = ptr[i];
            char b = other[i];
            // Simple ASCII lowercasing
            if (a >= 'A' && a <= 'Z') a += 32;
            if (b >= 'A' && b <= 'Z') b += 32;
            if (a != b) return false;
        }
        return true;
    }
    
    // Duck Typing (Range Interface)
    bool empty() const pure nothrow @nogc @safe => length == 0;
    char front() const pure nothrow @nogc @trusted => *ptr;
    void popFront() pure nothrow @nogc @trusted { ptr++; length--; }
    
    // Debug
    string toString() const => ptr ? ptr[0 .. length].idup : "(null)"; 
}

/**
 * ParsedHttpRequest Layout
 * Cache-Optimized: Routing info in first 64 bytes.
 */
align(64) struct ParsedHttpRequest {
    // --- CACHE LINE 0: ROUTING INFO (0-63 bytes) ---
    align(64) struct RoutingInfo {
        StringView method;      // [0-15]
        StringView path;        // [16-31]
        StringView query;       // [32-47]
        ushort statusCode;      // [48-49]
        ubyte versionMajor;     // [50]
        ubyte versionMinor;     // [51]
        ubyte flags;            // [52]
        ubyte numHeaders;       // [53]
        ubyte[10] _padding;     // [54-63] Zeroed
    }
    RoutingInfo routing;
    
    static assert(RoutingInfo.sizeof == 64, "RoutingInfo struct must be exactly 64 bytes");

    // --- CACHE LINE 1+: CONTENT INFO ---
    align(64) struct ContentInfo {
        align(32) struct HttpHeader {
            StringView name;
            StringView value;
        }
        
        enum MAX_HEADERS = 64;
        HttpHeader[MAX_HEADERS] headers; 
        
        StringView body;
        const(char)* errorPos;
        int errorCode;
    }
    ContentInfo content;
    
    // Helper methods
    void reset() pure nothrow @nogc {
        // Reset Routing: basta azzerare i primi 64 byte
        routing = RoutingInfo.init;
        // Reset Content: basta azzerare il count (fatto in routing)
        content.body = StringView.makeNull();
        content.errorCode = 0;
    }

    // --- Public API Methods ---

    StringView getMethod() const pure nothrow @nogc @safe { return routing.method; }
    StringView getPath() const pure nothrow @nogc @safe { return routing.path; }
    StringView getQuery() const pure nothrow @nogc @safe { return routing.query; }
    
    // Version
    StringView getVersion() const pure nothrow @nogc @safe {
        if (routing.versionMajor == 1) {
            if (routing.versionMinor == 1) return StringView("1.1");
            if (routing.versionMinor == 0) return StringView("1.0");
        }
        if (routing.versionMajor == 2) return StringView("2.0");
        return StringView("1.1"); 
    }
    
    ubyte getVersionMajor() const pure nothrow @nogc @safe { return routing.versionMajor; }
    ubyte getVersionMinor() const pure nothrow @nogc @safe { return routing.versionMinor; }

    // Headers
    StringView getHeader(const(char)[] name) const pure nothrow @nogc @trusted {
        for (size_t i = 0; i < routing.numHeaders; i++) { 
            auto h = content.headers[i];
            if (h.name.equalsIgnoreCase(name)) {
                return h.value;
            }
        }
        return StringView.makeNull();
    }
    
    bool hasHeader(const(char)[] name) const pure nothrow @nogc @trusted {
        return !getHeader(name).empty;
    }
    
    // Body
    StringView getBody() const pure nothrow @nogc @safe { return content.body; }
    
    // Flags
    bool shouldKeepAlive() const pure nothrow @nogc @safe {
        return (routing.flags & 0x01) != 0;
    }
    
    bool isUpgrade() const pure nothrow @nogc @safe {
        return (routing.flags & 0x02) != 0; 
    }
    
    // Errors
    int getErrorCode() const pure nothrow @nogc @safe { return content.errorCode; }
    const(char)* getErrorReason() const pure nothrow @nogc @safe { return content.errorPos; }
    
    // Range Interface for Headers
    auto getHeaders() const pure nothrow @nogc @safe {
        static struct HeaderRange {
            private const(ContentInfo.HttpHeader)* ptr;
            private size_t count;
            
            bool empty() const pure nothrow @nogc @safe => count == 0;
            auto front() const pure nothrow @nogc @safe => *ptr;
            void popFront() pure nothrow @nogc @trusted { ptr++; count--; }
        }
        return HeaderRange(content.headers.ptr, routing.numHeaders); 
    }
}
