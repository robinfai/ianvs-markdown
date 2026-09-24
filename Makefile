FLUTTER ?= flutter
DART ?= dart
INSTALL_DIR ?= /Applications

.DEFAULT_GOAL := help

.PHONY: help deps format format-check analyze test test-example test-app check run example run-app install clean publish-dry-run

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target>\n\nTargets:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Install package, example, and app dependencies
	$(FLUTTER) pub get
	cd example && $(FLUTTER) pub get
	cd app && $(FLUTTER) pub get

format: ## Format Dart source and test files
	$(DART) format lib test example/lib example/test app/lib app/test

format-check: ## Check Dart formatting without changing files
	$(DART) format --output=none --set-exit-if-changed lib test example/lib example/test app/lib app/test

analyze: ## Run static analysis for the package and example
	$(FLUTTER) analyze
	cd example && $(FLUTTER) analyze
	cd app && $(FLUTTER) analyze

test: ## Run package tests
	$(FLUTTER) test

test-example: ## Run example application tests
	cd example && $(FLUTTER) test

test-app: ## Run desktop application tests
	cd app && $(FLUTTER) test

check: format-check analyze test test-example test-app ## Run all validation checks

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

publish-dry-run: check ## Validate the package without publishing it
	$(DART) pub publish --dry-run
