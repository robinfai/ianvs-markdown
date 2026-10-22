FLUTTER ?= flutter
DART ?= dart
FORMAT_DART ?= $(DART)
INSTALL_DIR ?= /Applications
PYTHON ?= python3

CORE_DART = lib test example/lib example/test tool/package_smoke_test.dart benchmark
API_CHECK_DART = tool/api_check/lib tool/api_check/bin tool/api_check/test
INTEGRATION_DART = app/lib app/test packages/ianvs_mermaid/lib packages/ianvs_mermaid/hook packages/ianvs_mermaid/test packages/ianvs_mermaid/example/lib packages/ianvs_mermaid/example/test packages/ianvs_markdown_clipboard/lib packages/ianvs_markdown_clipboard/test

.DEFAULT_GOAL := help
# Flutter resolves dependencies and writes generated files in each package.
.NOTPARALLEL:

.PHONY: help deps deps-core deps-integrations format format-check format-check-core format-check-integrations analyze analyze-core analyze-integrations test test-example test-app test-mermaid test-mermaid-example test-quicklook test-native-import test-native-guarded-save test-native-sync-metadata test-native-attachments test-ios-preview build-ios-preview build-examples run-ios check check-local build-local build-local-release run-example check-core check-integrations check-package check-api check-processing-budget test-clipboard benchmark run example run-app install clean publish-dry-run

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: deps-core deps-integrations ## Install all repository dependencies

deps-core: ## Install core package and minimal example dependencies
	$(FLUTTER) pub get

deps-integrations: ## Install app and optional native adapter dependencies
	cd packages/ianvs_mermaid && $(FLUTTER) pub get
	cd packages/ianvs_markdown_clipboard && $(FLUTTER) pub get
	cd app && $(FLUTTER) pub get

format: ## Format Dart source and test files
	$(FORMAT_DART) format $(CORE_DART) $(INTEGRATION_DART) $(API_CHECK_DART)

format-check: format-check-core format-check-integrations ## Check all Dart formatting

format-check-core: ## Check core package and minimal example formatting
	$(FORMAT_DART) format --output=none --set-exit-if-changed $(CORE_DART)

format-check-integrations: ## Check host and native adapter formatting
	$(FORMAT_DART) format --output=none --set-exit-if-changed $(INTEGRATION_DART)

analyze: analyze-core analyze-integrations ## Analyze all packages

analyze-core: ## Analyze only core and minimal example code
	$(FLUTTER) analyze lib test tool/package_smoke_test.dart benchmark
	cd example && $(FLUTTER) analyze

analyze-integrations: ## Analyze the app and optional native integrations
	cd app && $(FLUTTER) analyze
	cd packages/ianvs_mermaid && $(FLUTTER) analyze
	cd packages/ianvs_mermaid/example && $(FLUTTER) analyze
	cd packages/ianvs_markdown_clipboard && $(FLUTTER) analyze

test: ## Run package tests
	$(FLUTTER) test

test-example: ## Run example application tests
	cd example && $(FLUTTER) test

.PHONY: test-clipboard
test-clipboard: ## Run the optional native clipboard adapter contracts
	cd packages/ianvs_markdown_clipboard && $(FLUTTER) test

test-app: ## Run desktop application tests
	cd app && $(FLUTTER) test

test-native-import: ## Verify native Markdown file import handling
	bash app/tool/test_native_markdown_import.sh

test-native-guarded-save: ## Verify coordinated native conflict-safe saves
	FLUTTER="$(FLUTTER)" PYTHON="$(PYTHON)" bash app/tool/test_native_guarded_save.sh

test-native-sync-metadata: ## Verify read-only native document sync metadata
	FLUTTER="$(FLUTTER)" PYTHON="$(PYTHON)" bash app/tool/test_native_sync_metadata.sh

test-native-attachments: ## Verify scoped native attachment indexing and binary reads
	FLUTTER="$(FLUTTER)" PYTHON="$(PYTHON)" bash app/tool/test_native_attachments.sh

test-ios-preview: test-native-import ## Check iOS reading, import handling, and native file copying
	cd app && $(FLUTTER) test test/preview_app_test.dart test/preview_library_test.dart test/preview_platform_test.dart

build-ios-preview: ## Build the iOS reading preview for the simulator
	cd app && $(FLUTTER) build ios --simulator --debug --no-codesign

build-local: deps ## Build the two local application entries for macOS Debug
	cd example && $(FLUTTER) build macos --debug --target lib/main.dart
	cd app && FLUTTER_XCODE_ARCHS="$$(uname -m)" CARGO_PROFILE_RELEASE_STRIP=none $(FLUTTER) build macos --debug --target lib/main.dart

