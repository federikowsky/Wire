import std.stdio;
import std.exception;
import core.exception;
import std.string : format;
import std.array : appender;
import core.time : MonoTime, Duration;
import wire;
import wire.parser;
import wire.types;

// ============================================================================
// Test Framework
// ============================================================================

private int passedTests = 0;
private int failedTests = 0;
private bool verboseMode = false;
private Duration totalTime;

void setVerbose(bool v)
{
    verboseMode = v;
}

void runTest(string name, void function() test)
{
    writef("  %-50s ... ", name);
    stdout.flush();

    auto startTime = MonoTime.currTime;

    try
    {
        test();
        auto elapsed = MonoTime.currTime - startTime;
        totalTime += elapsed;

        if (verboseMode)
        {
            writefln("\x1b[32mPASS\x1b[0m (%s)", formatDuration(elapsed));
        }
        else
        {
            writeln("\x1b[32mPASS\x1b[0m");
        }
        passedTests++;
    }
    catch (Throwable e)
    {
        auto elapsed = MonoTime.currTime - startTime;
        totalTime += elapsed;

        writeln("\x1b[31mFAIL\x1b[0m");
        writeln("    Error: ", e.msg);
        writeln("    File: ", e.file, ":", e.line);
        if (verboseMode)
        {
            writeln("    Time: ", formatDuration(elapsed));
        }
        failedTests++;
    }
}

string formatDuration(Duration d)
{
    auto usecs = d.total!"usecs";
    if (usecs < 1000)
    {
        return format("%d μs", usecs);
    }
    else if (usecs < 1_000_000)
    {
        return format("%.2f ms", usecs / 1000.0);
    }
    else
    {
        return format("%.2f s", usecs / 1_000_000.0);
    }
}

void testSection(string name)
{
    import std.array : replicate;

    writeln("\n\x1b[1m", name, "\x1b[0m");
    writeln(replicate("=", name.length));
}

// ============================================================================
// Happy Path Tests
// ============================================================================

void testSimpleGET()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req, "Parsing failed");
    assert(req.getMethod() == "GET");
    assert(req.getPath() == "/");
    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 1);
}

void testGETWithPath()
{
    auto data = cast(const(ubyte)[]) "GET /api/v1/users?page=2 HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "GET");
    assert(req.getPath() == "/api/v1/users");
    assert(req.getQuery() == "page=2");
    assert(req.getHeader("Host") == "localhost");
}

void testPOSTWithBody()
{
    auto data = cast(const(ubyte)[]) "POST /submit HTTP/1.1\r\nContent-Length: 11\r\n\r\nHello World";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "POST");
    assert(req.getPath() == "/submit");
    assert(req.getBody() == "Hello World");
    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 1);
}

void testPUTRequest()
{
    auto data = cast(const(ubyte)[]) "PUT /resource/123 HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 10\r\n\r\n{\"id\":123}";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "PUT");
    assert(req.getPath() == "/resource/123");
    assert(req.getHeader("Content-Type") == "application/json");
    assert(req.getBody() == "{\"id\":123}");
}

void testDELETERequest()
{
    auto data = cast(const(ubyte)[]) "DELETE /users/42 HTTP/1.1\r\nAuthorization: Bearer token\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "DELETE");
    assert(req.getPath() == "/users/42");
    assert(req.getHeader("Authorization") == "Bearer token");
}

void testHEADRequest()
{
    auto data = cast(const(ubyte)[]) "HEAD /index.html HTTP/1.1\r\nHost: www.example.com\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "HEAD");
    assert(req.getPath() == "/index.html");
}

void testOPTIONSRequest()
{
    auto data = cast(const(ubyte)[]) "OPTIONS * HTTP/1.1\r\nHost: api.example.com\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getMethod() == "OPTIONS");
    assert(req.getPath() == "*");
}

// ============================================================================
// Query String Tests
// ============================================================================

void testQueryStringSingle()
{
    auto data = cast(const(ubyte)[]) "GET /search?q=hello HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getPath() == "/search");
    assert(req.getQuery() == "q=hello");
}

