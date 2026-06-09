process AUTOCYCLER_FINISH {

    tag "${isolate}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    tuple val(isolate), path(assembly_fastas)

    output:
    path "${isolate}/final", emit: final_dir

    script:
    """
    mkdir -p assemblies

    cp ${assembly_fastas.join(' ')} assemblies/

    ${projectDir}/bin/uva_nanopipe autocycler-finish \
        --isolate "${isolate}" \
        --assemblies assemblies \
        --outdir "${isolate}/final"
    """
}
