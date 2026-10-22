PODMAN              ?= podman
WRITEFREELY_VERSION ?= $(shell cat WRITEFREELY_VERSION)
IMAGE               ?= ghcr.io/alanfranz/writefreely
ARCH                ?= $(shell $(PODMAN) info --format '{{.Host.Arch}}')
SOURCE_URL          ?= https://github.com/alanfranz/writefreely-docker-build
ARCHIVE_DIR         ?= dist
ARCHES              ?= amd64 arm64
TAGS                ?= $(WRITEFREELY_VERSION) latest

LOCAL_TAG = $(IMAGE):$(WRITEFREELY_VERSION)-$(ARCH)
MANIFEST  = $(IMAGE):$(WRITEFREELY_VERSION)

.PHONY: build test save manifest push clean

# Build for a single architecture (the host's by default).
build:
	$(PODMAN) build --pull=newer --platform linux/$(ARCH) \
		--build-arg WRITEFREELY_VERSION=$(WRITEFREELY_VERSION) \
		--label org.opencontainers.image.title=writefreely \
		--label org.opencontainers.image.description="WriteFreely $(WRITEFREELY_VERSION), built from upstream sources" \
		--label org.opencontainers.image.version=$(WRITEFREELY_VERSION) \
		--label org.opencontainers.image.source=$(SOURCE_URL) \
		--label org.opencontainers.image.licenses=AGPL-3.0-only \
		-t $(LOCAL_TAG) -f Containerfile .

test:
	PODMAN=$(PODMAN) scripts/smoke-test.sh $(LOCAL_TAG)

# Export the single-arch image so another machine/job can assemble the manifest.
save:
	mkdir -p $(ARCHIVE_DIR)
	rm -f $(ARCHIVE_DIR)/writefreely-$(ARCH).tar
	$(PODMAN) save --format oci-archive -o $(ARCHIVE_DIR)/writefreely-$(ARCH).tar $(LOCAL_TAG)

# Assemble a multi-arch manifest list from the archives in $(ARCHIVE_DIR).
manifest:
	-$(PODMAN) manifest rm $(MANIFEST)
	$(PODMAN) manifest create $(MANIFEST)
	for a in $(ARCHES); do \
		$(PODMAN) manifest add $(MANIFEST) oci-archive:$(ARCHIVE_DIR)/writefreely-$$a.tar || exit 1; \
	done
	$(PODMAN) manifest inspect $(MANIFEST)

push:
	for t in $(TAGS); do \
		$(PODMAN) manifest push --all $(MANIFEST) docker://$(IMAGE):$$t || exit 1; \
	done

clean:
	rm -rf $(ARCHIVE_DIR)
	-$(PODMAN) manifest rm $(MANIFEST)
	-$(PODMAN) rmi $(LOCAL_TAG)
