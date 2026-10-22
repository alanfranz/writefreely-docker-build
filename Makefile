PODMAN              ?= podman
WRITEFREELY_VERSION ?= $(shell cat WRITEFREELY_VERSION)
IMAGE               ?= ghcr.io/alanfranz/writefreely
PLATFORM            ?= linux/amd64
SOURCE_URL          ?= https://github.com/alanfranz/writefreely-docker-build
TAGS                ?= $(WRITEFREELY_VERSION) latest

LOCAL_TAG = $(IMAGE):$(WRITEFREELY_VERSION)

.PHONY: build test push clean

build:
	$(PODMAN) build --pull=newer --platform $(PLATFORM) \
		--build-arg WRITEFREELY_VERSION=$(WRITEFREELY_VERSION) \
		--label org.opencontainers.image.title=writefreely \
		--label org.opencontainers.image.description="WriteFreely $(WRITEFREELY_VERSION), built from upstream sources" \
		--label org.opencontainers.image.version=$(WRITEFREELY_VERSION) \
		--label org.opencontainers.image.source=$(SOURCE_URL) \
		--label org.opencontainers.image.licenses=AGPL-3.0-only \
		-t $(LOCAL_TAG) -f Containerfile .

test:
	PODMAN=$(PODMAN) scripts/smoke-test.sh $(LOCAL_TAG)

push:
	for t in $(TAGS); do \
		$(PODMAN) push $(LOCAL_TAG) docker://$(IMAGE):$$t || exit 1; \
	done

clean:
	-$(PODMAN) rmi $(LOCAL_TAG)
