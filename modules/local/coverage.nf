process COVERAGE {

    tag "${isolate}"

    conda "${projectDir}/envs/coverage.yml"

    input:
    tuple val(isolate), path(reads)

    output:
    tuple val(isolate), path("${isolate}"), emit: coverage_dir

    script:
    """
    ${projectDir}/bin/uva_nanopipe coverage \
        --isolate ${isolate} \
        --reads ${reads} \
        --outdir ${isolate} \
        --threads ${task.cpus}
    """
}
