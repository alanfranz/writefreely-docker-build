# Builds WriteFreely from an upstream release tag on current Go/Alpine.
# Filesystem layout matches the upstream image (WORKDIR /go, config at
# /go/config.ini, keys in /go/keys) so upstream docs and compose files apply.

ARG GO_VERSION=1.27
ARG ALPINE_VERSION=3.24

FROM docker.io/library/golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS build

ARG WRITEFREELY_VERSION
RUN test -n "${WRITEFREELY_VERSION}" || { echo "WRITEFREELY_VERSION build arg is required" >&2; exit 1; }

RUN apk add --no-cache git make g++ nodejs npm \
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
    && CGO_ENABLED=1 go build -trimpath -tags 'netgo sqlite' \
      -ldflags "-s -w -X 'github.com/writefreely/writefreely.softwareVer=${WRITEFREELY_VERSION}' -extldflags '-static'" \
      -o /stage/cmd/writefreely/writefreely . \
    && cp -R /src/templates /src/static /src/pages /stage/ \
    && mkdir /stage/keys


FROM docker.io/library/alpine:${ALPINE_VERSION}

RUN apk add --no-cache ca-certificates openssl tzdata \
    && ln -s /go/cmd/writefreely/writefreely /usr/local/bin/writefreely

COPY --from=build --chown=daemon:daemon /stage /go

WORKDIR /go
VOLUME /go/keys
EXPOSE 8080
USER daemon

ENTRYPOINT ["/go/cmd/writefreely/writefreely"]