void testQueryStringMultiple()
{
    auto data = cast(const(ubyte)[]) "GET /api/users?page=2&limit=10&sort=name HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getPath() == "/api/users");
    assert(req.getQuery() == "page=2&limit=10&sort=name");
}

void testQueryStringEmpty()
{
    auto data = cast(const(ubyte)[]) "GET /path HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getPath() == "/path");
    assert(req.getQuery().empty);
}

void testQueryStringEmptyValue()
{
    auto data = cast(const(ubyte)[]) "GET /path? HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getPath() == "/path");
    assert(req.getQuery().empty); // Query after ? is empty
}

void testQueryParamSingle()
{
    auto data = cast(const(ubyte)[]) "GET /search?q=hello HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.hasQueryParam("q"));
    assert(req.getQueryParam("q") == "hello");
    assert(!req.hasQueryParam("missing"));
    assert(req.getQueryParam("missing").isNull);
}

void testQueryParamMultiple()
{
    auto data = cast(const(ubyte)[]) "GET /api?page=2&limit=10&sort=name HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getQueryParam("page") == "2");
    assert(req.getQueryParam("limit") == "10");
    assert(req.getQueryParam("sort") == "name");
}

void testQueryParamEmptyValue()
{
    auto data = cast(const(ubyte)[]) "GET /api?flag=&other=value HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.hasQueryParam("flag"));
    assert(req.getQueryParam("flag").empty); // Has key but empty value
    assert(req.getQueryParam("other") == "value");
}

void testQueryParamNoValue()
{
    auto data = cast(const(ubyte)[]) "GET /api?debug&verbose&limit=5 HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.hasQueryParam("debug"));
    assert(req.hasQueryParam("verbose"));
    assert(req.getQueryParam("limit") == "5");
}

// ============================================================================
// Header Tests
// ============================================================================

void testMultipleHeaders()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nHost: example.com\r\nUser-Agent: TestClient\r\nAccept: */*\r\nConnection: keep-alive\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getHeader("Host") == "example.com");
    assert(req.getHeader("User-Agent") == "TestClient");
    assert(req.getHeader("Accept") == "*/*");
    assert(req.getHeader("Connection") == "keep-alive");
}

void testCaseInsensitiveHeaders()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nHOST: example.com\r\nuser-agent: D-Test\r\nCoNtEnT-tYpE: text/html\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getHeader("host") == "example.com");
    assert(req.getHeader("Host") == "example.com");
    assert(req.getHeader("HOST") == "example.com");
    assert(req.getHeader("User-Agent") == "D-Test");
    assert(req.getHeader("content-type") == "text/html");
}

void testHeaderWithSpaces()
{
    // llhttp trims leading whitespace, keeps trailing
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nX-Custom-Header:   value with spaces   \r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    auto value = req.getHeader("X-Custom-Header");
    // llhttp trims leading spaces after colon, may keep trailing
    assert(value.length > 0, "Header value should not be empty");
    // Value contains "value with spaces" (may have trailing spaces)
    import std.algorithm : canFind;

    assert(value.toString().canFind("value with spaces"));
}

void testEmptyHeaderValue()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nX-Empty: \r\nX-Normal: value\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.hasHeader("X-Empty"), "Empty header should be detected");
    assert(req.hasHeader("X-Normal"));
    auto value = req.getHeader("X-Empty");
    assert(value.empty, "Empty header should have empty value");
}

void testManyHeaders()
{
    auto app = appender!(ubyte[])();
    app.put(cast(const(ubyte)[]) "GET / HTTP/1.1\r\n");

    // Add 30 headers (well below limit)
    for (int i = 0; i < 30; i++)
    {
        app.put(cast(const(ubyte)[]) format("X-Header-%d: value-%d\r\n", i, i));
    }
    app.put(cast(const(ubyte)[]) "\r\n");

    auto req = parseHTTP(app.data);
    assert(req);
    assert(req.getHeader("X-Header-0") == "value-0");
    assert(req.getHeader("X-Header-15") == "value-15");
    assert(req.getHeader("X-Header-29") == "value-29");
}

