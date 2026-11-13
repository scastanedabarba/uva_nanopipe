# UVA NanoPipe

UVA NanoPipe is a modular Oxford Nanopore bacterial genome assembly workflow. Basecalling is handled by the existing Dorado/SLURM scripts; preparation and assembly are independently executable Nextflow DSL2 stages. Each stage can accept user-supplied inputs, so no preceding stage is required.

## Stages and handoffs

| Stage | Input | Generated handoff | Other outputs |
| --- | --- | --- | --- |
| Basecalling (Dorado scripts) | POD5 and barcode mapping | `prep_input.csv` | FASTQs; optional `prep_input_extended.csv` |
| Preparation (`--step prep`) | `Isolate,Reads` CSV (generated or user supplied) | `summary/assembly_input.csv` | `summary/coverage.csv`, `summary/read_filtering.csv`, per-isolate filtered FASTQs and genome-size estimates |
| Assembly (`--step assembly`) | `Isolate,Reads,GenomeSize,MinReadDepth,Assemble` CSV (generated or user supplied) | none | Autocycler results; `summary/autocycler_assembly_summary.tsv`; `assembly/assembly_parameters_used.csv` |

The basecalling workflow now writes `prep_input.csv` rather than the previously named `assembly_input.csv`. Its two-column manifest points to the reads produced by Dorado. Users who basecall externally can provide the same two-column CSV themselves.

## Dorado basecalling and demultiplexing output (run-scoped)

Launch using `bash bin/run_dorado.sh --pod5-dir ... --run-name RUN_NAME --mapping mapping.tsv --kit SQK-RBK114-24 --outdir OUTDIR`. The three dependent SLURM jobs retain their existing prepare → basecall → demux order. The `--outdir` is a shared output root, **not** a per-run directory.

```text
OUTDIR/
  basecalling/RUN_NAME/
    duplex.bam                  # full merged simplex/duplex BAM
    demux_input.bam             # dx:0 and dx:1 only
    duplex_summary.tsv
    models_used.txt
    read_groups.tsv
    basecalling.commands.txt
    basecalling_demux.versions.txt
    work/                       # channel split, batch lists, chunks, failed batches
  demux/RUN_NAME/
    ISOLATE.fastq.gz            # trimmed and ready for prep
    barcodeXX.fastq.gz          # unexpected assignments, if any
    unclassified.fastq.gz       # unclassified, if any
    demux.commands.txt
    demux.log
    work/raw/                   # original Dorado barcode FASTQs and summary
    work/intermediate/          # uncompressed isolate FASTQs
  summary/RUN_NAME/
    RUN_NAME.duplex_metrics.tsv
    RUN_NAME.barcode_summary.tsv
    RUN_NAME.demux_summary.tsv
    RUN_NAME.trim_summary.tsv
    RUN_NAME.pycoqc.html
    RUN_NAME.pycoqc.json
    RUN_NAME.pycoqc.log
    RUN_NAME.pycoqc_status.tsv
    RUN_NAME.basecalling_summary.tsv
  versions/RUN_NAME.basecalling_demux.versions.txt
  prep_input.csv
  prep_input_extended.csv
```

All run-specific QC filenames have the run prefix, enabling later cross-run aggregation. Tabular QC outputs include a `run_name` field except `trim_summary.tsv` and the metric/value duplex file; those are stored in run-scoped directories and identified by filename. The combined version file in `versions/` is an exact copy of the one in `basecalling/RUN_NAME/`.

**Retention:** No automatic intermediate cleanup. The raw Dorado demultiplexed FASTQs, per-batch BAMs, channel splits, and uncompressed intermediate FASTQs are retained. Rerunning a stage may regenerate/replace its working outputs; use unique output roots for independent analyses.

**QC:** Duplex read and base counts are computed from `dx` tags in the full BAM; duplex rate is `2*dx1_reads/(dx0_reads+dx_minus1_reads)*100`, and duplex base fraction is `dx1_bases/(dx0_bases+dx1_bases)*100`. PycoQC is run with `--min_pass_qual 10 --min_pass_len 1000`; its failure is nonfatal and logged in `RUN_NAME.pycoqc_status.tsv`. Barcode assignment summaries use untrimmed raw demultiplexed FASTQs as the denominator and distinguish expected, unexpected, and unclassified assignments.

**Handoff:** `prep_input.csv` includes only mapped isolates and absolute paths to `demux/RUN_NAME/ISOLATE.fastq.gz`. Because the manifest lives at the shared output root, it describes the most recently completed demultiplexing run; archive it before running another run to the same root.

## Preparation input

Create a CSV containing FASTQ paths:

```csv
Isolate,Reads
AR_091,/data/AR_091.fastq.gz
AR_092,/data/AR_092.fastq.gz
```

Use unique isolate IDs consisting of letters, numbers, dots, hyphens, or underscores. Provide absolute FASTQ paths for portability. Reads may come from UVA NanoPipe basecalling or any other workflow. Preparation performs NanoStat read statistics, Chopper filtering (Q10, minimum length 1000 bp), Raven/Autocycler genome-size estimation, and estimated depth calculation.

```bash
nextflow run /home/sgj4qr/github_repos/uva_nanopipe/main.nf \
  -profile slurm \
  --step prep \
  --input /path/to/prep_input.csv \
  --outdir /scratch/sgj4qr/nanopore_run
```

