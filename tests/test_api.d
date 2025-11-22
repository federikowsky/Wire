module test_api;

import std.stdio;
import wire.parser;
import wire.types;

// Mock data
const(ubyte)[] rawRequest = cast(const(ubyte)[])"GET /api/v1/status HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n\r\n";

void main() {
    writeln("Testing API...");

    // 1. Parsing
    auto req = parseHTTP(rawRequest);

    // 2. Validation
    if (req) {
        writeln("Parsing Success!");
        
        // 3. Accessors
        if (req.getMethod() == "GET") {
            writeln("Method is GET");
        }
        
        if (req.getPath() == "/api/v1/status") {
            writeln("Path is correct");
        }
        
        // 4. Headers
        StringView host = req.getHeader("Host");
        if (!host.empty) {
            writeln("Host: ", host);
        }
        
        if (req.hasHeader("Host")) {
            writeln("hasHeader works");
        }
        
        // 5. Case Insensitive Check
        if (req.getHeader("host").equalsIgnoreCase("LOCALHOST")) {
            writeln("Host check passed (case-insensitive)");
        }
        
        // 6. Version & Flags
        writeln("Version: ", req.getVersion());
        if (req.shouldKeepAlive()) {
            writeln("Keep-Alive: Yes");
        }
        
        // 7. Body
        if (req.getBody().empty) {
            writeln("Body: (empty)");
        }
        
        // 8. Iteration
        writeln("--- Headers ---");
        foreach (h; req.getHeaders()) {
            writeln(h.name, ": ", h.value);
        }
        
    } else {
        writeln("Parsing Failed: ", req.getErrorCode());
    }
}
