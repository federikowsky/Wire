module wire.types;

import core.stdc.string : memcmp;

/**
 * Represents a non-owning view over a character buffer.
 * Size: 16 bytes (ptr + len).
 * ABI: Passed in 2 registers (RDI, RSI on System V AMD64).
 */
struct StringView {
    const(char)* ptr;
    size_t length;

    // --- Constructors ---
    
    // From string literal or D slice
    this(const(char)[] s) pure nothrow @nogc @trusted {
        this.ptr = s.ptr;
        this.length = s.length;
    }
    
    // Null view (initial state)
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
    
    // Null check (distinguishes "not found" from "empty value")
    bool isNull() const pure nothrow @nogc @safe => ptr is null;
    
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
        bool messageComplete;   // [54] - NEW: set by on_message_complete callback
        ubyte[9] _padding;      // [55-63] Zeroed (was 10 bytes, now 9)
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
        // Reset Routing: just zero the first 64 bytes
        routing = RoutingInfo.init;
        routing.messageComplete = false;  // Explicitly reset completion flag
        // Reset Content: just zero the count (done in routing)
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
        return !getHeader(name).isNull;
    }
    
    // Body
    StringView getBody() const pure nothrow @nogc @safe { return content.body; }
    
    // Query String Parameter Extraction
    // Usage: auto page = req.getQueryParam("page"); // "2" from "?page=2&limit=10"
    StringView getQueryParam(const(char)[] name) const pure nothrow @nogc @trusted {
        auto query = routing.query;
        if (query.isNull || query.empty) return StringView.makeNull();
        
        const(char)* p = query.ptr;
        const(char)* end = query.ptr + query.length;
        
        while (p < end) {
            // Find start of key
            const(char)* keyStart = p;
            
            // Find '=' or '&' or end
            while (p < end && *p != '=' && *p != '&') p++;
            
            size_t keyLen = p - keyStart;
            
            // Check if this is our key
            bool matches = (keyLen == name.length);
            if (matches) {
                for (size_t i = 0; i < keyLen; i++) {
                    if (keyStart[i] != name[i]) {
                        matches = false;
                        break;
                    }
                }
            }
            
            if (p < end && *p == '=') {
                p++; // skip '='
                const(char)* valueStart = p;
                
                // Find '&' or end
                while (p < end && *p != '&') p++;
                
                if (matches) {
                    return StringView(valueStart[0 .. p - valueStart]);
                }
            } else if (matches) {
                // Key without value (e.g., "?flag&other=1")
                return StringView("");
            }
            
            // Skip '&' if present
            if (p < end && *p == '&') p++;
        }
        
        return StringView.makeNull();
    }
    
    // Check if query parameter exists
    bool hasQueryParam(const(char)[] name) const pure nothrow @nogc @trusted {
        return !getQueryParam(name).isNull;
    }
    
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
