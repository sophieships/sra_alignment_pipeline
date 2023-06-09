process parse_srrs {
    container 'eoksen/sra-parser:1.0'

    publishDir "results/${input_file}/srr_lists", mode: 'copy'

    input:
    path(input_file)

    output:
    path("${input_file}_srr_list.csv"), emit: parsed_srrs

    script:
    """
    python /scripts/sra_parser.py ${input_file} > ${input_file}_srr_list.csv
    """
}
