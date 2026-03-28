import groovy.json.JsonException
import groovy.json.JsonSlurper

def resolveManifestFile(String manifestPath) {
    File manifestFile = new File(manifestPath)
    if (!manifestFile.isAbsolute()) {
        manifestFile = new File(baseDir.toString(), manifestPath)
    }
    return manifestFile
}

def manifestError(File manifestFile, String message) {
    error("Invalid container image manifest at ${manifestFile}: ${message}")
}

def loadImageManifest(String manifestPath) {
    File manifestFile = resolveManifestFile(manifestPath)
    if (!manifestFile.exists()) {
        error("Container image manifest not found: ${manifestFile}")
    }
    try {
        def parsedManifest = new JsonSlurper().parse(manifestFile)
        if (!(parsedManifest instanceof Map)) {
            manifestError(manifestFile, "top-level JSON value must be an object")
        }
        return (Map) parsedManifest
    }
    catch (JsonException exception) {
        manifestError(manifestFile, "could not parse JSON (${exception.message})")
    }
}

def normalizeParamValue(def value, String fallback) {
    String normalizedValue = value?.toString()?.trim()
    return normalizedValue ? normalizedValue : fallback
}

def requireManifestMap(Map parent, String key, File manifestFile, String pathLabel) {
    def value = parent?.get(key)
    if (!(value instanceof Map)) {
        manifestError(manifestFile, "${pathLabel} must be an object")
    }
    return (Map) value
}

def requireManifestString(Map parent, String key, File manifestFile, String pathLabel) {
    String value = parent?.get(key)?.toString()?.trim()
    if (!value) {
        manifestError(manifestFile, "${pathLabel} must be a non-empty string")
    }
    return value
}

def validateImageManifest(Map imageManifest, File manifestFile) {
    Map defaults = requireManifestMap(imageManifest, 'defaults', manifestFile, 'defaults')
    requireManifestString(defaults, 'registry', manifestFile, 'defaults.registry')
    requireManifestString(defaults, 'namespace', manifestFile, 'defaults.namespace')

    Map images = requireManifestMap(imageManifest, 'images', manifestFile, 'images')
    List requiredImageKeys = [
        'aria2',
        'bcftools',
        'biopython',
        'bowtie2',
        'fastp',
        'pigz',
        'qualimap',
        'samtools',
        'sra_parser',
        'sra_tools',
    ]

    requiredImageKeys.each { String imageKey ->
        Map imageDefinition = requireManifestMap(images, imageKey, manifestFile, "images.${imageKey}")
        requireManifestString(imageDefinition, 'runtime_name', manifestFile, "images.${imageKey}.runtime_name")
        requireManifestString(imageDefinition, 'version', manifestFile, "images.${imageKey}.version")
    }
}

def buildImageReference(Map imageDefinition, String registry, String namespace) {
    String resolvedRegistry = normalizeParamValue(imageDefinition.get('registry'), registry)
    String resolvedNamespace = normalizeParamValue(imageDefinition.get('namespace'), namespace)
    String resolvedImageName = imageDefinition.runtime_name.toString()
    String resolvedVersion = imageDefinition.version.toString()
    String repository = [resolvedRegistry, resolvedNamespace, resolvedImageName]
        .findAll { it?.trim() }
        .join('/')
    return "${repository}:${resolvedVersion}"
}

def buildContainerImageMap(Map imageManifest, String registry, String namespace) {
    imageManifest.images.collectEntries { String imageKey, Map imageDefinition ->
        [(imageKey): buildImageReference(imageDefinition, registry, namespace)]
    }
}

def imageManifestFile = resolveManifestFile(params.image_manifest.toString())
def imageManifest = loadImageManifest(params.image_manifest.toString())
validateImageManifest(imageManifest, imageManifestFile)
def resolvedContainerRegistry = normalizeParamValue(params.container_registry, imageManifest.defaults.registry.toString())
def resolvedContainerNamespace = normalizeParamValue(params.container_namespace, imageManifest.defaults.namespace.toString())
params.container_registry = resolvedContainerRegistry
params.container_namespace = resolvedContainerNamespace
params.container_images = buildContainerImageMap(imageManifest, resolvedContainerRegistry, resolvedContainerNamespace)

if (params.help) {
    log.info """
    ======================
    SRA Alignment Pipeline
    ======================

    Usage:
      nextflow run main.nf [OPTIONS]
      nextflow run https://github.com/sophieships/sra_alignment_pipeline -r main [OPTIONS]

    Required:
      --email <address>         NCBI-registered email address
      --cpus <int>              Number of CPUs (default: 2)

    Input (one required):
      --sra_accession <id>      SRA accession number (requires --identifier)
      --identifier <id>         NCBI nucleotide identifier for reference genome
      --input_file <path>       CSV with columns: sra_accession, identifier

    Optional:
      --image_manifest <path>   Path to the tracked container image manifest
      --container_registry <r>  Override the container registry from the manifest
      --container_namespace <n> Override the container namespace from the manifest
      --L <int>                 Bowtie2 seed length (default: 22)
      --X <int>                 Bowtie2 max insert size (default: 600)
      --ploidy <int>            Ploidy for variant calling (default: 1)
      --include <expr>          bcftools filter inclusion expression
      --exclude <expr>          bcftools filter exclusion expression
      --help                    Show this help message
    """.stripIndent()
    exit 0
}

