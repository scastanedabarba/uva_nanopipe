nextflow.enable.dsl=2

include { COVERAGE } from './modules/local/coverage'

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
}
