nextflow.enable.dsl = 2

include { download_fasta } from '../../nf_scripts/download_fasta' addParams(container_image: 'unused-in-local-test')

workflow {
    download_fasta(
        Channel.value('SRR_TEST'),
        Channel.value('NC_TEST.1'),
        Channel.value('test@example.com')
    )
}
