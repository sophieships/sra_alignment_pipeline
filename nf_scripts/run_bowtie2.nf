process run_bowtie2 {
    cpus params.cpus
    container "eoksen/bowtie2.5.1:${params.architecture}"

    publishDir 'results/bowtie2', mode: 'copy'

    input:
    tuple val(name), path(forward_reads), path(reverse_reads)
    path downloaded_fasta

    output:
    tuple val(name), path("${name}.sam"), path("${name}_pair.align"), path("${name}_pair.unmapped"), emit: bowtie2_output

    script:
    """
    bowtie2-build -f ${downloaded_fasta} ref_index -p ${task.cpus}
    bowtie2 -p ${task.cpus} -x ref_index -1 ${forward_reads} -2 ${reverse_reads} -S ${name}.sam --al ${name}_pair.align --un ${name}_pair.unmapped -L ${params.L} -X ${params.X} --fr -q -t
    """
}
