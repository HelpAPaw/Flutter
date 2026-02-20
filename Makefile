CREDENTIALS_FILE := integration_test/test_credentials.json

.PHONY: test test-integration test-unit

## Run all tests
test: test-unit test-integration

## Run unit/widget tests
test-unit:
	flutter test

## Run integration tests (requires a device/emulator)
## Credentials are loaded automatically from $(CREDENTIALS_FILE)
## Copy integration_test/test_credentials.json.example to create it.
test-integration:
	@if [ ! -f "$(CREDENTIALS_FILE)" ]; then \
		echo "Missing $(CREDENTIALS_FILE). Copy the example and fill in your credentials:"; \
		echo "  cp integration_test/test_credentials.json.example integration_test/test_credentials.json"; \
		exit 1; \
	fi
	flutter test integration_test/ --dart-define-from-file=$(CREDENTIALS_FILE)