build-local-release: deps ## Build the same example and app entries for macOS Release
	cd example && $(FLUTTER) build macos --release --target lib/main.dart
	cd app && FLUTTER_XCODE_ARCHS="$$(uname -m)" CARGO_PROFILE_RELEASE_STRIP=none $(FLUTTER) build macos --release --target lib/main.dart

build-examples: ## Optional diagnostic builds for individual component examples
	cd example && $(FLUTTER) build macos --debug --target lib/body.dart
	cd example && $(FLUTTER) build macos --debug --target lib/reading.dart
	cd example && $(FLUTTER) build macos --debug --target lib/editor.dart
	cd example && $(FLUTTER) build macos --debug --target lib/streaming.dart
	cd example && $(FLUTTER) build macos --debug --target lib/main.dart

run-ios: ## Run on an iOS device or simulator (pass DEVICE=<device id>)
	cd app && $(FLUTTER) run $(if $(DEVICE),-d $(DEVICE),)

test-mermaid: ## Run the macOS native Mermaid bridge and visual regressions
	cargo test --locked --manifest-path packages/ianvs_mermaid/rust/Cargo.toml
	cd packages/ianvs_mermaid && $(FLUTTER) test

test-mermaid-example: ## Run the optional native integration example tests
	cd packages/ianvs_mermaid/example && $(FLUTTER) test

test-quicklook: deps-integrations ## Test the native macOS Quick Look renderer and file loading
	cargo fmt --check --manifest-path app/macos/QuickLook/renderer/Cargo.toml
	bash app/tool/test_native_quicklook.sh

check-processing-budget: ## Check large-input preprocessing in killable processes
	$(PYTHON) tool/check_processing_budget.py --flutter "$(FLUTTER)" --output build/processing-budget

.PHONY: test-tools
test-tools: ## Validate performance evidence checks
	$(PYTHON) -m unittest discover -s tool -p 'test_*.py'

check-api: deps-core ## Validate the public API baseline and its checker
	cd tool/api_check && $(DART) pub get --enforce-lockfile
	$(FORMAT_DART) format --output=none --set-exit-if-changed $(API_CHECK_DART)
	cd tool/api_check && $(DART) analyze
	cd tool/api_check && $(DART) test
	cd tool/api_check && $(DART) run bin/check.dart --check ../..

check-core: check-api format-check-core analyze-core test test-example test-tools check-processing-budget ## Validate core without Apple or Mermaid integration checks

check-integrations: test-native-note-transactions test-native-guarded-save test-native-sync-metadata test-native-attachments deps-integrations format-check-integrations analyze-integrations test-app test-mermaid test-mermaid-example test-clipboard test-quicklook test-native-import ## Validate the app and native integrations (macOS)

check-package: ## Test the actual Pub snapshot in an external Flutter host
	$(PYTHON) tool/check_package.py --flutter "$(FLUTTER)" --dart "$(DART)"

.PHONY: build-local-performance
build-local-performance: ## Build and freeze opt-in performance diagnostics in both actual mains
	$(PYTHON) tool/local_performance.py build --flutter "$(FLUTTER)" --mode "$(or $(MODE),profile)" --tag "$(or $(LABEL),main-profile)"

benchmark: ## Run the macOS profile benchmark (pass LABEL=before or after)
	$(PYTHON) tool/run_benchmark.py --flutter "$(FLUTTER)" --label "$(or $(LABEL),local)" $(BENCHMARK_ARGS)

check-local: check-core check-integrations build-local ## Validate local example/app iteration without external-host acceptance

check: check-core check-integrations check-package ## Run all validation checks

run: ## Run the desktop app on macOS (make run example for the example)
	cd $(if $(filter example,$(MAKECMDGOALS)),example,app) && $(FLUTTER) run -d macos

# Accept example as a selector for make run.
example:
	@:

run-example: ## Run the default example application on macOS
	cd example && $(FLUTTER) run -d macos --target lib/main.dart

run-app: ## Run the full desktop application on macOS
	cd app && $(FLUTTER) run -d macos

install: ## Build Linefold for macOS and install it (INSTALL_DIR=/Applications)
	# Build for this Mac; preserve Rust proc-macro alignment on macOS 27.
	cd app && FLUTTER_XCODE_ARCHS="$$(uname -m)" \
		CARGO_PROFILE_RELEASE_STRIP=none $(FLUTTER) build macos --release
	bash app/tool/install_macos_app.sh "$(INSTALL_DIR)"

clean: ## Remove generated build artifacts
	$(FLUTTER) clean
	cd example && $(FLUTTER) clean
	cd app && $(FLUTTER) clean

publish-dry-run: check-core check-package ## Validate core and publication without publishing
	$(DART) pub publish --dry-run

.PHONY: test-native-note-transactions
test-native-note-transactions: ## Verify recoverable native note move transactions using synthetic fixtures
	FLUTTER="$(FLUTTER)" PYTHON="$(PYTHON)" bash app/tool/test_native_note_transactions.sh
