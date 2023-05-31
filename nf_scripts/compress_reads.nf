process compress_reads {
    cpus params.cpus
    container 'eoksen/pigz:2.6-1'

    publishDir 'results/fastq', mode: 'copy'


    input:
    tuple val(sra_accession), path(forward_reads), path(reverse_reads)

    output:
    tuple val(sra_accession), path("${sra_accession}_1.fastq.gz"), emit: gzip_forward_reads
    tuple val(sra_accession), path("${sra_accession}_2.fastq.gz"), emit: gzip_reverse_reads

    script:
    """
    pigz -f -p ${task.cpus} ${forward_reads}
    pigz -f -p ${task.cpus} ${reverse_reads}
    """
}
