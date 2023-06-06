FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential \
    aria2=1.35.0-3 && rm -rf /var/lib/apt/lists/*


COPY sra_download.sh /scripts/sra_download.sh

# Make the shell script executable
RUN chmod +x /scripts/sra_download.sh

WORKDIR /data

