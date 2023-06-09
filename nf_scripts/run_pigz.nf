process run_pigz {
    cpus params.cpus
    container 'eoksen/pigz:2.6-1'

    publishDir "results/${sra_accession}/fastq", mode: 'copy'


    input:
    tuple val(sra_accession), path(forward_reads), path(reverse_reads)
    path download_status

    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq.gz"), emit: gzip_forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq.gz"), emit: gzip_reverse_reads

    when:
    download_status.exists()

    script:
    """
    pigz -f -p ${task.cpus} ${forward_reads}
    pigz -f -p ${task.cpus} ${reverse_reads}
    """
}