void testHeaderIteration()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nA: 1\r\nB: 2\r\nC: 3\r\n\r\n";
    auto req = parseHTTP(data);

    int count = 0;
    foreach (header; req.getHeaders())
    {
        count++;
    }
    assert(count == 3);
}

// ============================================================================
// HTTP Version Tests
// ============================================================================

void testHTTP10()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.0\r\nConnection: close\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 0);
    assert(req.getVersion() == "1.0");
}

void testHTTP11()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 1);
    assert(req.getVersion() == "1.1");
    assert(req.shouldKeepAlive() == true); // HTTP/1.1 default keep-alive
}

void testHTTP11ExplicitClose()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nConnection: close\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 1);
    assert(req.shouldKeepAlive() == false);
}

void testHTTP10ExplicitKeepAlive()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req.getVersionMajor() == 1);
    assert(req.getVersionMinor() == 0);
    assert(req.shouldKeepAlive() == true);
}

// ============================================================================
// Edge Cases & Limits
// ============================================================================

void testHeaderOverflow()
{
    auto app = appender!(ubyte[])();
    app.put(cast(const(ubyte)[]) "GET / HTTP/1.1\r\n");

    // Add 65 headers (limit is 64)
    for (int i = 0; i < 65; i++)
    {
        app.put(cast(const(ubyte)[]) format("H-%d: v\r\n", i));
    }
    app.put(cast(const(ubyte)[]) "\r\n");

    auto req = parseHTTP(app.data);
    assert(!req, "Should fail due to header overflow");
    assert(req.getErrorCode() == 24); // HPE_USER
}

void testLongPath()
{
    import std.array : replicate;

    auto longPath = "/very/long/path" ~ replicate("/segment", 50);
    auto data = cast(const(ubyte)[]) format("GET %s HTTP/1.1\r\n\r\n", longPath);
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getPath() == longPath);
}

void testLongHeaderValue()
{
    import std.array : replicate;

    auto longValue = replicate("x", 1000);
    auto data = cast(const(ubyte)[]) format("GET / HTTP/1.1\r\nX-Long: %s\r\n\r\n", longValue);
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getHeader("X-Long") == longValue);
}

void testEmptyRequest()
{
    // llhttp allows leading CRLF per HTTP/1.1 spec (RFC 7230 section 3.5)
    // "a server that is expecting to receive and parse a request-line
    // SHOULD ignore at least one empty line (CRLF) received prior to the request-line"
    auto data = cast(const(ubyte)[]) "\r\n\r\n";
    auto req = parseHTTP(data);

    // This is valid per HTTP spec - llhttp returns success but no useful data
    // Since there's no actual request, method will be empty
    assert(req.getMethod().empty || !req, "Empty CRLF should either succeed with no method or fail");
}

// ============================================================================
// Error Handling Tests
// ============================================================================

void testMalformedRequest()
{
    auto data = cast(const(ubyte)[]) "INVALID REQUEST\r\n\r\n";
    auto req = parseHTTP(data);

    assert(!req, "Should fail on malformed request");
    assert(req.getErrorCode() == 6, "Should be HPE_INVALID_METHOD"); // HPE_INVALID_METHOD = 6
}

void testInvalidVersion()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/9.9\r\n\r\n";
    auto req = parseHTTP(data);

    assert(!req, "Should fail on invalid HTTP version");
}

void testInvalidHeaderFormat()
{
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nInvalidHeaderNoColon\r\n\r\n";
    auto req = parseHTTP(data);

    assert(!req, "Should fail on header without colon");
}

// ============================================================================
// Real-World Scenarios
// ============================================================================

