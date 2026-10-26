# Builds WriteFreely from an upstream release tag on current Go/Alpine.
# Filesystem layout matches the upstream image (WORKDIR /go, config at
# /go/config.ini, keys in /go/keys) so upstream docs and compose files apply.
#
# The final image is FROM scratch: a static binary, its assets, CA certs,
# a writable /tmp and a static busybox (only for /bin/sh and wget, so
# healthchecks can run), all in a single layer.

# GO_VERSION and ALPINE_VERSION pick the base image tag; they are floating
# tags (and `make build` pulls with --pull=newer), so the newest patch
# releases get used. The *_MIN_VERSION args are the oldest patch releases
# that are acceptable: the build fails if the base image is older.
ARG GO_VERSION=1.27
ARG GO_MIN_VERSION=1.27.3
ARG ALPINE_VERSION=3.24
ARG ALPINE_MIN_VERSION=3.24.3

FROM docker.io/library/golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS build

ARG GO_MIN_VERSION
ARG ALPINE_MIN_VERSION
# apk version -t prints <, = or > comparing its two arguments.
RUN set -e; \
    go=$(go env GOVERSION); go=${go#go}; \
    alpine=$(cat /etc/alpine-release); \
    echo "Go ${go} (minimum ${GO_MIN_VERSION}), Alpine ${alpine} (minimum ${ALPINE_MIN_VERSION})"; \
    [ "$(apk version -t "${go}" "${GO_MIN_VERSION}")" != "<" ] \
      || { echo "Go ${go} is older than GO_MIN_VERSION ${GO_MIN_VERSION}" >&2; exit 1; }; \
    [ "$(apk version -t "${alpine}" "${ALPINE_MIN_VERSION}")" != "<" ] \
      || { echo "Alpine ${alpine} is older than ALPINE_MIN_VERSION ${ALPINE_MIN_VERSION}" >&2; exit 1; }

ARG WRITEFREELY_VERSION
RUN test -n "${WRITEFREELY_VERSION}" || { echo "WRITEFREELY_VERSION build arg is required" >&2; exit 1; }

RUN apk add --no-cache git make g++ nodejs npm busybox-static \
    && npm install -g less less-plugin-clean-css

RUN git clone --depth 1 --branch "v${WRITEFREELY_VERSION}" \
      https://github.com/writefreely/writefreely.git /src

WORKDIR /src

# Stylesheets and the prose editor bundle. The editor still uses webpack 4,
# which needs OpenSSL's legacy provider (md4).
RUN make -C less \
    && cd prose \
    && npm ci --no-audit --no-fund \
    && OPENSSL_CONF=/src/ossl_legacy.cnf npm run-script build

RUN cd cmd/writefreely \
    && CGO_ENABLED=1 go build -trimpath -buildvcs=false -tags 'netgo osusergo sqlite' \
      -ldflags "-s -w -X 'github.com/writefreely/writefreely.softwareVer=${WRITEFREELY_VERSION}' -extldflags '-static'" \
      -o /rootfs/go/cmd/writefreely/writefreely .

# Assemble the final filesystem. Only runtime assets are copied: no sources,
# no dotfiles.
RUN set -e; \
    cp -R /src/templates /src/static /src/pages /rootfs/go/; \
    find /rootfs/go -name '.*' -type f -delete; \
    mkdir -p /rootfs/go/static/local /rootfs/go/keys \
      /rootfs/etc/ssl/certs /rootfs/usr/local/bin /rootfs/bin /rootfs/tmp; \
    chmod 1777 /rootfs/tmp; \
    cp /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/; \
    ln -s /go/cmd/writefreely/writefreely /rootfs/usr/local/bin/writefreely; \
    cp /bin/busybox.static /rootfs/bin/busybox; \
    ln -s busybox /rootfs/bin/sh; \
    ln -s busybox /rootfs/bin/wget; \
    printf 'root:x:0:0:root:/root:/sbin/nologin\ndaemon:x:2:2:daemon:/go:/sbin/nologin\n' >/rootfs/etc/passwd; \
    printf 'root:x:0:\ndaemon:x:2:\n' >/rootfs/etc/group; \
    chown -R 2:2 /rootfs/go


FROM scratch

COPY --from=build /rootfs /

ENV PATH=/usr/local/bin:/bin \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
WORKDIR /go
VOLUME /go/keys
EXPOSE 8080
USER 2:2

ENTRYPOINT ["/go/cmd/writefreely/writefreely"]
