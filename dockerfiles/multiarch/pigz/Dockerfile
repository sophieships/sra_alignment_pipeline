FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG PIGZ_VERSION=2.8-1

RUN apt-get update && \
    apt-get install -y --no-install-recommends "pigz=${PIGZ_VERSION}" procps && \
    rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
