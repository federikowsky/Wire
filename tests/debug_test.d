module debug_test;

import std.stdio;
import wire.parser;
import wire.types;

void main() {
    writeln("Test 1: PUT Request");
    {
        auto data = cast(const(ubyte)[])"PUT /resource/123 HTTP/1.1\r\nContent-Type: application/json\r\n\r\n{\"id\":123}";
        auto req = parseHTTP(data);
        
        writeln("  req valid: ", cast(bool)req);
        writeln("  method: '", req.getMethod(), "'");
        writeln("  path: '", req.getPath(), "'");
        writeln("  Content-Type: '", req.getHeader("Content-Type"), "'");
        writeln("  body: '", req.getBody(), "'");
    }
    
    writeln("\nTest 2: DELETE Request");
    {
        auto data = cast(const(ubyte)[])"DELETE /users/42 HTTP/1.1\r\nAuthorization: Bearer token\r\n\r\n";
        auto req = parseHTTP(data);
        
        writeln("  req valid: ", cast(bool)req);
        writeln("  method: '", req.getMethod(), "'");
        writeln("  path: '", req.getPath(), "'");
        writeln("  Authorization: '", req.getHeader("Authorization"), "'");
    }
    
    writeln("\nAll debug tests completed!");
}
