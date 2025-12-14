module http_util_test;

import wire.types;
import std.stdio;

// ============================================================================
// Test Functions for HTTP Utility Functions
// ============================================================================

void testIsWhitespace()
{
    // Test space
    assert(isWhitespace(' '), "Space should be whitespace");
    
    // Test tab
    assert(isWhitespace('\t'), "Tab should be whitespace");
    
    // Test non-whitespace characters
    assert(!isWhitespace('a'), "Letter should not be whitespace");
    assert(!isWhitespace('A'), "Uppercase letter should not be whitespace");
    assert(!isWhitespace('0'), "Digit should not be whitespace");
    assert(!isWhitespace('\n'), "Newline should not be whitespace");
    assert(!isWhitespace('\r'), "Carriage return should not be whitespace");
    assert(!isWhitespace('!'), "Punctuation should not be whitespace");
}

void testTrimWhitespace()
{
    // Test empty string
    assert(trimWhitespace("").length == 0, "Empty string should remain empty");
    
    // Test string with no whitespace
    assert(trimWhitespace("hello") == "hello", "String without whitespace should remain unchanged");
    
    // Test leading spaces
    assert(trimWhitespace("  hello") == "hello", "Leading spaces should be removed");
    
    // Test trailing spaces
    assert(trimWhitespace("hello  ") == "hello", "Trailing spaces should be removed");
    
    // Test leading tabs
    assert(trimWhitespace("\thello") == "hello", "Leading tabs should be removed");
    
    // Test trailing tabs
    assert(trimWhitespace("hello\t") == "hello", "Trailing tabs should be removed");
    
    // Test both leading and trailing
    assert(trimWhitespace("  hello  ") == "hello", "Both leading and trailing spaces should be removed");
    assert(trimWhitespace("\t\thello\t\t") == "hello", "Both leading and trailing tabs should be removed");
    assert(trimWhitespace(" \t hello \t ") == "hello", "Mixed leading and trailing whitespace should be removed");
    
    // Test only whitespace
    assert(trimWhitespace("   ").length == 0, "String with only spaces should become empty");
    assert(trimWhitespace("\t\t\t").length == 0, "String with only tabs should become empty");
    assert(trimWhitespace(" \t \t ").length == 0, "String with only mixed whitespace should become empty");
    
    // Test internal spaces (should not be removed)
    assert(trimWhitespace("  hello world  ") == "hello world", "Internal spaces should be preserved");
    
    // Test zero-copy (same pointer)
    const(char)[] original = "  test  ";
    const(char)[] trimmed = trimWhitespace(original);
    // After trimming, the trimmed slice should point to the same buffer
    assert(trimmed.ptr >= original.ptr && trimmed.ptr < original.ptr + original.length,
           "Trimmed slice should be zero-copy (same buffer)");
}

void testFindHeaderEnd()
{
    // Test empty append
    assert(findHeaderEnd([], []) == 0, "Empty append should return 0");
    assert(findHeaderEnd([1, 2, 3], []) == 0, "Empty append should return 0");
    
    // Test terminator fully in append
    assert(findHeaderEnd([], cast(ubyte[])"\r\n\r\n") == 4, "Terminator in append should return 4");
    assert(findHeaderEnd([], cast(ubyte[])"prefix\r\n\r\n") == 10, "Terminator after prefix should return position");
    
    // Test terminator split across boundary
    // Case 1: \r\n\r in existing, \n in append
    assert(findHeaderEnd(cast(ubyte[])"\r\n\r", cast(ubyte[])"\n") == 1, "Split terminator (last byte in append) should return 1");
    
    // Case 2: \r\n in existing, \r\n in append
    assert(findHeaderEnd(cast(ubyte[])"\r\n", cast(ubyte[])"\r\n") == 2, "Split terminator (last 2 bytes in append) should return 2");
    
    // Case 3: \r in existing, \n\r\n in append
    assert(findHeaderEnd(cast(ubyte[])"\r", cast(ubyte[])"\n\r\n") == 3, "Split terminator (last 3 bytes in append) should return 3");
    
    // Case 4: \r\n\r\n split: \r in existing, \n\r\n in append
    assert(findHeaderEnd(cast(ubyte[])"data\r", cast(ubyte[])"\n\r\nmore") == 3, "Split terminator should be found");
    
    // Test no terminator found
    assert(findHeaderEnd([], cast(ubyte[])"hello") == 0, "No terminator should return 0");
    assert(findHeaderEnd(cast(ubyte[])"data", cast(ubyte[])"more data") == 0, "No terminator should return 0");
    
    // Test terminator at start of append
    assert(findHeaderEnd(cast(ubyte[])"prefix", cast(ubyte[])"\r\n\r\nsuffix") == 4, "Terminator at start of append should return 4");
    
    // Test multiple terminators (should find first)
    assert(findHeaderEnd([], cast(ubyte[])"\r\n\r\n\r\n\r\n") == 4, "First terminator should be found");
    
    // Test terminator in middle of append
    // "value" is 5 chars, terminator starts at position 5, ends at 8, so should return 9
    assert(findHeaderEnd(cast(ubyte[])"header", cast(ubyte[])"value\r\n\r\nbody") == 9, "Terminator in middle should return position after terminator");
    
    // Test cross-boundary with partial match
    assert(findHeaderEnd(cast(ubyte[])"data\r\n\r", cast(ubyte[])"x") == 0, "Partial match should not trigger");
    assert(findHeaderEnd(cast(ubyte[])"data\r\n", cast(ubyte[])"\rx") == 0, "Partial match should not trigger");
    
    // Test exact boundary match
    assert(findHeaderEnd(cast(ubyte[])"\r\n\r", cast(ubyte[])"\n") == 1, "Exact boundary match should work");
}

