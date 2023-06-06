import requests
from bs4 import BeautifulSoup
import time
import sys
import csv
import os

def get_search_url(accession_number):
    return f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=sra&term={accession_number}"

def get_fetch_url(id):
    return f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=sra&id={id}"

def send_API_request(url):
    return requests.get(url)

def parse_XML_response(response):
    return BeautifulSoup(response.content, features='xml')

def extract_ids(soup):
    return [id.text for id in soup.find_all('Id')]

def extract_srr_accessions(fetch_soup):
    return [run['accession'] for run in fetch_soup.find_all('RUN')]

def process_srr_accessions(srr_accessions, identifier):
    for srr_accession in srr_accessions:
        print(srr_accession + "," + identifier, flush=True)

# Check if sys.argv[1] is a CSV file
if len(sys.argv) == 2 and ".csv" in sys.argv[1]:
    with open(sys.argv[1], 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            accession_number, identifier = row[0], row[1]

            # Perform the search
            search_url = get_search_url(accession_number)
            search_response = send_API_request(search_url)
            time.sleep(1/3)
            search_soup = parse_XML_response(search_response)
            ids = extract_ids(search_soup)

            # Process each Id
            for id in ids:
                # Fetch data
                fetch_url = get_fetch_url(id)
                time.sleep(1/3)
                fetch_response = send_API_request(fetch_url)
                fetch_soup = parse_XML_response(fetch_response)

                # Extract and process SRR accession numbers
                srr_accessions = extract_srr_accessions(fetch_soup)
                process_srr_accessions(srr_accessions, identifier)
else:
    accession_number = sys.argv[1]
    if len(sys.argv) > 2:
        identifier = sys.argv[2]
    else:
        identifier = None   

    # Perform the search
    search_url = get_search_url(accession_number)
    time.sleep(1/3)
    search_response = send_API_request(search_url)
    search_soup = parse_XML_response(search_response)
    ids = extract_ids(search_soup)

    # Process each Id
    for id in ids:
        # Fetch data
        fetch_url = get_fetch_url(id)
        time.sleep(1/3)
        fetch_response = send_API_request(fetch_url)
        fetch_soup = parse_XML_response(fetch_response)

        # Extract and process SRR accession numbers
        srr_accessions = extract_srr_accessions(fetch_soup)
        process_srr_accessions(srr_accessions, identifier)
