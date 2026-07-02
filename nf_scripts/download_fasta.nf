process download_fasta {
    label 'process_low'
    maxForks 1
    container "${params.container_image}"

    storeDir "${params.outdir}/reference_genomes"

    input:
    val sra_accession
    val identifierVal
    val emailval

    output:
    path("${identifierVal}_reference.fasta.gz"), emit: downloaded_fasta

    script:
    """
    echo "Downloading fasta file for ${identifierVal}"
    download_fasta.py ${identifierVal} ${emailval}
    """

    stub:
    """
    touch ${identifierVal}_reference.fasta.gz
    """
}
