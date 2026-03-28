FROM ubuntu:24.04

ARG QUALIMAP_VERSION=2.3
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        fontconfig \
        libcairo2 \
        libjpeg-turbo8 \
        libpng16-16 \
        libxt6 \
        openjdk-17-jre-headless \
        procps \
        r-base-core \
        unzip \
        x11-common && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o qualimap.zip "https://bitbucket.org/kokonech/qualimap/downloads/qualimap_v${QUALIMAP_VERSION}.zip" && \
    unzip qualimap.zip && \
    rm qualimap.zip && \
    mv "qualimap_v${QUALIMAP_VERSION}" /opt/qualimap && \
    sed -i 's/ -XX:MaxPermSize=1024m//g' /opt/qualimap/qualimap /opt/qualimap/qualimap_bash_fix

ENV PATH="/opt/qualimap:${PATH}"
WORKDIR /data
