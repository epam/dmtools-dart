# Makefile — dmtools-dart build system (macOS / Linux / Windows)
#
# Cross-platform build for the dmtools CLI:
#   make deps     — install Dart dependencies
#   make native   — compile the QuickJS shared library for your platform
#   make build    — compile the standalone `dmtools` executable
#   make install  — build + install into ~/.local/bin (macOS/Linux)
#   make test     — run the test suite
#
# Windows requires MinGW-w64 (gcc) on PATH — the bridge uses GCC atomics.

.DEFAULT_GOAL := help
.PHONY: help deps native build run test test-cov analyze format gates install clean clean-native clean-build

# ── Platform detection ───────────────────────────────────────────────────

ifeq ($(OS),Windows_NT)
  PLATFORM  := windows
  EXE_EXT   := .exe
  CC        ?= gcc
  SHARED    := -shared
  LIBS      := -lm -lpthread
  DEFINES   := -D_GNU_SOURCE
else ifeq ($(shell uname -s),Darwin)
  PLATFORM  := macos
  EXE_EXT   :=
  CC        ?= clang
  SHARED    := -dynamiclib
  LIBS      := -lm -lpthread
  DEFINES   :=
else
  PLATFORM  := linux
  EXE_EXT   :=
  CC        ?= gcc
  SHARED    := -shared
  LIBS      := -lm -ldl -lpthread
  DEFINES   := -D_GNU_SOURCE
endif

# ── Paths & sources ──────────────────────────────────────────────────────
# QuickJS lives in the `quickjs_runtime` package (vendored there); the shared
# library is built inside that package's pub-cache checkout, where its FFI
# layer looks it up via .dart_tool/package_config.json.
QUICKJS_PKG   := $(shell python3 -c "import json;print([p['rootUri'] for p in json.load(open('.dart_tool/package_config.json'))['packages'] if p['name']=='quickjs_runtime'][0].replace('file://',''))" 2>/dev/null)
LIB_OUT       := $(QUICKJS_PKG)/native/quickjs/libquickjs_bridge.so
EXE_OUT       := dmtools$(EXE_EXT)

# Install layout (mirrors install.sh): the AOT binary goes to
# $(PREFIX)/bin and the QuickJS bridge lands in native/quickjs/ beside it —
# the exe-relative lookup path the runtime checks. Override with
# `make install PREFIX=/usr/local` (macOS) or any writable prefix.
PREFIX      ?= $(HOME)/.local
INSTALL_BIN := $(PREFIX)/bin

DART := dart

# ── Targets ──────────────────────────────────────────────────────────────

## deps: install Dart dependencies (dart pub get)
deps:
	$(DART) pub get

## native: compile the QuickJS bridge shared library (quickjs_runtime package)
native:
	@test -n "$(QUICKJS_PKG)" || (echo "run 'make deps' first"; exit 1)
	bash "$(QUICKJS_PKG)/tool/build_quickjs.sh"
	@echo "built $(LIB_OUT)"

## build: compile the standalone `dmtools` executable
build: deps native
	$(DART) compile exe bin/dmtools.dart -o $(EXE_OUT)
	@echo ""
	@echo "Built $(EXE_OUT) ($(PLATFORM))"
	@echo "Note: the executable needs libquickjs_bridge.so next to it,"
	@echo "or set JSR_QUICKJS_LIB to its absolute path."

## install: build and install the CLI into $(PREFIX)/bin (default ~/.local/bin)
install: build
ifeq ($(PLATFORM),windows)
	@echo "make install is not supported on Windows — use install.ps1 (follow-up)"
	@exit 1
else
	@mkdir -p "$(INSTALL_BIN)/native/quickjs"
	install -m 0755 $(EXE_OUT) "$(INSTALL_BIN)/dmtools$(EXE_EXT)"
	install -m 0644 $(LIB_OUT) "$(INSTALL_BIN)/native/quickjs/libquickjs_bridge.so"
	@echo "Installed: $(INSTALL_BIN)/dmtools$(EXE_EXT)"
	@echo "          $(INSTALL_BIN)/native/quickjs/libquickjs_bridge.so"
	@case ":$${PATH}:" in \
	  *":$(INSTALL_BIN):"*) ;; \
	  *) echo ""; \
	     echo "$(INSTALL_BIN) is not on your PATH — add it to your shell profile (~/.zshrc on macOS):"; \
	     echo "  export PATH=\"$(INSTALL_BIN):\$$PATH\"" ;; \
	esac
endif

## run: run from source (fast iteration, no AOT compile)
run: deps native
	$(DART) run bin/dmtools.dart

## test: run the unit + contract test suite
test: deps native
	$(DART) test

## test-cov: run tests and generate LCOV coverage report
test-cov: deps native
	$(DART) test --coverage=coverage
	$(DART) pub global run coverage:format_coverage \
	  --lcov --in coverage --out coverage/lcov.info --report-on lib

## analyze: static analysis
analyze:
	$(DART) analyze

## format: format all Dart code
format:
	$(DART) format .

## gates: full quality gate suite (format + analyze + test + crap4dart)
gates: format analyze test
	crap4dart check --all
	crap4dart analyze

## clean: remove all build artifacts
clean: clean-native clean-build

## clean-native: remove the compiled QuickJS library only
clean-native:
	rm -f $(LIB_OUT)
## clean-build: remove the compiled executable only
clean-build:
	rm -f $(EXE_OUT)

## help: show this help
help:
	@echo "dmtools-dart — build targets (platform: $(PLATFORM), cc: $(CC))"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ": "}; /^## /{sub(/^## /,""); printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
