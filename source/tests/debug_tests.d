import std.stdio;
import std.string : format;
import std.array : replicate;
import core.time : MonoTime, Duration;
import wire;
import wire.parser;
import wire.types;

// ============================================================================
// Debug Test Framework - Shows detailed step-by-step execution
// ============================================================================

void debugTest(string testName, const(ubyte)[] rawData) {
    writeln("\n" ~ replicate("═", 80));
    writeln("🔍 DEBUG TEST: ", testName);
    writeln(replicate("═", 80));
    
    // 1. Show raw input
    writeln("\n📥 RAW INPUT:");
    writeln("  Length: ", rawData.length, " bytes");
    writeln("  Hex dump (first 100 bytes):");
    showHexDump(rawData, 100);
    writeln("\n  ASCII representation:");
    writeln("  ", formatHTTPData(rawData));
    
    // 2. Start parsing with timing
    writeln("\n⏱️  PARSING PHASES:");
    
    auto t0 = MonoTime.currTime;
    writeln("  [Phase 1] Acquiring parser from pool...");
    auto t1 = MonoTime.currTime;
    writeln("    ✓ Completed in ", formatMicros(t1 - t0));
    
    writeln("  [Phase 2] Executing llhttp parser...");
    auto t2 = MonoTime.currTime;
    auto req = parseHTTP(rawData);
    auto t3 = MonoTime.currTime;
    writeln("    ✓ Completed in ", formatMicros(t3 - t2));
    
    auto totalParsing = t3 - t0;
    writeln("  📊 Total parsing time: ", formatMicros(totalParsing));
    
    // 3. Check parse result
    writeln("\n✅ PARSE RESULT:");
    if (!req) {
        writeln("  ❌ PARSING FAILED!");
        writeln("  Error Code: ", req.getErrorCode());
        writeln("  Error Reason: ", req.getErrorReason());
        writeln("  Error Position: ", cast(void*)req.getErrorReason());
        return;
    }
    writeln("  ✓ Parsing successful");
    
    // 4. Show parsed request line
    writeln("\n📋 REQUEST LINE:");
    auto methodStart = MonoTime.currTime;
    auto method = req.getMethod();
    auto methodEnd = MonoTime.currTime;
    writeln("  Method:  '", method, "' (", method.length, " bytes) [", formatMicros(methodEnd - methodStart), "]");
    
    auto pathStart = MonoTime.currTime;
    auto path = req.getPath();
    auto pathEnd = MonoTime.currTime;
    writeln("  Path:    '", path, "' (", path.length, " bytes) [", formatMicros(pathEnd - pathStart), "]");
    
    auto versionStart = MonoTime.currTime;
    auto vMajor = req.getVersionMajor();
    auto vMinor = req.getVersionMinor();
    auto versionStr = req.getVersion();
    auto versionEnd = MonoTime.currTime;
    writeln("  Version: HTTP/", vMajor, ".", vMinor, " => '", versionStr, "' [", formatMicros(versionEnd - versionStart), "]");
    
    // 5. Show all headers with timing
    writeln("\n📨 HEADERS:");
    int headerCount = 0;
    auto headerIterStart = MonoTime.currTime;
    foreach (header; req.getHeaders()) {
        headerCount++;
        writeln("  [", headerCount, "] ", header.name, ": ", header.value);
        writeln("      └─ Name: ", header.name.length, " bytes, Value: ", header.value.length, " bytes");
    }
    auto headerIterEnd = MonoTime.currTime;
    writeln("  📊 Total headers: ", headerCount, " (iteration time: ", formatMicros(headerIterEnd - headerIterStart), ")");
    
    // 6. Test header lookup performance
    if (headerCount > 0) {
        writeln("\n🔎 HEADER LOOKUP TESTS:");
        
        // Try to find "Host" header
        auto lookupStart = MonoTime.currTime;
        auto hostHeader = req.getHeader("Host");
        auto lookupEnd = MonoTime.currTime;
        if (hostHeader.length > 0) {
            writeln("  getHeader(\"Host\") = '", hostHeader, "' [", formatMicros(lookupEnd - lookupStart), "]");
        }
        
        // Try case-insensitive
        lookupStart = MonoTime.currTime;
        auto hostHeader2 = req.getHeader("host");
        lookupEnd = MonoTime.currTime;
        if (hostHeader2.length > 0) {
            writeln("  getHeader(\"host\") = '", hostHeader2, "' [", formatMicros(lookupEnd - lookupStart), "]");
        }
        
        // Try missing header
        lookupStart = MonoTime.currTime;
        auto missing = req.getHeader("X-Non-Existent");
        lookupEnd = MonoTime.currTime;
        writeln("  getHeader(\"X-Non-Existent\") = ", missing.length == 0 ? "(not found)" : "'" ~ missing.toString() ~ "'", 
                " [", formatMicros(lookupEnd - lookupStart), "]");
    }
    
    // 7. Show body
    writeln("\n📦 BODY:");
    auto bodyStart = MonoTime.currTime;
    auto body = req.getBody();
    auto bodyEnd = MonoTime.currTime;
    if (body.length > 0) {
        writeln("  Length: ", body.length, " bytes");
        writeln("  Content: '", body, "'");
        if (body.length > 50) {
            writeln("  (truncated, showing first 50 bytes)");
        }
        writeln("  Access time: ", formatMicros(bodyEnd - bodyStart));
    } else {
        writeln("  (no body)");
    }
    
    // 8. Show connection flags
    writeln("\n🔌 CONNECTION FLAGS:");
    auto keepAliveStart = MonoTime.currTime;
    auto keepAlive = req.shouldKeepAlive();
    auto keepAliveEnd = MonoTime.currTime;
    writeln("  Keep-Alive:  ", keepAlive ? "YES" : "NO", " [", formatMicros(keepAliveEnd - keepAliveStart), "]");
    
    auto upgradeStart = MonoTime.currTime;
    auto upgrade = req.isUpgrade();
    auto upgradeEnd = MonoTime.currTime;
    writeln("  Upgrade:     ", upgrade ? "YES" : "NO", " [", formatMicros(upgradeEnd - upgradeStart), "]");
    
    // 9. Final summary
    writeln("\n📊 PERFORMANCE SUMMARY:");
    writeln("  Total time:      ", formatMicros(totalParsing));
    writeln("  Throughput:      ", format("%.2f", (rawData.length / (totalParsing.total!"usecs" / 1_000_000.0))), " bytes/sec");
    writeln("  Throughput:      ", format("%.2f", (rawData.length / (totalParsing.total!"usecs" / 1_000_000.0)) / (1024*1024)), " MB/sec");
    
    writeln("\n" ~ replicate("═", 80) ~ "\n");
}

