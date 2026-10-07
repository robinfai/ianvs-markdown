FLUTTER ?= flutter
DART ?= dart
FORMAT_DART ?= $(DART)
INSTALL_DIR ?= /Applications
PYTHON ?= python3

CORE_DART = lib test example/lib example/test tool/package_smoke_test.dart benchmark
INTEGRATION_DART = app/lib app/test packages/ianvs_mermaid/lib packages/ianvs_mermaid/hook packages/ianvs_mermaid/test packages/ianvs_mermaid/example/lib packages/ianvs_mermaid/example/test

.DEFAULT_GOAL := help
# Flutter resolves dependencies and writes generated files in each package.
.NOTPARALLEL:

.PHONY: help deps deps-core deps-integrations format format-check format-check-core format-check-integrations analyze analyze-core analyze-integrations test test-example test-app test-mermaid test-mermaid-example test-quicklook check check-core check-integrations check-package benchmark run example run-app install clean publish-dry-run

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: deps-core deps-integrations ## Install all repository dependencies

deps-core: ## Install core package and minimal example dependencies
	$(FLUTTER) pub get

deps-integrations: ## Install app and optional Mermaid dependencies
	cd packages/ianvs_mermaid && $(FLUTTER) pub get
	cd app && $(FLUTTER) pub get

format: ## Format Dart source and test files
	$(FORMAT_DART) format $(CORE_DART) $(INTEGRATION_DART)

format-check: format-check-core format-check-integrations ## Check all Dart formatting

format-check-core: ## Check core package and minimal example formatting
	$(FORMAT_DART) format --output=none --set-exit-if-changed $(CORE_DART)

format-check-integrations: ## Check host and native adapter formatting
	$(FORMAT_DART) format --output=none --set-exit-if-changed $(INTEGRATION_DART)

analyze: analyze-core analyze-integrations ## Analyze all packages

analyze-core: ## Analyze only core and minimal example code
	$(FLUTTER) analyze lib test tool/package_smoke_test.dart benchmark
	cd example && $(FLUTTER) analyze

analyze-integrations: ## Analyze the app and optional Mermaid integration
	cd app && $(FLUTTER) analyze
	cd packages/ianvs_mermaid && $(FLUTTER) analyze
	cd packages/ianvs_mermaid/example && $(FLUTTER) analyze

test: ## Run package tests
	$(FLUTTER) test

test-example: ## Run example application tests
	cd example && $(FLUTTER) test

test-app: ## Run desktop application tests
	cd app && $(FLUTTER) test

test-mermaid: ## Run the macOS native Mermaid bridge and visual regressions
	cargo test --locked --manifest-path packages/ianvs_mermaid/rust/Cargo.toml
	cd packages/ianvs_mermaid && $(FLUTTER) test

test-mermaid-example: ## Run the optional native integration example tests
	cd packages/ianvs_mermaid/example && $(FLUTTER) test

test-quicklook: deps-integrations ## Test the native macOS Quick Look renderer and file loading
	cargo fmt --check --manifest-path app/macos/QuickLook/renderer/Cargo.toml
	bash app/tool/test_native_quicklook.sh

check-core: deps-core format-check-core analyze-core test test-example ## Validate core without Apple or Mermaid integration checks

check-integrations: deps-integrations format-check-integrations analyze-integrations test-app test-mermaid test-mermaid-example test-quicklook ## Validate the app and native integrations (macOS)

check-package: ## Test the actual Pub snapshot in an external Flutter host
	$(PYTHON) tool/check_package.py --flutter "$(FLUTTER)" --dart "$(DART)"

benchmark: ## Run the macOS profile benchmark (pass LABEL=before or after)
	$(PYTHON) tool/run_benchmark.py --flutter "$(FLUTTER)" --label "$(or $(LABEL),local)" $(BENCHMARK_ARGS)

check: check-core check-integrations check-package ## Run all validation checks

run: ## Run the desktop app on macOS (make run example for the example)
	cd $(if $(filter example,$(MAKECMDGOALS)),example,app) && $(FLUTTER) run -d macos

# Accept example as a selector for make run.
example:
	@:

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
