nextflow.enable.dsl = 2

include { run_fasterq_dump } from '../../nf_scripts/run_fasterq_dump' addParams(container_image: 'unused-in-local-test')
include { run_pigz } from '../../nf_scripts/run_pigz' addParams(container_image: 'unused-in-local-test')

workflow {
    download_status = Channel.fromPath(params.download_status, checkIfExists: true)
    run_fasterq_dump(download_status)
    paired_reads = run_fasterq_dump.out.forward_reads.join(run_fasterq_dump.out.reverse_reads)
    run_pigz(paired_reads)
}
