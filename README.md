
# UVA NanoPipe

UVA NanoPipe is a modular long-read bacterial genome assembly pipeline being developed for Oxford Nanopore sequencing data. The pipeline is designed around Nextflow DSL2 and is intended to eventually become an nf-core compatible workflow.

Current implemented stages:

1. Coverage estimation and read filtering
2. Autocycler subsampling
3. Parallel assembler execution
4. Assembly weighting
5. Final Autocycler consensus generation

---

# Current Pipeline Structure

uva_nanopipe/
├── bin/
├── conf/
├── envs/
├── modules/
├── scripts/
├── main.nf
└── README.txt

---

# Current Workflow

## Step 1 — Coverage Estimation

Processes:
- NanoStat
- Chopper filtering
- Genome size estimation with Autocycler helper (Raven)
- Coverage estimation

Outputs:
- coverage.csv
- read_filtering.csv
- trimmed reads
- genome_size.txt

---

## Step 2 — Autocycler Subsample

Runs:
- autocycler subsample

Produces:
- subsampled read sets
- draft assembly preparation

---

## Step 3 — Parallel Assembly

Each assembler/sample combination is submitted independently through Nextflow + SLURM.

Assemblers currently supported:
- raven
- miniasm
- flye
- metamdbg
- necat
- nextdenovo
- canu
- plassembler

Each assembler runs independently on:
- sample_01
- sample_02
- sample_03
- sample_04

---

## Step 4 — Assembly Weighting

Post-processing:
- Plassembler circular contig weighting
- Flye/Canu consensus weighting
- Assembly collection

---

## Step 5 — Autocycler Finalization

Runs:
- autocycler compress
- autocycler cluster
- autocycler trim
- autocycler resolve
- autocycler combine

Produces:
- final consensus assembly

---

# Running the Pipeline

## Example Input CSV

Isolate,Reads
AR_091,/path/to/AR_091.fastq.gz

---

## Example Run

nextflow run main.nf \
  -profile slurm \
  -c conf/uva.config \
  --input linelist.csv \
  --outdir results/test

---

# Rivanna Configuration

Example conf/uva.config

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

---

# Plassembler Database

If plassembler is enabled, a Plassembler database must be installed separately.

## Install Database

conda activate autocycler
plassembler download -d /path/to/plassembler_db

## Provide Database Path

--plassembler_db /path/to/plassembler_db

or in config:

params {
    plassembler_db = "/path/to/plassembler_db"
}

---

# Development Notes

Current priorities:
1. Stabilize assembly workflow
2. Add polishing
3. Add annotation
4. Add QC summaries
5. Add container support
6. Transition toward nf-core structure

---

# Design Philosophy

Autocycler is intentionally split into:
1. Draft assembly generation
2. Final consensus generation

This allows users to:
- inspect assemblies
- remove noisy assemblies
- modify weights
- rerun finalization only

---

# Useful Commands

## Resume

-resume

## Monitor Jobs

squeue -u $USER

## Inspect Logs

find work -name ".command.err"
find work -name ".command.out"

