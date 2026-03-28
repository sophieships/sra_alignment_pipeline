process run_fastp {
    cpus params.cpus
    container "${params.container_image}"

    publishDir "results/${name}/fastp", mode: 'copy'

    input:
    tuple val(name), path(forward_reads), path(reverse_reads)

    output:
    tuple val(name), path("${name}_trimmed_1.fastq.gz"), emit: trimmed_forward_reads
    tuple val(name), path("${name}_trimmed_2.fastq.gz"), emit: trimmed_reverse_reads
    path("${name}_fastp_report.html"), emit: fastp_html_report
    path("${name}_fastp_report.json"), emit: fastp_json_report

    script:
    """
    export LD_LIBRARY_PATH=/usr/local/lib
    fastp -w ${task.cpus} -i ${forward_reads} -I ${reverse_reads} -o ${name}_trimmed_1.fastq.gz -O ${name}_trimmed_2.fastq.gz -h ${name}_fastp_report.html -j ${name}_fastp_report.json
    """
}
