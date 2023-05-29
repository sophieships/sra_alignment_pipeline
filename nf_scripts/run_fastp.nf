process run_fastp {
    cpus params.cpus
    container 'eoksen/fastp:v0.23.3'

    publishDir 'results/fastp', mode: 'copy'

    input:
    tuple val(name), path(forward_reads), path(reverse_reads)

    output:
    tuple val(name), path("${name}_trimmed_1.fastq.gz"), emit: trimmed_forward_reads
    tuple val(name), path("${name}_trimmed_2.fastq.gz"), emit: trimmed_reverse_reads


    script:
    """
    export LD_LIBRARY_PATH=/usr/local/lib
    fastp -w ${task.cpus} -i ${forward_reads} -I ${reverse_reads} -o ${name}_trimmed_1.fastq.gz -O ${name}_trimmed_2.fastq.gz
    """
}
