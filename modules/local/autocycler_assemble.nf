process AUTOCYCLER_ASSEMBLE {

    tag "${isolate}_${assembler}_${sample_id}"

    conda "/scratch/sgj4qr/pgcoe_nanopore/autocycler"

    input:
    tuple val(isolate), val(assembler), val(sample_id), path(reads), path(genome_size_file)

    output:
    path "${isolate}/assemblies_raw/${assembler}_${sample_id}", emit: assembly_result

    script:
    """
    ${projectDir}/bin/uva_nanopipe autocycler-assemble-one \
        --isolate ${isolate} \
        --assembler ${assembler} \
        --sample ${sample_id} \
        --reads ${reads} \
        --genome-size ${genome_size_file} \
        --outdir ${isolate}/assemblies_raw/${assembler}_${sample_id} \
        --threads ${task.cpus} \
        --read-type ${params.read_type} \
        --plassembler-db "${params.plassembler_db ?: 'NONE'}"
    """
}
