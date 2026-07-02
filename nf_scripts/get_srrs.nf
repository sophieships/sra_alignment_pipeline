process get_srrs {
    label 'process_low'
    container "${params.container_image}"

    publishDir "${params.outdir}/${accession}/srr_lists", mode: 'copy'

    input:
    val(accession)
    val(identifier)

    output:
    path("${accession}_srr_list.csv"), emit: srr_list

    script:
    """
    sra_parser.py ${accession} ${identifier} > ${accession}_srr_list.csv
    """

    stub:
    """
    echo "${accession},${identifier}" > ${accession}_srr_list.csv
    """
}
