from Bio import Entrez, SeqIO
import pysam

def download_fasta(identifier, email):
    Entrez.email = email
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