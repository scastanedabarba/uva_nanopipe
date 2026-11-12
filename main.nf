nextflow.enable.dsl=2

include { COVERAGE } from './modules/local/coverage'
include { SUMMARIZE_COVERAGE } from './modules/local/summarize_coverage'
include { AUTOCYCLER_SUBSAMPLE } from './modules/local/autocycler_subsample'
include { AUTOCYCLER_ASSEMBLE } from './modules/local/autocycler_assemble'
include { AUTOCYCLER_WEIGHT } from './modules/local/autocycler_weight'
include { AUTOCYCLER_FINISH } from './modules/local/autocycler_finish'
include { SUMMARIZE_ASSEMBLIES } from './modules/local/summarize_assemblies'
include { RECORD_ASSEMBLY_INPUT } from './modules/local/record_assembly_input'

workflow {
    if (!params.input) error 'Provide --input /path/to/linelist.csv'
    if (!(params.step in ['prep', 'assembly'])) error 'Specify --step prep or --step assembly'
    def input_csv = file(params.input)
    if (!input_csv.exists()) error "Input manifest does not exist: ${input_csv}"

    if (params.step == 'prep') {
        samples_ch = Channel.fromPath(params.input).splitCsv(header: true).map { row ->
            def isolate = (row.Isolate ?: '').trim()
            def reads_path = (row.Reads ?: '').trim()
            if (!(isolate ==~ /[A-Za-z0-9._-]+/)) error "Invalid Isolate in prep input: ${isolate}"
            if (!reads_path) error "Missing Reads for ${isolate}"
            def reads = file(reads_path)
            if (!reads.exists() || !reads.isFile()) error "FASTQ not found for ${isolate}: ${reads}"
            tuple(isolate, reads)
        }
        COVERAGE(samples_ch)
        SUMMARIZE_COVERAGE(COVERAGE.out.coverage_dir.collect())
    }
    else {
        // Assembly requires only the user-provided manifest, not preparation artifacts.
        def assembly_rows = Channel.fromPath(params.input).splitCsv(header: true).map { row ->
            def isolate = (row.Isolate ?: '').trim()
            if (!(isolate ==~ /[A-Za-z0-9._-]+/)) error "Invalid Isolate in assembly input: ${isolate}"
            def selected = (row.Assemble ?: 'true').trim().toLowerCase()
            if (!(selected in ['true', 'false'])) error "Assemble must be true/false for ${isolate}"
            if (selected == 'false') return null
            def reads_path = (row.Reads ?: '').trim()
            def gs = (row.GenomeSize ?: '').trim()
            def depth = (row.MinReadDepth ?: '25').trim()
            if (!reads_path) error "Missing Reads for selected isolate ${isolate}"
            def reads = file(reads_path)
            if (!reads.exists() || !reads.isFile()) error "FASTQ not found for ${isolate}: ${reads}"
            if (!(gs ==~ /[0-9]+/) || gs.toLong() <= 0L) error "Invalid GenomeSize for ${isolate}: ${gs}"
            if (!(depth ==~ /[0-9]+/) || depth.toInteger() <= 0) error "Invalid MinReadDepth for ${isolate}: ${depth}"
            tuple(isolate, reads, gs.toLong(), depth.toInteger())
        }.filter { it != null }

        // Save an exact copy of the supplied manifest (including skipped rows).
        RECORD_ASSEMBLY_INPUT(Channel.fromPath(params.input))
        AUTOCYCLER_SUBSAMPLE(assembly_rows)

        assembly_jobs_ch = AUTOCYCLER_SUBSAMPLE.out.subsample_result.flatMap { isolate, subsample_dir ->
            def genome_size_file = file("${subsample_dir}/genome_size.txt")
            params.assemblers.collectMany { assembler ->
                ['01', '02', '03', '04'].collect { sample_id ->
                    tuple(isolate, assembler, sample_id,
                          file("${subsample_dir}/subsampled_reads/sample_${sample_id}.fastq"), genome_size_file)
                }
            }
        }
        AUTOCYCLER_ASSEMBLE(assembly_jobs_ch)
        def assemblies_per_isolate = params.assemblers.size() * 4
        assembly_grouped_ch = AUTOCYCLER_ASSEMBLE.out.assembly_result
            .map { assembly_dir -> tuple(assembly_dir.parent.parent.baseName, assembly_dir) }
            .groupTuple(by: 0, size: assemblies_per_isolate)
        weight_input_ch = assembly_grouped_ch.join(AUTOCYCLER_SUBSAMPLE.out.subsample_result)
            .map { isolate, assembly_dirs, subsample_dir -> tuple(isolate, assembly_dirs, subsample_dir) }
        AUTOCYCLER_WEIGHT(weight_input_ch)
        AUTOCYCLER_FINISH(AUTOCYCLER_WEIGHT.out.assemblies)
        SUMMARIZE_ASSEMBLIES(AUTOCYCLER_FINISH.out.final_dir_for_summary.collect())
    }
}