// If no SRA accession number, identifier, or input file is provided, throw an error.
if ( params.sra_accession == '' && params.identifier == '' && params.input_file == '' ) {
    error "You must provide either an SRA accession number and identifier with --sra_accession and --identifier, or an input file with --input_file"
}

// If only one of the SRA accession or identifier is provided without an input file, throw an error.
if (( params.sra_accession == '' || params.identifier == '' ) && params.input_file == '' ) {
    error("You have only provided one of the SRA accession or identifier. Both or an input file must be provided. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email> \nOr provide an input file: nextflow run main.nf --input_file <file> --cpus <cpus> --email <email>")
}

// If both an input file and individual SRA accession and/or identifier are provided, log a warning that only the input file will be used.
if ( params.input_file != '' && ( params.sra_accession != '' || params.identifier != '' )) {
    log.warn("Both an input file and individual SRA accession and/or identifier are provided. Only the input file will be used for the pipeline.")
}

// If no email is provided, throw an error. 
if ( params.email == '' ) {
    error("No email provided. Specify it with --email. \nCorrect usage: nextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email>")
}

// If the provided CPU number is not a number, throw an error.
if ( !params.cpus.toString().isNumber() ) {
    error("Invalid CPU number provided. Specify it with --cpus <int>. It should be an integer. \nTo check the number of CPUs on your system: \n- Unix-based (Linux/MacOS/WSL2): use the 'nproc' command \n- To adjust system cpu and memory allocation for Docker, go to Docker Desktop, then settings/resources and set cpu and memory parameters. \nnextflow run main.nf --sra_accession <accession> --identifier <identifier> --cpus <cpus> --email <email>")
}
log.info("Using container images from ${resolvedContainerRegistry}/${resolvedContainerNamespace}")

include { get_srrs } from './nf_scripts/get_srrs'
include { parse_srrs } from './nf_scripts/parse_srrs'
include { download_fastq } from './nf_scripts/download_fastq'
include { run_fasterq_dump } from './nf_scripts/run_fasterq_dump'
include { run_pigz } from './nf_scripts/run_pigz'
include { run_fastp } from './nf_scripts/run_fastp'
include { download_fasta } from './nf_scripts/download_fasta'
include { run_bowtie2 } from './nf_scripts/run_bowtie2'
include { run_samtools } from './nf_scripts/run_samtools'
include { run_bcftools } from './nf_scripts/run_bcftools'
include { run_qualimap } from './nf_scripts/run_qualimap'
include { run_bcftools_filter } from './nf_scripts/run_bcftools_filter'

workflow {
    if ( params.sra_accession && params.identifier && params.input_file == '' ) {
        log.info("SRA accession and identifier provided. Downloading SRRs from SRA.")
        Channel.value( [params.sra_accession, params.identifier] )
            .set { accessions_channel }

        accessions = accessions_channel.map { it[0] }
        identifiers = accessions_channel.map { it[1] }
        get_srrs( accessions, identifiers )
            srr_tuples = get_srrs.out.srr_list
                     .collectFile()
                     .splitCsv( header: false )
                     .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }

        download_fastq( sra_accessions_channel )
        
        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join( run_fasterq_dump.out.reverse_reads), download_fastq.out.download_status )

        // mix the forward and reverse reads from download_fastq and run_pigz
        forward_reads = download_fastq.out.gzip_forward_reads.mix( run_pigz.out.gzip_forward_reads )
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix( run_pigz.out.gzip_reverse_reads )

        download_fasta( sra_accessions_channel, identifiers_channel, params.email )
    }
    else {
        log.info("Input file provided. Parsing SRRs from input file.")
        Channel.fromPath( params.input_file )
            .set { input_file_channel }
        
        parse_srrs( input_file_channel )
        srr_tuples = parse_srrs.out.parsed_srrs
                    .collectFile()
                    .splitCsv( header: false) 
                    .map { tuple(it[0], it[1]) }

        sra_accessions_channel = srr_tuples.map{ it[0] }
        identifiers_channel = srr_tuples.map{ it[1] }

        download_fastq( sra_accessions_channel )

        // run only when download_status is emitted from download_fastq
        run_fasterq_dump( download_fastq.out.download_status )
        run_pigz( run_fasterq_dump.out.forward_reads.join(run_fasterq_dump.out.reverse_reads), download_fastq.out.download_status )

        // mix the forward and reverse reads from download_fastq and run_pigz
        forward_reads = download_fastq.out.gzip_forward_reads.mix( run_pigz.out.gzip_forward_reads )
        reverse_reads = download_fastq.out.gzip_reverse_reads.mix( run_pigz.out.gzip_reverse_reads )

        download_fasta( sra_accessions_channel, identifiers_channel, params.email )

    }
    
    run_fastp( forward_reads.join( reverse_reads ) )
    
    run_bowtie2( run_fastp.out.trimmed_forward_reads.join( run_fastp.out.trimmed_reverse_reads), download_fasta.out.downloaded_fasta )
    
    run_samtools( run_bowtie2.out.bowtie2_output, download_fasta.out.downloaded_fasta )
    
    run_qualimap( run_samtools.out.sorted_bam )

    run_bcftools( run_samtools.out.sorted_bam, run_samtools.out.indexed_references )
    if ( params.include || params.exclude ) {
        run_bcftools_filter( run_bcftools.out.vcf_files )
    }
}
