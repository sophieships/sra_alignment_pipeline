FROM python:3.9-slim-buster

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

RUN pip install requests==2.26.0 beautifulsoup4==4.12.2 lxml==4.6.3 html5lib

COPY sra_parser.py /scripts/sra_parser.py

RUN chmod +x /scripts/sra_parser.py

WORKDIR /data

CMD ["/bin/bash"]
