process run_pigz {
    label 'process_low'
    container "${params.container_image}"

    publishDir "${params.outdir}/${sra_accession}/fastq", mode: 'copy'


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

    stub:
    """
    touch ${sra_accession}_1.fastq.gz ${sra_accession}_2.fastq.gz
    """
}
