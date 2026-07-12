module app;

import wire;

void main()
{
    enum raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n";
    auto parser = createParser();
    assert(parser !is null);
    scope (exit) destroyParser(parser);

    auto error = parseHTTPWith(parser, cast(const(ubyte)[]) raw);
    assert(cast(int) error == 0);

    assert(getRequest(parser).routing.messageComplete);
    assert(getRequest(parser).getMethod() == "GET");
    assert(getRequest(parser).getPath() == "/health");
}
