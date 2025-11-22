module llhttp.bindings;

import core.stdc.stdint;

/**
 * LLHTTP C Bindings
 * Minimal bindings required for the wrapper.
 */
extern(C) @nogc nothrow:

// --- Types ---

// llhttp_t struct definition (mirrored from llhttp.h v9.3.0)
// We only define fields up to what we need (http_minor) to avoid padding issues if struct grows.
// However, for correct pointer arithmetic if we ever did it (we don't), we'd need full size.
// Since we only access fields via pointer, prefix matching is sufficient.
struct llhttp_t {
    int32_t _index;
    void* _span_pos0;
    void* _span_cb0;
    int32_t error;
    const(char)* reason;
    const(char)* error_pos;
    void* data;
    void* _current;
    uint64_t content_length;
    uint8_t type;
    uint8_t method;
    uint8_t http_major;
    uint8_t http_minor;
    uint8_t header_state;
    uint16_t lenient_flags;
    uint8_t upgrade;
    uint8_t finish;
    uint16_t flags;
    uint16_t status_code;
    uint8_t initial_message_completed;
    void* settings;
}

enum llhttp_errno {
    HPE_OK = 0,
    HPE_INTERNAL = 1,
    HPE_STRICT = 2,
    HPE_LF_EXPECTED = 3,
    HPE_UNEXPECTED_CONTENT_LENGTH = 4,
    HPE_CLOSED_CONNECTION = 5,
    HPE_INVALID_METHOD = 6,
    HPE_INVALID_URL = 7,
    HPE_INVALID_CONSTANT = 8,
    HPE_INVALID_VERSION = 9,
    HPE_INVALID_HEADER_TOKEN = 10,
    HPE_INVALID_CONTENT_LENGTH = 11,
    HPE_INVALID_CHUNK_SIZE = 12,
    HPE_INVALID_STATUS = 13,
    HPE_INVALID_EOF_STATE = 14,
    HPE_INVALID_TRANSFER_ENCODING = 15,
    HPE_CB_MESSAGE_BEGIN = 16,
    HPE_CB_HEADERS_COMPLETE = 17,
    HPE_CB_MESSAGE_COMPLETE = 18,
    HPE_CB_CHUNK_HEADER = 19,
    HPE_CB_CHUNK_COMPLETE = 20,
    HPE_PAUSED = 21,
    HPE_PAUSED_UPGRADE = 22,
    HPE_PAUSED_H2_UPGRADE = 23,
    HPE_USER = 24,
    HPE_CB_URL_COMPLETE = 25,
    HPE_CB_STATUS_COMPLETE = 26,
    HPE_CB_METHOD_COMPLETE = 27,
    HPE_CB_VERSION_COMPLETE = 28,
    HPE_CB_HEADER_FIELD_COMPLETE = 29,
    HPE_CB_HEADER_VALUE_COMPLETE = 30,
    HPE_CB_CHUNK_EXTENSION_NAME_COMPLETE = 31,
    HPE_CB_CHUNK_EXTENSION_VALUE_COMPLETE = 32,
    HPE_CB_RESET = 33
}

enum llhttp_type {
    HTTP_BOTH = 0,
    HTTP_REQUEST = 1,
    HTTP_RESPONSE = 2
}

// Callback function pointer types
alias llhttp_cb = int function(llhttp_t*);
alias llhttp_data_cb = int function(llhttp_t*, const(char)* at, size_t length);

struct llhttp_settings_t {
    // Exact order from llhttp.h
    llhttp_cb      on_message_begin;
    llhttp_data_cb on_protocol;
    llhttp_data_cb on_url;
    llhttp_data_cb on_status;
    llhttp_data_cb on_method;
    llhttp_data_cb on_version;
    llhttp_data_cb on_header_field;
    llhttp_data_cb on_header_value;
    llhttp_data_cb on_chunk_extension_name;
    llhttp_data_cb on_chunk_extension_value;
    llhttp_cb      on_headers_complete;
    llhttp_data_cb on_body;
    llhttp_cb      on_message_complete;
    llhttp_cb      on_protocol_complete;
    llhttp_cb      on_url_complete;
    llhttp_cb      on_status_complete;
    llhttp_cb      on_method_complete;
    llhttp_cb      on_version_complete;
    llhttp_cb      on_header_field_complete;
    llhttp_cb      on_header_value_complete;
    llhttp_cb      on_chunk_extension_name_complete;
    llhttp_cb      on_chunk_extension_value_complete;
    llhttp_cb      on_chunk_header;
    llhttp_cb      on_chunk_complete;
   llhttp_cb      on_reset;
}

// --- Functions ---
void llhttp_init(llhttp_t* parser, llhttp_type type, const(llhttp_settings_t)* settings);
llhttp_errno llhttp_execute(llhttp_t* parser, const(char)* data, size_t len);
void llhttp_reset(llhttp_t* parser);
const(char)* llhttp_errno_name(llhttp_errno err);
const(char)* llhttp_get_error_reason(const(llhttp_t)* parser);
void llhttp_set_error_reason(llhttp_t* parser, const(char)* reason);

// Helpers
int llhttp_should_keep_alive(const(llhttp_t)* parser);
