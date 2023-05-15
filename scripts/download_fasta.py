import sys
from Bio import Entrez, SeqIO

identifier = sys.argv[1]

handle = Entrez.efetch(db="nucleotide", id=identifier, rettype="fasta", retmode="text")
record = SeqIO.read(handle, "fasta")
handle.close()

with open(f"{identifier}_reference.fasta", "w") as output_handle:
    SeqIO.write(record, output_handle, "fasta")
