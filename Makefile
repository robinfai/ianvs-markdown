FLUTTER ?= flutter
DART ?= dart

.DEFAULT_GOAL := help

.PHONY: help deps format format-check analyze test test-example test-app check run run-app clean publish-dry-run

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

run: ## Run the example application on macOS
	cd example && $(FLUTTER) run -d macos

run-app: ## Run the full desktop application on macOS
	cd app && $(FLUTTER) run -d macos

clean: ## Remove generated build artifacts
	$(FLUTTER) clean
	cd example && $(FLUTTER) clean
	cd app && $(FLUTTER) clean

publish-dry-run: check ## Validate the package without publishing it
	$(DART) pub publish --dry-run
