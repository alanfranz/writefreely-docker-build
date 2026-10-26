PODMAN              ?= podman
WRITEFREELY_VERSION ?= $(shell cat WRITEFREELY_VERSION)
IMAGE               ?= ghcr.io/alanfranz/writefreely
PLATFORM            ?= linux/amd64
SOURCE_URL          ?= https://github.com/alanfranz/writefreely-docker-build
# CI sets this to the workflow run number; local builds are tagged _dev.
BUILD_NUMBER        ?= dev

VERSION_TAG = $(WRITEFREELY_VERSION)_$(BUILD_NUMBER)
LOCAL_TAG   = $(IMAGE):$(VERSION_TAG)

.PHONY: build test push clean

build:
	$(PODMAN) build --pull=newer --platform $(PLATFORM) \
		--build-arg WRITEFREELY_VERSION=$(WRITEFREELY_VERSION) \
		--label org.opencontainers.image.title=writefreely \
		--label org.opencontainers.image.description="WriteFreely $(WRITEFREELY_VERSION), built from upstream sources" \
		--label org.opencontainers.image.version=$(VERSION_TAG) \
		--label org.opencontainers.image.source=$(SOURCE_URL) \
		--label org.opencontainers.image.licenses=AGPL-3.0-only \
		-t $(LOCAL_TAG) -f Containerfile .

test:
	PODMAN=$(PODMAN) scripts/smoke-test.sh $(LOCAL_TAG)

push:
	@echo '$(BUILD_NUMBER)' | grep -qE '^[0-9]+$$' || \
		{ echo "push needs a numeric BUILD_NUMBER (got '$(BUILD_NUMBER)')" >&2; exit 1; }
	PODMAN=$(PODMAN) scripts/push.sh $(LOCAL_TAG) $(IMAGE) $(VERSION_TAG)

clean:
	-$(PODMAN) rmi $(LOCAL_TAG)
