# UVA NanoPipe

UVA NanoPipe is a modular long-read bacterial genome assembly pipeline for Oxford Nanopore sequencing data. The workflow is implemented in Nextflow DSL2 and is designed to provide a reproducible, scalable, and HPC-compatible implementation of the Autocycler assembly workflow.

The pipeline primarily serves as an orchestration and workflow management layer around existing long-read assembly tools and the Autocycler consensus framework. UVA NanoPipe automates preprocessing, parallel assembler execution, assembly organization, weighting, and final consensus generation within a reproducible Nextflow environment suitable for SLURM-based HPC systems.

In addition to assembly orchestration, the pipeline includes an initial coverage estimation and read filtering stage designed to provide early sequencing quality metrics prior to assembly. These summaries allow users to rapidly identify isolates with insufficient coverage, poor read quality, or other characteristics likely to negatively impact downstream assembly performance. This enables early identification of problematic isolates before computationally intensive assembly steps are performed.

The underlying consensus-generation methodology is provided by Autocycler and associated long-read assemblers. UVA NanoPipe does not replace these tools, but instead provides a modular framework for executing, managing, and scaling them in a standardized workflow.

---

# Features

- Long-read bacterial genome assembly
- Parallel multi-assembler execution
- Autocycler-based consensus assembly
- Coverage estimation and read filtering
- Modular Nextflow DSL2 design
- SLURM-compatible execution
- Resumable workflow execution

---

# Workflow Overview

The pipeline currently performs:

1. Read QC and filtering
2. Coverage estimation and genome size estimation
3. Autocycler subsampling
4. Parallel execution of multiple long-read assemblers
5. Assembly weighting and collection
6. Autocycler consensus generation

The workflow is intentionally modular, allowing users to inspect and modify intermediate assemblies prior to final consensus generation.

---

# Current Workflow

## Step 1 — Coverage Estimation and Read Filtering

Processes:
- NanoStat
- Chopper
- Genome size estimation using Autocycler helper (Raven)
- Coverage estimation

Purpose:
This stage is intended to provide early sequencing QC and assembly feasibility metrics prior to computationally intensive assembly generation. Coverage summaries and filtering statistics can help identify isolates with:
- insufficient sequencing depth
- poor read quality
- abnormal genome size estimates
- potentially problematic datasets likely to fail assembly

Outputs:
- `coverage.csv`
- `read_filtering.csv`
- filtered FASTQ files
- `genome_size.txt`

These metrics can be used to evaluate sequencing quality and determine whether additional sequencing or preprocessing may be required prior to assembly.

---

## Step 2 — Autocycler Subsampling

Runs:
- `autocycler subsample`

Outputs:
- subsampled read sets
- assembly-ready FASTQ files

---

## Step 3 — Parallel Assembly

Each assembler/subsample combination is submitted independently through Nextflow + SLURM.

Supported assemblers:
- raven
- miniasm
- flye
- metamdbg
- necat
- nextdenovo
- canu
- plassembler

Each assembler is run independently on:
- `sample_01`
- `sample_02`
- `sample_03`
- `sample_04`

Outputs:
- individual assembler FASTA files
- assembler logs
- assembler-specific intermediate outputs

Example:
- `canu_01.fasta`
- `flye_02.fasta`
- `raven_03.fasta`

---

## Step 4 — Assembly Weighting

Post-processing includes:
- collection of all assembly FASTAs
- Plassembler circular contig weighting
- Flye/Canu consensus weighting

Outputs:
- weighted assembly FASTAs for Autocycler consensus generation

---

## Step 5 — Autocycler Finalization

Runs:
- `autocycler compress`
- `autocycler cluster`
- `autocycler trim`
- `autocycler resolve`
- `autocycler combine`

Outputs:
- final consensus assembly
- Autocycler intermediate outputs
- clustering information
- consensus graph files

---

# Pipeline Structure

```text
uva_nanopipe/
├── bin/
├── conf/
├── envs/
├── modules/
│   └── local/
├── scripts/
├── main.nf
├── nextflow.config
└── README.md
```

---

# Input Format

## Example Input CSV

```csv
Isolate,Reads
AR_091,/path/to/AR_091.fastq.gz
```

