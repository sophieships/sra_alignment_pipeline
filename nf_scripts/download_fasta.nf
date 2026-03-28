process download_fasta {
    maxForks 1
    container "${params.container_images.biopython}"

    storeDir "results/reference_genomes"

    input:
    val sra_accession
    val identifierVal
    val emailval

    output:
    path("${identifierVal}_reference.fasta.gz"), emit: downloaded_fasta

    script:
    """
    echo "Downloading fasta file for ${identifierVal}"
    python /scripts/download_fasta.py ${identifierVal} ${emailval}
    """
}
