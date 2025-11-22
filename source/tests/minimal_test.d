module minimal_test;

import llhttp.parser;
import llhttp.types;
import llhttp.bindings;
import std.stdio;

void main() {
    writeln("Starting minimal test...");
    
    // Test 1: parseHTTP wrapper
    writeln("[1] Testing parseHTTP wrapper...");
    auto data = cast(const(ubyte)[])"GET / HTTP/1.1\r\n\r\n";
    
    writeln("    Before parseHTTP");
    auto req = parseHTTP(data);
    writeln("    After parseHTTP");
    
    // Test 2: Access parser
    writeln("[2] Accessing parser...");
    writeln("    req.parser: ", cast(void*)req.parser);
    
    // Test 3: Access request
    writeln("[3] Accessing request...");
    writeln("    errorCode: ", req.parser.request.content.errorCode);
    
    // Test 4: Call getMethod
    writeln("[4] Calling getMethod...");
    auto method = req.getMethod();
    writeln("    method.ptr: ", cast(void*)method.ptr);
    writeln("    method.length: ", method.length);
    
    // Test 5: Convert to bool  
    writeln("[5] Testing bool cast...");
    if (req) {
        writeln("    req is true");
    } else {
        writeln("    req is false");
    }
    
    writeln("All tests completed!");
}
