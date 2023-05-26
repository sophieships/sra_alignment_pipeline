// Validate parameters
if (params.sra_accession == '' && params.identifier == '' && params.input_file == '') {
    error "You must provide either an SRA accession number and identifier with --sra_accession and --identifier, or an input file with --input_file"
}

if ((params.sra_accession == '' || params.identifier == '') && params.input_file == '') {
    error("You have only provided one of the SRA accession or identifier. Both or an input file must be provided. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64> \nOr provide an input file: nextflow run main.nf --input_file <file> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.input_file != '' && (params.sra_accession != '' || params.identifier != '')) {
    log.warn("Both an input file and individual SRA accession and/or identifier are provided. Only the input file will be used for the pipeline.")
}

if (params.email == '') {
    error("No email provided. Specify it with --email. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.cpus == '' || !params.cpus.toString().isNumber()) {
    error("Invalid or no CPU number provided. Specify it with --cpus. It should be a number. \nTo check the number of CPUs on your system: \n- Unix-based (Linux/MacOS/WSL2): use the 'nproc' command \nnextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

if (params.architecture == '') {
    error("No architecture provided. Specify it with --architecture. \nTo check your system's architecture: \n- Unix-based (Linux/MacOS/WSL2): use the 'uname -m' command \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> --architecture <arm64 or x86_64>")
}

include { fastq_dump } from './nf_scripts/fastq_dump'
include { run_fastp } from './nf_scripts/run_fastp'
include { downloadfasta } from './nf_scripts/downloadfasta'
include { run_bowtie2 } from './nf_scripts/run_bowtie2'
include { run_samtools } from './nf_scripts/run_samtools'
include { run_bcftools } from './nf_scripts/run_bcftools'
include { run_qualimap } from './nf_scripts/run_qualimap'
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter'


// Create the default channel with a single accession and identifier
default_channel = Channel.value([params.sra_accession, params.identifier])

// If an input file is specified, create a channel from the file
if (params.input_file != '') {
    Channel
        .fromPath(params.input_file)
        .splitCsv() // splits by line
        .map { tuple(it[0], it[1]) } // create tuple for each line
        .set { file_channel }
} else {
    // If no input file is specified, use the default channel
    file_channel = default_channel
}

file_channel
    .map {
        accession, identifier -> tuple(accession, identifier)
    }
    .set { entries }

// Split the tuple into separate channels
accessions = file_channel.map { it[0] }
identifiers = file_channel.map { it[1] }

workflow {

    fastq_dump( accessions )
    run_fastp( fastq_dump.out.forward_reads.join(fastq_dump.out.reverse_reads) )
    downloadfasta( identifiers, params.email )
    run_bowtie2( run_fastp.out.trimmed_forward_reads.join(run_fastp.out.trimmed_reverse_reads), downloadfasta.out.downloaded_fasta )
    run_samtools( run_bowtie2.out.bowtie2_output, downloadfasta.out.downloaded_fasta )
    run_bcftools( run_samtools.out.sorted_bam, run_samtools.out.indexed_references )
    run_qualimap( run_samtools.out.sorted_bam )

    if (params.include || params.exclude) {
        run_bcftools_filter( run_bcftools.out.vcf_files )
    }
}