// Utility functions
void showHexDump(const(ubyte)[] data, size_t maxBytes) {
    import std.algorithm : min;
    size_t len = min(data.length, maxBytes);
    
    for (size_t i = 0; i < len; i += 16) {
        writef("  %04X: ", i);
        
        // Hex bytes
        for (size_t j = 0; j < 16; j++) {
            if (i + j < len) {
                writef("%02X ", data[i + j]);
            } else {
                write("   ");
            }
            if (j == 7) write(" ");
        }
        
        write(" |");
        
        // ASCII representation
        for (size_t j = 0; j < 16 && i + j < len; j++) {
            ubyte b = data[i + j];
            if (b >= 32 && b < 127) {
                writef("%c", cast(char)b);
            } else if (b == '\r') {
                write("␍");
            } else if (b == '\n') {
                write("␊");
            } else {
                write("·");
            }
        }
        
        writeln("|");
    }
    
    if (data.length > maxBytes) {
        writeln("  ... (", data.length - maxBytes, " more bytes)");
    }
}

string formatHTTPData(const(ubyte)[] data) {
    import std.array : appender;
    auto result = appender!string();
    
    foreach (b; data) {
        if (b == '\r') {
            result.put("\\r");
        } else if (b == '\n') {
            result.put("\\n");
        } else if (b >= 32 && b < 127) {
            result.put(cast(char)b);
        } else {
            result.put(format("\\x%02X", b));
        }
    }
    
    return result.data;
}

string formatMicros(Duration d) {
    auto usecs = d.total!"usecs";
    if (usecs == 0) {
        return "<1 μs";
    } else if (usecs < 1000) {
        return format("%d μs", usecs);
    } else if (usecs < 1_000_000) {
        return format("%.2f ms", usecs / 1000.0);
    } else {
        return format("%.2f s", usecs / 1_000_000.0);
    }
}

// ============================================================================
// Debug Test Cases
// ============================================================================

void main() {
    import std.array : replicate;
    
    writeln("\n\n");
    writeln("╔" ~ "═".replicate(78) ~ "╗");
    writeln("║" ~ " ".replicate(15) ~ "Wire - Debug Test Suite" ~ " ".replicate(39) ~ "║");
    writeln("║" ~ " ".replicate(10) ~ "Detailed step-by-step HTTP parsing analysis" ~ " ".replicate(24) ~ "║");
    writeln("╚" ~ "═".replicate(78) ~ "╝");
    
    // Test 1: Simple GET
    debugTest(
        "Simple GET Request",
        cast(const(ubyte)[])"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    );
    
    // Test 2: POST with body
    debugTest(
        "POST Request with JSON Body",
        cast(const(ubyte)[])"POST /api/users HTTP/1.1\r\nHost: api.example.com\r\nContent-Type: application/json\r\nContent-Length: 27\r\n\r\n{\"name\":\"John\",\"age\":30}"
    );
    
    // Test 3: Complex browser request
    debugTest(
        "Browser Request with Multiple Headers",
        cast(const(ubyte)[])(
            "GET /index.html HTTP/1.1\r\n" ~
            "Host: www.example.com\r\n" ~
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)\r\n" ~
            "Accept: text/html,application/xhtml+xml\r\n" ~
            "Accept-Language: en-US,en;q=0.9\r\n" ~
            "Accept-Encoding: gzip, deflate, br\r\n" ~
            "Connection: keep-alive\r\n" ~
            "Cache-Control: max-age=0\r\n" ~
            "\r\n"
        )
    );
    
    // Test 4: PUT request
    debugTest(
        "PUT Request",
        cast(const(ubyte)[])"PUT /resource/123 HTTP/1.1\r\nHost: api.example.com\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"updated\":true}"
    );
    
    // Test 5: Request with query string
    debugTest(
        "GET with Query String",
        cast(const(ubyte)[])"GET /search?q=wire+http&lang=en HTTP/1.1\r\nHost: search.example.com\r\n\r\n"
    );
    
    writeln("\n✅ All debug tests completed!\n");
}
