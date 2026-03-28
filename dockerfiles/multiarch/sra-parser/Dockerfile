ARG PYTHON_IMAGE=python:3.13-slim-bookworm
FROM ${PYTHON_IMAGE}

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential procps && \
    rm -rf /var/lib/apt/lists/*

ARG REQUESTS_VERSION=2.32.3
ARG BEAUTIFULSOUP4_VERSION=4.12.3
ARG LXML_VERSION=5.3.0
ARG HTML5LIB_VERSION=1.1

RUN pip install --no-cache-dir \
    "requests==${REQUESTS_VERSION}" \
    "beautifulsoup4==${BEAUTIFULSOUP4_VERSION}" \
    "lxml==${LXML_VERSION}" \
    "html5lib==${HTML5LIB_VERSION}"

COPY sra_parser.py /scripts/sra_parser.py

RUN chmod +x /scripts/sra_parser.py

WORKDIR /data

CMD ["/bin/bash"]
