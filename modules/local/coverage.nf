process COVERAGE {

    tag "${isolate}"

    conda "${projectDir}/envs/coverage.yml"

    input:
    tuple val(isolate), path(reads)

    output:
    path "${isolate}", emit: coverage_dir

    path "${isolate}/coverage.csv", emit: coverage_csv
    path "${isolate}/read_filtering.csv", emit: filtering_csv

    script:
    """
    ${projectDir}/bin/uva_nanopipe coverage \
        --isolate ${isolate} \
        --reads ${reads} \
        --outdir ${isolate} \
        --threads ${task.cpus}
    """
}
