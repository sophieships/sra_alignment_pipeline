process downloadfasta {
    container 'eoksen/biopython-pysam:3.9'

    publishDir 'results/downloaded_fasta', mode: 'copy'

    input:
    val identifierVal
    val emailval

    output:
    path("${identifierVal}_reference.fasta.gz"), emit: downloaded_fasta

    script:
    """
    python /scripts/download_fasta.py ${identifierVal} ${emailval}
    """
}
