process run_samtools {
    cpus params.cpus
    container 'eoksen/samtools:1.17'

    publishDir 'results/samtools', mode: 'copy'

    input:
    path(sam_file)
    path reference

    output:
    path("${sam_file.baseName}.sorted.bam"), emit: sorted_bam
    path("${sam_file.baseName}.sorted.bam.bai"), emit: bam_index
    tuple(path("${reference}"), path("${reference}.fai")), emit: indexed_references

    script:
    """
    samtools view -b ${sam_file} -o ${sam_file.baseName}.bam
    samtools sort -@ ${task.cpus} -o ${sam_file.baseName}.sorted.bam ${sam_file.baseName}.bam
    samtools index ${sam_file.baseName}.sorted.bam
    samtools faidx ${reference}
    """
}
