nextflow.enable.dsl=2

include { COVERAGE } from './modules/local/coverage'
include { SUMMARIZE_COVERAGE } from './modules/local/summarize_coverage'

include { AUTOCYCLER_SUBSAMPLE } from './modules/local/autocycler_subsample'
include { AUTOCYCLER_ASSEMBLE } from './modules/local/autocycler_assemble'
include { AUTOCYCLER_WEIGHT } from './modules/local/autocycler_weight'
include { AUTOCYCLER_FINISH } from './modules/local/autocycler_finish'

workflow {

    if (params.input == null) {
        error "Please provide an input CSV with --input"
    }

    samples_ch = Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row ->
            tuple(row.Isolate, file(row.Reads))
        }

    COVERAGE(samples_ch)

    SUMMARIZE_COVERAGE(
        COVERAGE.out.coverage_dir.collect()
    )

    AUTOCYCLER_SUBSAMPLE(
        COVERAGE.out.coverage_dir
    )

    assembly_jobs_ch = AUTOCYCLER_SUBSAMPLE.out.subsample_dir
        .flatMap { subsample_dir ->

            def isolate = subsample_dir.parent.baseName
            def genome_size_file = file("${subsample_dir}/genome_size.txt")

            params.assemblers.collectMany { assembler ->
                ['01', '02', '03', '04'].collect { sample_id ->
                    tuple(
                        isolate,
                        assembler,
                        sample_id,
                        file("${subsample_dir}/subsampled_reads/sample_${sample_id}.fastq"),
                        genome_size_file
                    )
                }
            }
        }

    AUTOCYCLER_ASSEMBLE(assembly_jobs_ch)

    assembly_grouped_ch = AUTOCYCLER_ASSEMBLE.out.assembly_result
        .map { assembly_dir ->
            def isolate = assembly_dir.parent.parent.baseName
            tuple(isolate, assembly_dir)
        }
        .groupTuple()

    subsample_keyed_ch = AUTOCYCLER_SUBSAMPLE.out.subsample_dir
        .map { subsample_dir ->
            def isolate = subsample_dir.parent.baseName
            tuple(isolate, subsample_dir)
        }

    weight_input_ch = assembly_grouped_ch
        .join(subsample_keyed_ch)
        .map { isolate, assembly_dirs, subsample_dir ->
            tuple(isolate, assembly_dirs, subsample_dir)
        }

    AUTOCYCLER_WEIGHT(weight_input_ch)

    AUTOCYCLER_FINISH(AUTOCYCLER_WEIGHT.out.assemblies)
}
