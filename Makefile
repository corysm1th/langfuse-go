.PHONY: generate release build test integration-test vet clean langfuse-spec help

LANGFUSE_REPO := https://github.com/langfuse/langfuse.git
LANGFUSE_SPEC := web/public/generated/api
LANGFUSE_VERSION = $(shell git -C langfuse tag 2>/dev/null | sort -V | tail -1)

help:
	@echo "Available targets:"
	@echo "  generate          - Generate Go SDK from OpenAPI spec"
	@echo "  release           - Generate, commit, and tag SDK with Langfuse version"
	@echo "  langfuse-spec     - Sparse-clone the OpenAPI spec from langfuse"
	@echo "  build             - Build the Go package"
	@echo "  test              - Run unit tests (excludes WireMock integration tests)"
	@echo "  integration-test  - Run all tests including WireMock integration tests"
	@echo "  vet               - Run go vet"
	@echo "  clean             - Remove generated Go files"

generate: langfuse-spec
	TMPDIR=/tmp FERN_NO_VERSION_REDIRECTION=true fern generate --local --runner podman

release: generate
	git add -A
	git commit -m "regenerate SDK for langfuse $(LANGFUSE_VERSION)"
	git tag $(LANGFUSE_VERSION)

langfuse-spec:
	@if [ ! -d langfuse/.git ]; then \
		git clone --filter=blob:none --no-checkout --depth=1 $(LANGFUSE_REPO) langfuse; \
		cd langfuse && git fetch --tags && git sparse-checkout set $(LANGFUSE_SPEC) && git checkout; \
	else \
		cd langfuse && git fetch --tags --depth=1 origin main && git checkout FETCH_HEAD; \
	fi

build:
	go build ./...

test:
	go test $$(go list ./... | grep -v '_test$$')

integration-test:
	podman compose -f wiremock/docker-compose.test.yml up -d
	@port=$$(podman compose -f wiremock/docker-compose.test.yml port wiremock 8080 | cut -d: -f2); \
	echo "Waiting for WireMock on port $$port..."; \
	until curl -sf http://localhost:$$port/__admin/health > /dev/null 2>&1; do sleep 2; done; \
	WIREMOCK_URL=http://localhost:$$port go test ./...; \
	result=$$?; \
	podman compose -f wiremock/docker-compose.test.yml down; \
	exit $$result

vet:
	go vet ./...

clean:
	find . -name "*.gen.go" -delete
	rm -f go.mod go.sum
