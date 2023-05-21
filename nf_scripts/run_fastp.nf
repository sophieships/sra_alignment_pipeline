process run_fastp {
    container 'eoksen/fastp:v0.23.3'

    publishDir 'results/fastp', mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    tuple val(name), path("*_trimmed_{1,2}.fastq.gz")

    script:
    """
    export LD_LIBRARY_PATH=/usr/local/lib
    fastp -i ${reads[0]} -I ${reads[1]} -o ${name}_trimmed_1.fastq.gz -O ${name}_trimmed_2.fastq.gz
    """
}