Review the generated files before assembly:

```text
nanopore_run/
├── coverage/
│   ├── AR_091/
│   │   ├── trimmed_reads/AR_091.trimmed.fastq.gz
│   │   ├── genome_size/genome_size.txt
│   │   ├── coverage.csv
│   │   └── read_filtering.csv
│   └── AR_092/...
└── summary/
    ├── coverage.csv
    ├── read_filtering.csv
    └── assembly_input.csv
```

### Coverage summary and warnings

`summary/coverage.csv` reports filtered reads, filtered total bases, estimated genome size, estimated coverage, the pipeline's proposed minimum read depth, and `status`.

- `LOW_TOTAL_BASES`: fewer than 100,000,000 filtered bases (100 Mbp).
- `LOW_GENOME_SIZE`: estimated genome size below 1,000,000 bp. Researchers should also verify that *any* predicted genome size matches the expected organism.
- `LOW_COVERAGE`: estimated depth below 25×.
- Multiple warnings are joined with semicolons, e.g. `LOW_TOTAL_BASES;LOW_COVERAGE`.
- `OK`: no warnings and processing succeeded.
- `READS_NOT_FOUND`, `TRIMMED_READS_EMPTY`, `GENOME_SIZE_FAILED`: processing failures. These isolates remain in the manifest but default to `Assemble=false`.

Thresholds are strict: exactly 100 Mbp, 1 Mbp, or 25× does not trigger a warning. These are screening warnings, **not** a species-aware quality assessment or an automatic assembly exclusion. `read_filtering.csv` retains its existing computational-status semantics.

The existing Autocycler minimum-depth selection is unchanged: when estimated coverage is below 25×, the proposed `MinReadDepth` is 10; otherwise it is 25. This parameter is a *minimum subsample depth*, not a cap on the sequencing depth Autocycler may use. A 10× fallback does not imply that low-depth assembly will be reliable.

## Assembly input

Preparation generates an editable `summary/assembly_input.csv`:

```csv
Isolate,Reads,GenomeSize,MinReadDepth,Assemble
AR_091,/absolute/path/to/AR_091.trimmed.fastq.gz,5100000,25,true
AR_092,/absolute/path/to/AR_092.trimmed.fastq.gz,4200000,10,true
AR_093,,NA,,false
```

All isolates remain in the manifest. Processing successes (including QC warnings) default to `true`; processing failures default to `false`. Researchers can change `Assemble` to `false` to skip an isolate, or to `true` after correcting missing inputs. For `Assemble=true`, the FASTQ path must exist, `GenomeSize` must be a positive integer (bp), and `MinReadDepth` must be a positive integer. `MinReadDepth` defaults to 25 if omitted or blank in a user-created assembly manifest; `Assemble` defaults to `true` if omitted or blank. For `Assemble=false`, other values may be blank or `NA`.

**The assembly stage accepts a manually created CSV of exactly this format.** It does not require that the preparation stage was run or that QC summary files exist. Researchers entering directly at assembly are responsible for their own read QC and filtering. The supplied genome size and minimum read depth are authoritative; the pipeline does not silently replace them with previous estimates.

```bash
nextflow run /home/sgj4qr/github_repos/uva_nanopipe/main.nf \
  -profile slurm \
  --step assembly \
  --input /scratch/sgj4qr/nanopore_run/summary/assembly_input.csv \
  --outdir /scratch/sgj4qr/nanopore_run
```

The original input manifest (including skipped rows) is copied to `assembly/assembly_parameters_used.csv` at execution. Keep the input CSV and run directory for reproducibility; a subsequent run into the same output directory can overwrite this record, so use separate output directories for distinct runs.

### Existing Autocycler behavior

Assembly still runs `autocycler subsample`, four subsamples (`sample_01` through `sample_04`), the configured assemblers, assembly weighting, and Autocycler compress/cluster/trim/resolve/combine. The subsampling script and underlying assembly algorithms are unchanged. The default assemblers are Raven, Miniasm, Flye, metaMDBG, NECAT, NextDenovo, Plassembler, and Canu. The Plassembler database must be supplied with `--plassembler_db` when Plassembler is selected. Check the installed Autocycler version and its subsampling behavior before changing the minimum-depth policy.

## Execution environments

The `local`, `slurm`, and `apptainer` profiles are defined in `nextflow.config`. SLURM requires an appropriate partition and account for your site. For example, add to your local `slurm` profile:

```groovy
process.queue = 'standard'
process.clusterOptions = '--account=amr_services_paid'
```

These values are site-specific, not portable defaults. The assembly modules currently use the Rivanna-specific Autocycler Conda environment at `/scratch/sgj4qr/pgcoe_nanopore/autocycler`; configure that environment for your installation. Preparation uses `envs/coverage.yml`.

Nextflow `-resume` can reuse cached tasks when their inputs and code have not changed. Moving from preparation to assembly does **not** require `-resume`; the stages are separate invocations with explicit manifests.

## Development and testing

Before processing a cohort, test one isolate through both stages, inspect the summary files, and verify that a manually created assembly manifest can run without any preparation directory. The code has not been end-to-end tested on SLURM as part of this update.
