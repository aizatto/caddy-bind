# syntax=docker/dockerfile:1
ARG VERSION=2.8.4

FROM --platform=$BUILDPLATFORM caddy:${VERSION}-builder AS builder
ARG VERSION
ARG TARGETOS
ARG TARGETARCH

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg \
    GOOS=$TARGETOS GOARCH=$TARGETARCH \
    xcaddy build \
    v${VERSION} \
    --with github.com/mholt/caddy-dynamicdns \
    --with github.com/caddy-dns/rfc2136

FROM caddy:${VERSION}

COPY --from=builder /usr/bin/caddy /usr/bin/caddy