#!/usr/bin/env python3
"""Resolve SRA/experiment accessions to SRR run accessions via NCBI E-utilities.

Queries the NCBI SRA database with esearch, then efetch, and extracts the RUN
accessions from the returned XML. Emits ``<srr_accession>,<identifier>`` lines,
one per run, matching the CSV format the pipeline's downstream steps consume.

Uses only ``requests`` plus the Python standard library so it runs under the
stock ``quay.io/biocontainers/requests`` image (no custom scraper container).
Nextflow stages this file onto the task PATH from the pipeline's top-level
``bin/`` directory, so the process invokes it as ``sra_parser.py`` directly.
"""

import csv
import sys
import time
import xml.etree.ElementTree as ET

import requests


def get_search_url(accession_number):
    return f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term={accession_number}"


def get_fetch_url(id):
    return f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&id={id}"


def send_API_request(url):
    return requests.get(url)


def parse_XML_response(response):
    return ET.fromstring(response.content)


def extract_ids(root):
    return [element.text for element in root.iter('Id') if element.text]


def extract_srr_accessions(fetch_root):
    return [
        run.get('accession')
        for run in fetch_root.iter('RUN')
        if run.get('accession')
    ]


def process_srr_accessions(srr_accessions, identifier):
    for srr_accession in srr_accessions:
        print(srr_accession + "," + identifier, flush=True)


def resolve_accession(accession_number, identifier):
    search_url = get_search_url(accession_number)
    search_response = send_API_request(search_url)
    time.sleep(1 / 3)
    search_root = parse_XML_response(search_response)
    ids = extract_ids(search_root)

    for id in ids:
        fetch_url = get_fetch_url(id)
        time.sleep(1 / 3)
        fetch_response = send_API_request(fetch_url)
        fetch_root = parse_XML_response(fetch_response)
        srr_accessions = extract_srr_accessions(fetch_root)
        process_srr_accessions(srr_accessions, identifier)


# Check if sys.argv[1] is a CSV file
if len(sys.argv) == 2 and ".csv" in sys.argv[1]:
    with open(sys.argv[1], 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            accession_number, identifier = row[0], row[1]
            resolve_accession(accession_number, identifier)
else:
    accession_number = sys.argv[1]
    if len(sys.argv) > 2:
        identifier = sys.argv[2]
    else:
        identifier = None
    resolve_accession(accession_number, identifier)