Required columns:
- `Isolate`
- `Reads`

---

# Running the Pipeline

## Example Run

```bash
nextflow run main.nf \
    -profile slurm \
    -c conf/uva.config \
    --input linelist.csv \
    --outdir results/test
```

## Resume Previous Run

```bash
-resume
```

---

# Example SLURM Configuration

## `conf/uva.config`

```nextflow
executor {
    exitReadTimeout = '2 h'
}

process {

    executor = 'slurm'
    queue = 'standard'
    account = 'amr_services_paid'

    cpus = 8
    memory = '32 GB'
    time = '48h'
}

params {
    plassembler_db = "/path/to/plassembler_db"
}
```

---

# Plassembler Database

If Plassembler is enabled, a Plassembler database must be installed separately.

## Install Database

```bash
conda activate autocycler

plassembler download -d /path/to/plassembler_db
```

## Provide Database Path

Command line:

```bash
--plassembler_db /path/to/plassembler_db
```

or in config:

```nextflow
params {
    plassembler_db = "/path/to/plassembler_db"
}
```

---

# Output Structure

Example isolate output:

```text
results/
└── AR_091/
    ├── coverage/
    ├── subsample/
    ├── assemblies_raw/
    ├── drafts/
    └── final/
```

---

# Design Philosophy

UVA NanoPipe is designed as a workflow implementation layer around Autocycler rather than a novel assembly algorithm itself.

Key goals include:
- reproducible execution on HPC systems
- modular DSL2 workflow organization
- scalable parallel assembly execution
- simplified management of multiple assembler outputs
- compatibility with containerized and nf-core-style workflows
- preservation of Autocycler’s flexible manual inspection workflow

Autocycler is intentionally separated into:
1. Draft assembly generation
2. Final consensus generation

This design allows users to:
- inspect intermediate assemblies
- remove problematic assemblies
- manually modify weights
- rerun finalization independently
- debug assembler-specific issues without rerunning the entire workflow

UVA NanoPipe aims to make these steps easier to execute reproducibly at scale while preserving the flexibility of the original Autocycler methodology.

---

# Development Priorities

Current priorities:
1. Stabilize workflow behavior
2. Add polishing
3. Add annotation
4. Add QC summaries
5. Add container support
6. Add nf-core compatibility
7. Add automated reporting

---

# Useful Commands

## Monitor Jobs

```bash
squeue -u $USER
```

## Check SLURM Accounting

```bash
sacct -j <JOBID>
```

## Inspect Logs

```bash
find work -name ".command.err"
find work -name ".command.out"
```

## Clean Failed Cached Processes

```bash
nextflow clean -f
```

---

# Troubleshooting

## Canu Jobs Reported as Failed While Still Running

Some SLURM systems may require increasing:

```nextflow
executor {
    exitReadTimeout = '2 h'
}
```

to prevent premature Nextflow timeout detection for long-running Canu jobs.

---

# Status

Current status:
- Core assembly workflow operational
- Parallel assembly functioning
- Autocycler integration functioning
- Active development ongoing



## Two-stage execution: preparation and assembly

Run preparation first (QC, Chopper filtering, Raven genome-size estimation, coverage summaries):

```bash
nextflow run main.nf -profile slurm --input linelist.csv --outdir results/test --step prep
```

Review `results/test/summary/coverage.csv`, `results/test/summary/read_filtering.csv`, and per-isolate results under `results/test/coverage/`. Inspect or correct each `coverage/<isolate>/genome_size/genome_size.txt` if appropriate.

Then run assembly using the **same outdir** and input CSV:

```bash
nextflow run main.nf -profile slurm --input linelist.csv --outdir results/test --step assembly
```

Assembly reads published filtered FASTQs and genome-size/coverage files; it does **not** rerun preparation or require `-resume`. A reduced input CSV may be supplied to assemble only selected isolates, provided they were previously prepared. Samples with missing outputs or a non-OK preparation status cause assembly to stop. Use `-resume` only when retrying the same stage and wanting Nextflow cache reuse.

The `--step` argument is required (`prep` or `assembly`). Basecalling is unchanged and outside these stages.
