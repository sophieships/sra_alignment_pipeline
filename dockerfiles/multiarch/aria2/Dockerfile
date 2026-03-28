FROM debian:bookworm-slim AS builder

ARG ARIA2_VERSION=1.37.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        libsqlite3-dev \
        libssh2-1-dev \
        libssl-dev \
        libxml2-dev \
        pkg-config \
        zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN curl -fsSL -o aria2.tar.gz "https://github.com/aria2/aria2/releases/download/release-${ARIA2_VERSION}/aria2-${ARIA2_VERSION}.tar.gz" && \
    tar -xzf aria2.tar.gz && \
    cd "aria2-${ARIA2_VERSION}" && \
    ./configure --prefix=/usr/local && \
    make -j"$(nproc)" && \
    make install-strip && \
    cd / && \
    rm -rf /tmp/*

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        libsqlite3-0 \
        libssh2-1 \
        libssl3 \
        libxml2 \
        zlib1g && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/aria2c /usr/local/bin/aria2c
COPY aria2_COPYING.txt /licenses/aria2/COPYING.txt
COPY sra_download.sh /scripts/sra_download.sh

RUN chmod +x /scripts/sra_download.sh

WORKDIR /data
