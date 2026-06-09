process AUTOCYCLER_FINISH {

    tag "${drafts_dir.parent.baseName}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    path drafts_dir

    output:
    path "${drafts_dir.parent.baseName}/final", emit: final_dir

    script:
    """
    isolate="${drafts_dir.parent.baseName}"

    ${projectDir}/bin/uva_nanopipe autocycler-finish \
        --isolate "\${isolate}" \
        --assemblies "${drafts_dir}/assemblies" \
        --outdir "\${isolate}/final"
    """
}