void testTypicalBrowserRequest()
{
    auto data = cast(const(ubyte)[])(
        "GET /index.html HTTP/1.1\r\n" ~
            "Host: www.example.com\r\n" ~
            "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)\r\n" ~
            "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n" ~
            "Accept-Language: en-US,en;q=0.9\r\n" ~
            "Accept-Encoding: gzip, deflate, br\r\n" ~
            "Connection: keep-alive\r\n" ~
            "\r\n"
    );

    auto req = parseHTTP(data);
    assert(req);
    assert(req.getMethod() == "GET");
    assert(req.getPath() == "/index.html");
    assert(req.getHeader("Host") == "www.example.com");
    assert(req.getHeader("Accept-Encoding") == "gzip, deflate, br");
    assert(req.shouldKeepAlive());
}

void testAPIRequest()
{
    auto body = `{"username":"test","password":"secret123"}`;
    auto data = cast(const(ubyte)[]) format(
        "POST /api/v2/auth/login HTTP/1.1\r\n" ~
            "Host: api.example.com\r\n" ~
            "Content-Type: application/json\r\n" ~
            "Content-Length: %d\r\n" ~
            "\r\n%s",
            body.length, body
    );

    auto req = parseHTTP(data);
    assert(req);
    assert(req.getMethod() == "POST");
    assert(req.getPath() == "/api/v2/auth/login");
    assert(req.getHeader("Content-Type") == "application/json");
    assert(req.getBody() == body);
}

void testChunkedEncoding()
{
    auto data = cast(const(ubyte)[])(
        "POST /upload HTTP/1.1\r\n" ~
            "Host: upload.example.com\r\n" ~
            "Transfer-Encoding: chunked\r\n" ~
            "\r\n"
    );

    auto req = parseHTTP(data);
    assert(req);
    assert(req.hasHeader("Transfer-Encoding"));
}

// ============================================================================
// Security Tests
// ============================================================================

void testPATCHRequest()
{
    auto data = cast(const(ubyte)[]) "PATCH /users/123 HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{\"name\":\"test\"}";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getMethod() == "PATCH");
    assert(req.getPath() == "/users/123");
    assert(req.getBody() == "{\"name\":\"test\"}");
}

void testMultipleSameNameHeaders()
{
    // HTTP allows multiple headers with same name (e.g., Set-Cookie, Cookie)
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nCookie: a=1\r\nCookie: b=2\r\nHost: test\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    // Wire returns the first matching header (this is implementation-defined behavior)
    auto cookie = req.getHeader("Cookie");
    assert(cookie == "a=1" || cookie == "b=2", "Should return one of the Cookie values");

    // Count total Cookie headers through iteration
    int cookieCount = 0;
    foreach (h; req.getHeaders())
    {
        if (h.name.equalsIgnoreCase("Cookie"))
        {
            cookieCount++;
        }
    }
    assert(cookieCount == 2, "Should have 2 Cookie headers");
}

void testContentLengthBodyMatch()
{
    // Body exactly matches Content-Length
    auto data = cast(const(ubyte)[]) "POST /test HTTP/1.1\r\nContent-Length: 5\r\n\r\nHello";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getBody() == "Hello");
}

void testURLEncodedPath()
{
    // URL with percent-encoding (Wire should preserve as-is)
    auto data = cast(const(ubyte)[]) "GET /path%20with%20spaces HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    // Wire does NOT decode URLs - they are passed through as-is
    assert(req.getPath() == "/path%20with%20spaces");
}

void testURLEncodedQuery()
{
    auto data = cast(const(ubyte)[]) "GET /search?q=hello%20world&name=%3Cscript%3E HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getPath() == "/search");
    // Query is preserved as-is (no decoding)
    assert(req.getQuery() == "q=hello%20world&name=%3Cscript%3E");
}

void testSpecialCharactersInPath()
{
    auto data = cast(const(ubyte)[]) "GET /api/v1/users/test@example.com HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getPath() == "/api/v1/users/test@example.com");
}

void testVeryLongQueryString()
{
    import std.array : replicate;

    auto longQuery = replicate("x", 2000);
    auto data = cast(const(ubyte)[]) format("GET /search?q=%s HTTP/1.1\r\n\r\n", longQuery);
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getQuery() == "q=" ~ longQuery);
}

