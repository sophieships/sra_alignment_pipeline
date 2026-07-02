#!/usr/bin/env python3
"""Download a reference sequence from NCBI and bgzip-compress it.

Fetches a nucleotide record from NCBI Entrez by identifier, writes it as FASTA,
then bgzip-compresses it with pysam so downstream `samtools faidx` /
`bcftools consensus` can index and read it. Runs under the stock biopython+pysam
mulled biocontainer; Nextflow stages this file onto the task PATH from the
pipeline's top-level bin/ directory, so download_fasta invokes it directly.
"""

from Bio import Entrez, SeqIO
import pysam
import time

def download_fasta(identifier, email):
    Entrez.email = email
    time.sleep(3)
    handle = Entrez.efetch(db='nucleotide', id=identifier, rettype='fasta', retmode='text')
    record = SeqIO.read(handle, 'fasta')
    handle.close()
    filename = f"{identifier}_reference.fasta"
    SeqIO.write(record, filename, 'fasta')

    # Compress the fasta file with bgzip
    pysam.tabix_compress(filename, filename + '.gz', force=True)

    return filename

if __name__ == "__main__":
    import sys
    download_fasta(sys.argv[1], sys.argv[2])
