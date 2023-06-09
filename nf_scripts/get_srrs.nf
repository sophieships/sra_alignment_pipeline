process get_srrs {
    container 'eoksen/sra-parser:1.0'

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