void testNullByteInPath()
{
    // Null bytes in path should be handled gracefully
    auto data = cast(const(ubyte)[]) "GET /path\x00evil HTTP/1.1\r\n\r\n";
    auto req = parseHTTP(data);

    // llhttp may reject this or pass it through - either is acceptable
    // The key is no crash/segfault
    if (req)
    {
        // If accepted, path should stop at null or include it
        assert(req.getPath().length >= 5); // At least "/path"
    }
}

void testTraceMethod()
{
    // TRACE is security-sensitive but valid HTTP method
    auto data = cast(const(ubyte)[]) "TRACE / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    auto req = parseHTTP(data);

    assert(req);
    assert(req.getMethod() == "TRACE");
}

void testConnectMethod()
{
    // CONNECT for proxy tunneling - llhttp pauses on this (HPE_PAUSED_UPGRADE)
    // because it switches to tunnel mode
    auto data = cast(const(ubyte)[]) "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n";
    auto req = parseHTTP(data);

    // llhttp returns HPE_PAUSED_UPGRADE (22) for CONNECT - this is expected
    // The method is still parsed correctly even if the overall parse "fails"
    // Note: Some applications may want to handle this differently
    if (!req)
    {
        assert(req.getErrorCode() == 22, "CONNECT should return HPE_PAUSED_UPGRADE");
    }
    else
    {
        assert(req.getMethod() == "CONNECT");
    }
}

void testTruncatedRequest()
{
    // Request truncated mid-header (no CRLF at end)
    auto data = cast(const(ubyte)[]) "GET / HTTP/1.1\r\nHost: exam";
    auto req = parseHTTP(data);

    // Parser should handle gracefully - may succeed with partial data or fail
    // Key is: no crash, no segfault
    if (req)
    {
        // If it parses, method should still be correct
        assert(req.getMethod() == "GET");
    }
    // Either way, we survived without crashing
}

void testIncompleteBody()
{
    // Request with Content-Length but body is shorter
    auto data = cast(const(ubyte)[]) "POST /submit HTTP/1.1\r\nContent-Length: 100\r\n\r\nShort";
    auto req = parseHTTP(data);

    // Parser should handle gracefully - body may be partial or empty
    // Key is: no crash, predictable behavior
    if (req)
    {
        assert(req.getMethod() == "POST");
        assert(req.getPath() == "/submit");
        // Body may be partial or empty depending on llhttp behavior
    }
}

// ============================================================================
// Main Test Runner
// ============================================================================

