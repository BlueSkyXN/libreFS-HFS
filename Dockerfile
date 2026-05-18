# syntax=docker/dockerfile:1.6

ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS builder

ARG TARGETARCH=amd64
ARG GO_VERSION=1.26.3
ARG LIBREFS_REF=main
ARG LIBREFS_COMMIT=HEAD

ENV GOROOT=/usr/local/go
ENV GOPATH=/root/go
ENV PATH=/usr/local/go/bin:/root/go/bin:$PATH
ENV CGO_ENABLED=0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="${TARGETARCH:-amd64}"; \
    case "$arch" in \
      amd64|arm64) go_arch="$arch" ;; \
      *) echo "Unsupported TARGETARCH: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm -f /tmp/go.tgz; \
    go version

WORKDIR /src

RUN git init . \
    && git remote add origin https://github.com/libreFS/libreFS.git \
    && git fetch --depth 1 origin "${LIBREFS_REF}" \
    && git checkout --detach FETCH_HEAD \
    && if [ "${LIBREFS_COMMIT}" != "HEAD" ]; then test "$(git rev-parse HEAD)" = "${LIBREFS_COMMIT}"; fi

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/go/pkg/mod \
    go build -trimpath -buildvcs=false -ldflags="-s -w" -o /out/librefs .

FROM ubuntu:${UBUNTU_VERSION}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        nginx \
        tini \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1000 user \
    && mkdir -p \
        /data \
        /tmp/nginx/client_body \
        /tmp/nginx/proxy \
        /tmp/nginx/fastcgi \
        /tmp/nginx/uwsgi \
        /tmp/nginx/scgi \
    && chown -R user:user /data /tmp/nginx

COPY --from=builder --chmod=0755 /out/librefs /usr/local/bin/librefs
COPY --chmod=0644 nginx.conf /etc/nginx/nginx.conf
COPY --chmod=0755 start.sh /start.sh

ENV HOME=/home/user

USER user

EXPOSE 7860

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:7860/minio/health/ready || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/start.sh"]
