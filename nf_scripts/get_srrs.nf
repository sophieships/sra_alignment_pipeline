process get_srrs {
    container "${params.container_images.sra_parser}"

    publishDir "results/${accession}/srr_lists", mode: 'copy'

    input:
    val(accession)
    val(identifier)

    output:
    path("${accession}_srr_list.csv"), emit: srr_list

    script:
    """
    python /scripts/sra_parser.py ${accession} ${identifier} > ${accession}_srr_list.csv
    """
}