void main(string[] args)
{
    // Parse command line arguments
    foreach (arg; args[1 .. $])
    {
        if (arg == "-v" || arg == "--verbose")
        {
            setVerbose(true);
        }
    }

    writeln("\n\x1b[1;36m╔══════════════════════════════════════════════════════════╗\x1b[0m");
    writeln("\x1b[1;36m║         Wire - Comprehensive Test Suite                 ║\x1b[0m");
    writeln("\x1b[1;36m╚══════════════════════════════════════════════════════════╝\x1b[0m");

    if (verboseMode)
    {
        writeln("\n\x1b[1;33m[VERBOSE MODE]\x1b[0m");
        writeln("Showing detailed timing and output information\n");
    }

    auto overallStart = MonoTime.currTime;

    testSection("Happy Path Tests");
    runTest("Simple GET request", &testSimpleGET);
    runTest("GET with path and query", &testGETWithPath);
    runTest("POST with body", &testPOSTWithBody);
    runTest("PUT request", &testPUTRequest);
    runTest("DELETE request", &testDELETERequest);
    runTest("HEAD request", &testHEADRequest);
    runTest("OPTIONS request", &testOPTIONSRequest);

    testSection("Query String Tests");
    runTest("Query string single param", &testQueryStringSingle);
    runTest("Query string multiple params", &testQueryStringMultiple);
    runTest("Query string empty (no ?)", &testQueryStringEmpty);
    runTest("Query string empty value", &testQueryStringEmptyValue);
    runTest("Query param single", &testQueryParamSingle);
    runTest("Query param multiple", &testQueryParamMultiple);
    runTest("Query param empty value", &testQueryParamEmptyValue);
    runTest("Query param no value (flag)", &testQueryParamNoValue);

    testSection("Header Tests");
    runTest("Multiple headers", &testMultipleHeaders);
    runTest("Case-insensitive headers", &testCaseInsensitiveHeaders);
    runTest("Header with spaces", &testHeaderWithSpaces);
    runTest("Empty header value", &testEmptyHeaderValue);
    runTest("Many headers (30)", &testManyHeaders);
    runTest("Header iteration", &testHeaderIteration);

    testSection("HTTP Version Tests");
    runTest("HTTP/1.0", &testHTTP10);
    runTest("HTTP/1.1", &testHTTP11);
    runTest("HTTP/1.1 explicit close", &testHTTP11ExplicitClose);
    runTest("HTTP/1.0 explicit keep-alive", &testHTTP10ExplicitKeepAlive);

    testSection("Edge Cases & Limits");
    runTest("Header overflow (65 headers)", &testHeaderOverflow);
    runTest("Long path", &testLongPath);
    runTest("Long header value", &testLongHeaderValue);
    runTest("Empty request (CRLF only)", &testEmptyRequest);

    testSection("Error Handling");
    runTest("Malformed request", &testMalformedRequest);
    runTest("Invalid version", &testInvalidVersion);
    runTest("Invalid header format", &testInvalidHeaderFormat);

    testSection("Real-World Scenarios");
    runTest("Typical browser request", &testTypicalBrowserRequest);
    runTest("API request with JSON", &testAPIRequest);
    runTest("Chunked encoding", &testChunkedEncoding);

    testSection("Security Tests");
    runTest("PATCH request", &testPATCHRequest);
    runTest("Multiple same-name headers", &testMultipleSameNameHeaders);
    runTest("Content-Length body match", &testContentLengthBodyMatch);
    runTest("URL encoded path", &testURLEncodedPath);
    runTest("URL encoded query", &testURLEncodedQuery);
    runTest("Special characters in path", &testSpecialCharactersInPath);
    runTest("Very long query string", &testVeryLongQueryString);
    runTest("Null byte in path", &testNullByteInPath);
    runTest("TRACE method", &testTraceMethod);
    runTest("CONNECT method", &testConnectMethod);

    testSection("Edge Case Tests (Robustness)");
    runTest("Truncated request mid-header", &testTruncatedRequest);
    runTest("Incomplete body (short Content-Length)", &testIncompleteBody);

    auto overallElapsed = MonoTime.currTime - overallStart;

    // Summary
    import std.array : replicate;

    writeln("\n\x1b[1;36m" ~ replicate("─", 60) ~ "\x1b[0m");
    writeln("\x1b[1mTest Results:\x1b[0m");
    writeln("  \x1b[32mPassed:\x1b[0m ", passedTests);
    writeln("  \x1b[31mFailed:\x1b[0m ", failedTests);
    writeln("  \x1b[1mTotal:\x1b[0m  ", passedTests + failedTests);

    if (verboseMode)
    {
        writeln("\n\x1b[1mPerformance:\x1b[0m");
        writeln("  Total time:    ", formatDuration(overallElapsed));
        writeln("  Test time:     ", formatDuration(totalTime));
        writeln("  Overhead:      ", formatDuration(overallElapsed - totalTime));
        writeln("  Avg per test:  ", formatDuration(totalTime / (passedTests + failedTests)));

        auto testsPerSec = (passedTests + failedTests) / (
            overallElapsed.total!"usecs" / 1_000_000.0);
        writeln("  Tests/second:  ", format("%.2f", testsPerSec));
    }

    if (failedTests == 0)
    {
        writeln("\n\x1b[1;32m✓ All tests passed!\x1b[0m\n");
    }
    else
    {
        writeln("\n\x1b[1;31m✗ Some tests failed!\x1b[0m\n");
        import core.stdc.stdlib : exit;

        exit(1);
    }
}
