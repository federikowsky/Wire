# ============================================================================
# Wire - High-Performance HTTP Parser for D
# ============================================================================

# Compiler Configuration
CC       := cc
DC       := ldc2
AR       := ar

# Directories
BUILD_DIR    := build
SRC_DIR      := source
LLHTTP_SRC   := $(SRC_DIR)/wire/c
D_SOURCES    := $(SRC_DIR)/wire

# Output
LIB_NAME     := libwire.a
TEST_BIN     := $(BUILD_DIR)/tests
LIB_OUT      := $(BUILD_DIR)/$(LIB_NAME)

# Compiler Flags
CFLAGS       := -O3 -march=native -fPIC -Wall
DFLAGS       := -O3 -mcpu=native -I$(SRC_DIR) -betterC=false
DFLAGS_DEBUG := -g -I$(SRC_DIR)
DFLAGS_LIB   := $(DFLAGS) -lib

# Source Files
C_SOURCES    := $(wildcard $(LLHTTP_SRC)/*.c)
C_OBJECTS    := $(patsubst $(LLHTTP_SRC)/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))

D_FILES      := $(D_SOURCES)/types.d \
                $(D_SOURCES)/bindings.d \
                $(D_SOURCES)/parser.d \
                $(D_SOURCES)/package.d

TEST_FILE    := $(SRC_DIR)/tests/tests.d

# ============================================================================
# Phony Targets
# ============================================================================

.PHONY: all clean test lib help debug

# Default Target
all: test

# Help
help:
	@echo "Wire - High-Performance HTTP Parser - Build Targets"
	@echo "===================================================="
	@echo "  make all      - Build and run tests (default)"
	@echo "  make test     - Compile and run test suite"
	@echo "  make lib      - Build static library"
	@echo "  make debug    - Build tests with debug symbols"
	@echo "  make clean    - Remove all build artifacts"
	@echo "  make help     - Show this help message"
	@echo ""
	@echo "Build directory: $(BUILD_DIR)/"
	@echo "Library output:  $(LIB_OUT)"

# ============================================================================
# Build Rules
# ============================================================================

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Compile C sources to object files
$(BUILD_DIR)/%.o: $(LLHTTP_SRC)/%.c | $(BUILD_DIR)
	@echo "[CC] $< -> $@"
	@$(CC) $(CFLAGS) -c $< -o $@

# Build static library
lib: $(LIB_OUT)

$(LIB_OUT): $(C_OBJECTS) $(D_FILES) | $(BUILD_DIR)
	@echo "[DC] Building library: $@"
	@$(DC) $(DFLAGS_LIB) $(D_FILES) $(C_OBJECTS) -of=$@ -od=$(BUILD_DIR)
	@echo "✓ Library built: $@"

# Build test executable
test: $(TEST_BIN)
	@echo ""
	@echo "Running Test Suite..."
	@echo "====================="
	@$(TEST_BIN)
	@echo ""
	@echo "✓ All tests passed!"

$(TEST_BIN): $(C_OBJECTS) $(D_FILES) $(TEST_FILE) | $(BUILD_DIR)
	@echo "[DC] Building tests: $@"
	@$(DC) $(DFLAGS) $(D_FILES) $(TEST_FILE) $(C_OBJECTS) -of=$@ -od=$(BUILD_DIR)

# Build debug version
debug: DFLAGS := $(DFLAGS_DEBUG)
debug: $(TEST_BIN)
	@echo "Debug build complete: $(TEST_BIN)"
	@echo "Run with: lldb $(TEST_BIN)"

# ============================================================================
# Utility Targets
# ============================================================================

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean complete"

# Show build info
info:
	@echo "Build Configuration"
	@echo "==================="
	@echo "C Compiler:    $(CC)"
	@echo "D Compiler:    $(DC)"
	@echo "C Flags:       $(CFLAGS)"
	@echo "D Flags:       $(DFLAGS)"
	@echo "Build Dir:     $(BUILD_DIR)"
	@echo ""
	@echo "Source Files"
	@echo "============"
	@echo "C Sources:     $(words $(C_SOURCES)) files"
	@echo "D Modules:     $(words $(D_FILES)) files"
	@echo ""
	@echo "Output"
	@echo "======"
	@echo "Library:       $(LIB_OUT)"
	@echo "Tests:         $(TEST_BIN)"
