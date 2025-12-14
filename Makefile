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
TEST_DIR     := tests
LLHTTP_SRC   := $(SRC_DIR)/wire/c
D_SOURCES    := $(SRC_DIR)/wire

# Output
LIB_NAME     := libwire.a
LIB_OUT      := $(BUILD_DIR)/$(LIB_NAME)

# Compiler Flags
CFLAGS       := -O2 -fPIC -Wall
DFLAGS       := -O2 -I$(SRC_DIR) -I$(TEST_DIR)
DFLAGS_DEBUG := -g -I$(SRC_DIR) -I$(TEST_DIR)
DFLAGS_LIB   := $(DFLAGS) -lib

# Source Files
C_SOURCES    := $(wildcard $(LLHTTP_SRC)/*.c)
C_OBJECTS    := $(patsubst $(LLHTTP_SRC)/%.c,$(BUILD_DIR)/%.o,$(C_SOURCES))

D_FILES      := $(wildcard $(D_SOURCES)/*.d) $(wildcard $(D_SOURCES)/*/*.d)

# Test files (auto-discovered)
TEST_SOURCES := $(wildcard $(TEST_DIR)/*.d)
TEST_TARGETS := $(patsubst $(TEST_DIR)/%.d,$(BUILD_DIR)/%,$(TEST_SOURCES))

# ============================================================================
# Phony Targets
# ============================================================================

.PHONY: all clean test test-verbose test-debug lib help debug

# Default Target
all: test

# Help
help:
	@echo "Wire - High-Performance HTTP Parser - Build Targets"
	@echo "===================================================="
	@echo "  make all           - Build and run tests (default)"
	@echo "  make test          - Compile and run test suite"
	@echo "  make test-verbose  - Run tests with detailed timing"
	@echo "  make test-debug    - Run debug tests (step-by-step analysis)"
	@echo "  make lib           - Build static library"
	@echo "  make debug         - Build tests with debug symbols"
	@echo "  make clean         - Remove all build artifacts"
	@echo "  make help          - Show this help message"
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
test: $(BUILD_DIR)/tests
	@echo ""
	@echo "Running Test Suite..."
	@echo "====================="
	@$(BUILD_DIR)/tests
	@echo ""
	@echo "✓ All tests passed!"

# Run tests with verbose output (timing, stats)
test-verbose: $(BUILD_DIR)/tests
	@echo ""
	@echo "Running Test Suite (Verbose Mode)..."
	@echo "======================================"
	@$(BUILD_DIR)/tests --verbose
	@echo ""

# Run debug tests (detailed step-by-step analysis)
test-debug: $(BUILD_DIR)/debug_tests
	@echo ""
	@echo "Running Debug Test Suite..."
	@echo "============================"
	@$(BUILD_DIR)/debug_tests

# ============================================================================
# Tests (Pattern Rule - builds any test automatically)
# ============================================================================

# Pattern rule: build any test from tests/*.d
$(BUILD_DIR)/%: $(TEST_DIR)/%.d $(C_OBJECTS) $(D_FILES) | $(BUILD_DIR)
	@echo "[DC] Building $*..."
	@$(DC) $(DFLAGS) $(D_FILES) $< $(TEST_DIR)/http_util_test.d $(C_OBJECTS) -of=$@ -od=$(BUILD_DIR)
	@echo "✓ Built: $@"

# Build all tests
tests-all: $(TEST_TARGETS)
	@echo "✓ All tests built in $(BUILD_DIR)/"
	@echo "  Targets: $(notdir $(TEST_TARGETS))"

# Build debug version
debug: DFLAGS := $(DFLAGS_DEBUG)
debug: $(BUILD_DIR)/tests
	@echo "Debug build complete: $(BUILD_DIR)/tests"
	@echo "Run with: lldb $(BUILD_DIR)/tests"

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