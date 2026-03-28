FROM ubuntu:24.04

ARG BOWTIE2_VERSION=2.5.5
ARG TARGETARCH

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        perl \
        procps \
        python3 \
        unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp

RUN case "${TARGETARCH}" in \
        amd64) bowtie_arch="x86_64" ;; \
        arm64) bowtie_arch="aarch64" ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o bowtie2.zip "https://github.com/BenLangmead/bowtie2/releases/download/v${BOWTIE2_VERSION}/bowtie2-${BOWTIE2_VERSION}-linux-${bowtie_arch}.zip" && \
    unzip bowtie2.zip && \
    rm bowtie2.zip && \
    mv "bowtie2-${BOWTIE2_VERSION}-linux-${bowtie_arch}" /opt/bowtie2 && \
    rm -rf /tmp/*

ENV PATH="/opt/bowtie2:${PATH}"
WORKDIR /data
