process run_bowtie2 {
    cpus params.cpus
    container "eoksen/bowtie2.5.1:${params.architecture}"

    publishDir 'results/bowtie2', mode: 'copy'

    input:
    tuple val(name), path(reads)
    path reference

    output:
    tuple val(name), path("${name}.sam"), path("${name}_pair.align"), path("${name}_pair.unmapped")

    script:
    """
    bowtie2-build -f ${reference} ref_index -p ${task.cpus}
    bowtie2 -p ${task.cpus} -x ref_index -1 ${reads[0]} -2 ${reads[1]} -S ${name}.sam --al ${name}_pair.align --un ${name}_pair.unmapped -L ${params.L} -X ${params.X} --fr -q -t
    """
}
