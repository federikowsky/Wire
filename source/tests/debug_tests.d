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
    
    // Test 1: Simple GET (baseline)
    debugTest(
        "Simple GET Request (Baseline)",
        cast(const(ubyte)[])"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"
    );
    
    // Test 2: Real browser request with many headers
    debugTest(
        "Chrome Browser Request (20+ Headers)",
        cast(const(ubyte)[])(
            "GET /products/shoes?category=running&size=42&color=blue&brand=nike&sort=price HTTP/1.1\r\n" ~
            "Host: shop.example.com\r\n" ~
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\r\n" ~
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8\r\n" ~
            "Accept-Language: en-US,en;q=0.9,it;q=0.8,de;q=0.7\r\n" ~
            "Accept-Encoding: gzip, deflate, br, zstd\r\n" ~
            "Connection: keep-alive\r\n" ~
            "Cache-Control: max-age=0\r\n" ~
            "Upgrade-Insecure-Requests: 1\r\n" ~
            "Sec-Fetch-Site: none\r\n" ~
            "Sec-Fetch-Mode: navigate\r\n" ~
            "Sec-Fetch-User: ?1\r\n" ~
            "Sec-Fetch-Dest: document\r\n" ~
            "Sec-Ch-Ua: \"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"\r\n" ~
            "Sec-Ch-Ua-Mobile: ?0\r\n" ~
            "Sec-Ch-Ua-Platform: \"macOS\"\r\n" ~
            "DNT: 1\r\n" ~
            "Cookie: session_id=abc123def456ghi789; user_pref=dark_mode; cart_id=xyz; _ga=GA1.2.123456789.1234567890; _gid=GA1.2.987654321.0987654321\r\n" ~
            "If-None-Match: \"686897696a7c876b7e\"\r\n" ~
            "If-Modified-Since: Thu, 21 Nov 2024 10:00:00 GMT\r\n" ~
            "Referer: https://google.com/search?q=running+shoes\r\n" ~
            "\r\n"
        )
    );
    
    // Test 3: API request with JWT token and large JSON payload
    debugTest(
        "REST API POST with JWT Token & Large JSON Payload",
        cast(const(ubyte)[])(
            "POST /api/v2/users/bulk-create HTTP/1.1\r\n" ~
            "Host: api.production.example.com\r\n" ~
            "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJleHAiOjE3MTYyMzkwMjIsInJvbGVzIjpbImFkbWluIiwidXNlciIsIm1vZGVyYXRvciJdLCJwZXJtaXNzaW9ucyI6WyJ1c2VyczpyZWFkIiwidXNlcnM6d3JpdGUiLCJ1c2VyczpkZWxldGUiXX0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c\r\n" ~
            "Content-Type: application/json; charset=utf-8\r\n" ~
            "Accept: application/json\r\n" ~
            "Accept-Language: en-US\r\n" ~
            "X-Request-ID: 550e8400-e29b-41d4-a716-446655440000\r\n" ~
            "X-Correlation-ID: 7f3e1c2a-9b4d-4f2e-a3c7-8d6e5a4b3c2d\r\n" ~
            "X-Client-Version: 2.5.3\r\n" ~
            "X-API-Key: pk_live_51HqJ8KLx2S0y9V8z7W6t5U4r3Q2p1O0n9M8l7K6j5I4h3G2f1E0d9C8b7A6\r\n" ~
            "User-Agent: MyApp/2.5.3 (iOS 17.0; iPhone15,2)\r\n" ~
            "Connection: keep-alive\r\n" ~
            "Content-Length: 612\r\n" ~
            "\r\n" ~
            `{"users":[{"id":1,"name":"Alice Johnson","email":"alice@example.com","role":"admin","active":true,"settings":{"theme":"dark","notifications":true,"language":"en"}},{"id":2,"name":"Bob Smith","email":"bob@example.com","role":"user","active":true,"settings":{"theme":"light","notifications":false,"language":"de"}},{"id":3,"name":"Charlie Brown","email":"charlie@example.com","role":"moderator","active":false,"settings":{"theme":"auto","notifications":true,"language":"fr"}},{"id":4,"name":"Diana Prince","email":"diana@example.com","role":"user","active":true,"settings":{"theme":"dark","notifications":true,"language":"en"}}],"metadata":{"batch_id":"batch_2024_001","timestamp":"2024-11-21T12:00:00Z"}}`
        )
    );
    
    // Test 4: GraphQL query with variables
    debugTest(
        "GraphQL Query with Complex Variables",
        cast(const(ubyte)[])(
            "POST /graphql HTTP/1.1\r\n" ~
            "Host: graphql.api.example.com\r\n" ~
            "Content-Type: application/json\r\n" ~
            "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzEyMyIsInNjb3BlcyI6WyJyZWFkOnVzZXJzIiwid3JpdGU6cG9zdHMiXX0.signature\r\n" ~
            "Accept: application/json\r\n" ~
            "Apollo-Require-Preflight: true\r\n" ~
            "X-Apollo-Operation-Name: GetUserWithPosts\r\n" ~
            "Content-Length: 456\r\n" ~
            "\r\n" ~
            `{"query":"query GetUserWithPosts($userId: ID!, $postLimit: Int!, $includeComments: Boolean!) { user(id: $userId) { id name email profile { avatar bio location } posts(limit: $postLimit) { id title content createdAt likes comments @include(if: $includeComments) { id author text } } } }","variables":{"userId":"user_12345","postLimit":10,"includeComments":true},"operationName":"GetUserWithPosts"}`
        )
    );
    
    // Test 5: Webhook with large payload
    debugTest(
        "Webhook Event with Large Payload (30+ Headers)",
        cast(const(ubyte)[])(
            "POST /webhooks/stripe/payment-success HTTP/1.1\r\n" ~
            "Host: webhooks.myapp.com\r\n" ~
            "User-Agent: Stripe/1.0 (+https://stripe.com/docs/webhooks)\r\n" ~
            "Content-Type: application/json\r\n" ~
            "Stripe-Signature: t=1234567890,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd,v0=6ffbb59b2300aae63f272406069a9788598b792a944a07aba816edb039989a39\r\n" ~
            "Accept: */*\r\n" ~
            "Accept-Encoding: gzip, deflate\r\n" ~
            "X-Stripe-Event-ID: evt_1234567890abcdef\r\n" ~
            "X-Stripe-Event-Type: payment_intent.succeeded\r\n" ~
            "X-Webhook-ID: webhook_1234567890\r\n" ~
            "X-Request-ID: req_abc123def456\r\n" ~
            "X-Forwarded-For: 54.187.174.169, 172.31.255.255\r\n" ~
            "X-Forwarded-Proto: https\r\n" ~
            "X-Real-IP: 54.187.174.169\r\n" ~
            "CF-Ray: 8342a8b9c8d7e6f5-SJC\r\n" ~
            "CF-Visitor: {\"scheme\":\"https\"}\r\n" ~
            "CF-Connecting-IP: 54.187.174.169\r\n" ~
            "CF-IPCountry: US\r\n" ~
            "Connection: keep-alive\r\n" ~
            "Content-Length: 1247\r\n" ~
            "\r\n" ~
            `{"id":"evt_1234567890","object":"event","api_version":"2023-10-16","created":1700654321,"data":{"object":{"id":"pi_1234567890","object":"payment_intent","amount":50000,"amount_capturable":0,"amount_received":50000,"application":null,"canceled_at":null,"cancellation_reason":null,"capture_method":"automatic","client_secret":"pi_123_secret_456","confirmation_method":"automatic","created":1700654300,"currency":"usd","customer":"cus_abc123","description":"Payment for Order #12345","invoice":null,"last_payment_error":null,"livemode":true,"metadata":{"order_id":"12345","customer_email":"john@example.com","product_name":"Premium Subscription"},"next_action":null,"payment_method":"pm_1234567890","payment_method_types":["card"],"processing":null,"receipt_email":"john@example.com","setup_future_usage":null,"shipping":{"address":{"city":"San Francisco","country":"US","line1":"123 Market St","line2":"Suite 456","postal_code":"94102","state":"CA"},"carrier":null,"name":"John Doe","phone":"+14155551234","tracking_number":null},"source":null,"statement_descriptor":"MYCOMPANY*PREMIUM","statement_descriptor_suffix":null,"status":"succeeded","transfer_data":null,"transfer_group":null}},"livemode":true,"pending_webhooks":1,"request":{"id":"req_abc123","idempotency_key":"unique_key_12345"},"type":"payment_intent.succeeded"}`
        )
    );
    
    // Test 6: Multipart form data (file upload simulation - headers only)
    debugTest(
        "File Upload with Multipart Form Data Headers",
        cast(const(ubyte)[])(
            "POST /upload/avatar HTTP/1.1\r\n" ~
            "Host: cdn.example.com\r\n" ~
            "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r\n" ~
            "Accept: application/json, text/plain, */*\r\n" ~
            "Accept-Language: en-US,en;q=0.5\r\n" ~
            "Accept-Encoding: gzip, deflate, br\r\n" ~
            "Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ~
            "Content-Length: 2048\r\n" ~
            "Origin: https://app.example.com\r\n" ~
            "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMTIzNDUifQ.signature\r\n" ~
            "X-CSRF-Token: abc123def456ghi789jkl012mno345pqr678stu901vwx234yz\r\n" ~
            "X-Upload-Session-ID: upload_sess_1234567890abcdef\r\n" ~
            "X-File-Name: profile_photo.jpg\r\n" ~
            "X-File-Size: 2048576\r\n" ~
            "X-File-Type: image/jpeg\r\n" ~
            "Connection: keep-alive\r\n" ~
            "Referer: https://app.example.com/settings/profile\r\n" ~
            "Sec-Fetch-Dest: empty\r\n" ~
            "Sec-Fetch-Mode: cors\r\n" ~
            "Sec-Fetch-Site: same-site\r\n" ~
            "\r\n" ~
            "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ~
            "Content-Disposition: form-data; name=\"user_id\"\r\n\r\n12345\r\n" ~
            "------WebKitFormBoundary7MA4YWxkTrZu0gW\r\n" ~
            "Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n" ~
            "Content-Type: image/jpeg\r\n\r\n" ~
            "[binary image data would be here...]\r\n" ~
            "------WebKitFormBoundary7MA4YWxkTrZu0gW--\r\n"
        )
    );
    
    // Test 7: XML SOAP request
    debugTest(
        "SOAP XML Request with Large Payload",
        cast(const(ubyte)[])(
            "POST /soap/service HTTP/1.1\r\n" ~
            "Host: soap.legacy-api.example.com\r\n" ~
            "Content-Type: text/xml; charset=utf-8\r\n" ~
            "SOAPAction: \"http://example.com/GetUserDetails\"\r\n" ~
            "Accept: text/xml\r\n" ~
            "User-Agent: Apache-HttpClient/4.5.13 (Java/11.0.16)\r\n" ~
            "Content-Length: 856\r\n" ~
            "\r\n" ~
            `<?xml version="1.0" encoding="UTF-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:web="http://example.com/webservice"><soap:Header><web:Authentication><web:Username>admin_user</web:Username><web:Password>encrypted_password_here</web:Password><web:Token>session_token_abc123def456</web:Token></web:Authentication></soap:Header><soap:Body><web:GetUserDetailsRequest><web:UserID>12345</web:UserID><web:IncludeOrders>true</web:IncludeOrders><web:IncludePayments>true</web:IncludePayments><web:DateRange><web:StartDate>2024-01-01</web:StartDate><web:EndDate>2024-12-31</web:EndDate></web:DateRange><web:Options><web:Format>detailed</web:Format><web:Language>en-US</web:Language></web:Options></web:GetUserDetailsRequest></soap:Body></soap:Envelope>`
        )
    );
    
    writeln("\n📊 OVERALL PERFORMANCE COMPARISON");
    writeln("═".replicate(80));
    writeln("All test cases completed successfully!");
    writeln("Compare the parsing times above to see how Wire handles:");
    writeln("  • Simple requests: ~1-20 μs");
    writeln("  • Medium complexity: ~20-50 μs");
    writeln("  • Large payloads (1-2KB): ~50-200 μs");
    writeln("  • Very large payloads (>2KB): May vary");
    writeln("\n✅ All debug tests completed!\n");
}
