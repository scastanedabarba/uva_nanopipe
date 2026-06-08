# uva_nanopipe

`uva_nanopipe` is a developing Nanopore analysis pipeline. The current implemented step performs read filtering, read summary statistics, Raven-based genome size estimation, and coverage estimation for one or more isolates.

The pipeline is being developed first as modular bash scripts wrapped by Nextflow. The long-term goal is to transition the workflow toward a portable nf-core-style pipeline.

---

# Current status

Implemented:

- Single-isolate coverage script
- Command-line wrapper
- Conda environment for coverage step
- Initial Nextflow `COVERAGE` process
- SLURM execution through a UVA-specific config file

Not yet implemented:

- Summary/combine step
- Assembly step
- Containers
- nf-core template structure

---

# Repository structure

uva_nanopipe/
├── bin/
│   └── uva_nanopipe
├── scripts/
│   ├── coverage/
│   │   └── calculate_coverage.sh
│   └── assembly/
│       └── run_autocycler.sh
├── modules/
│   └── local/
│       └── coverage.nf
├── envs/
│   └── coverage.yml
├── conf/
│   └── uva.config
├── test_data/
├── main.nf
├── nextflow.config
└── README.md

---

# Coverage step

The current coverage workflow performs the following steps for each isolate:

1. Runs NanoStat before trimming
2. Filters reads with Chopper
3. Runs NanoStat after trimming
4. Downsamples reads for genome size estimation if needed
5. Estimates genome size using `autocycler helper genome_size`
6. Estimates coverage from total filtered bases and genome size

---

# Coverage outputs

Each isolate produces:

coverage.csv
read_filtering.csv
trimmed_reads/
genome_size/

Expected directory structure:

results/coverage/AR_353/
├── coverage.csv
├── read_filtering.csv
├── trimmed_reads/
│   ├── AR_353.trimmed.fastq.gz
│   ├── pre_trimming.nanostat.txt
│   └── post_trimming.nanostat.txt
└── genome_size/
    ├── AR_353.genome_size_reads.fastq.gz
    └── genome_size.txt

---

# coverage.csv columns

isolate,filtered_reads,total_bases,genome_size,coverage_est,min_read_depth,status

---

# Input CSV format

The current Nextflow workflow expects a CSV with the following columns:

Isolate,Reads
AR_353,/path/to/AR_353.fastq.gz

Example:

Isolate,Reads
AR_353,/project/som_infc_dis_mathers/genomics/nanopore/nanofilt_qc/20250515_rapidBac_GXB04608_Run027_v14/AR_353.fastq.gz

---

# Coverage Conda environment

The coverage process uses:

envs/coverage.yml

Create the environment manually:

module load miniforge

conda env create -f envs/coverage.yml

Activate:

conda activate uva_nanopipe_coverage

Test installed software:

which NanoStat
which chopper
which seqtk
which autocycler

Nextflow will automatically create and cache Conda environments when using a Conda-enabled profile.

No user-specific Conda cache directory is hardcoded into the pipeline.

Users who want to control Conda cache locations can set:

export NXF_CONDA_CACHEDIR=/path/to/cache

externally.

---

# Running the coverage script directly

Example direct execution:

./bin/uva_nanopipe coverage \
  --isolate AR_353 \
  --reads /path/to/AR_353.fastq.gz \
  --outdir results/coverage/AR_353 \
  --threads 4

---

# Running with Nextflow locally

Local execution is intended only for tiny test data.

Example:

nextflow run main.nf \
  -profile local \
  --input test_data/coverage_test.csv \
  --outdir results/test_local

---

# UVA/Rivanna configuration

The main `nextflow.config` should remain portable and should not include UVA-specific accounts, queues, usernames, or scratch paths.

UVA-specific SLURM settings should be stored in:

conf/uva.config

Create it with:

mkdir -p conf
nano conf/uva.config

Add:

process {
    executor = 'slurm'
    queue = 'standard'
    clusterOptions = '--account=amr_services_paid'
}

This tells Nextflow to:

- submit jobs through SLURM
- use the `standard` partition
- charge jobs to the `amr_services_paid` account

---

# Running with Nextflow on UVA/Rivanna

Example:

nextflow run /home/sgj4qr/github_repos/uva_nanopipe/main.nf \
  -profile slurm \
  -c /home/sgj4qr/github_repos/uva_nanopipe/conf/uva.config \
  --input linelist.csv \
  --outdir results/test_nextflow

Resume a previous run:

nextflow run /home/sgj4qr/github_repos/uva_nanopipe/main.nf \
  -profile slurm \
  -c /home/sgj4qr/github_repos/uva_nanopipe/conf/uva.config \
  --input linelist.csv \
  --outdir results/test_nextflow \
  -resume

---

# Monitoring jobs on Rivanna

Check submitted jobs:

squeue -u $USER

Check generated outputs:

find results/test_nextflow -maxdepth 4 -type f

Inspect task logs:

cat work/*/*/.command.err
cat work/*/*/.command.out
cat work/*/*/.command.log

Inspect generated SLURM directives:

grep -R "#SBATCH" work/*/*/.command.run

---

# Nextflow profiles

Profiles are stored in:

nextflow.config

Current profiles:

- local
- conda
- slurm
- apptainer

Run examples:

nextflow run main.nf -profile local

nextflow run main.nf -profile slurm

Future containerized execution:

nextflow run main.nf -profile apptainer

---

# Current Nextflow architecture

The workflow currently uses:

main.nf

which imports:

modules/local/coverage.nf

The actual bioinformatics logic remains in:

scripts/coverage/calculate_coverage.sh

This separation allows:

- easier debugging
- modular workflow development
- future nf-core transition
- container compatibility

---

# Development roadmap

Completed:

1. Refactor coverage script to run one isolate
2. Test coverage script manually
3. Create wrapper script
4. Test wrapper execution
5. Create coverage Conda environment
6. Convert coverage into a Nextflow process
7. Test coverage process with SLURM

Planned:

8. Add combine/summarize process
9. Add assembly placeholder
10. Implement assembly script
11. Convert assembly into a Nextflow process
12. Add Apptainer/Singularity containers
13. Add test datasets
14. Improve parameter/config handling
15. Move toward nf-core-style structure

---

# Notes

Current development prioritizes:

- modularity
- portability
- reproducibility
- separation of workflow orchestration from bioinformatics logic

The pipeline intentionally avoids:

- hardcoded usernames
- hardcoded scratch directories
- hardcoded Conda cache paths
- institution-specific assumptions in the default configuration

