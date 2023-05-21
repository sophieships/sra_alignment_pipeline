// Validate parameters
if (params.sra_accession == '') {
    error "You must provide an SRA accession number with --sra_accession"
}

if (params.identifier == '') {
    log.error("No identifier provided. Specify it with --identifier. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email>")
    exit 1
}

if (params.email == '') {
    log.error("No email provided. Specify it with --email. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email>")
    exit 1
}

if (params.cpus= = '' || !(params.cpus.isNumber())) {
    log.error("Invalid or no CPU number provided. Specify it with --cpus. It should be a number. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email>")
    exit 1
}

include { fastq_dump } from './nf_scripts/fastq_dump'
include { run_fastp } from './nf_scripts/run_fastp'
include { downloadfasta } from './nf_scripts/downloadfasta'
include { run_bowtie2 } from './nf_scripts/run_bowtie2'
include { run_samtools } from './nf_scripts/run_samtools'
include { run_bcftools } from './nf_scripts/run_bcftools'
include { run_qualimap } from './nf_scripts/run_qualimap'
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter'


workflow {
    fastq_dump( params.sra_accession )
    run_fastp( fastq_dump.out.reads )
    downloadfasta( [ params.identifier, params.email ] )
    run_bowtie2( run_fastp.out.reads, downloadfasta.out.downloaded )
    run_samtools( run_bowtie2.out.sam, downloadfasta.out.downloaded )
    run_bcftools( run_samtools.out.sorted_bam, run_samtools.out.indexed_references )
    run_qualimap( run_samtools.out.sorted_bam )

    if (params.include || params.exclude) {
        run_bcftools_filter( run_bcftools.out.vcf_files )
    }
}