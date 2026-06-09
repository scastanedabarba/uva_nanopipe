#!/bin/bash
set -euo pipefail

ISOLATE=""
ASSEMBLER=""
SAMPLE=""
READS=""
GENOME_SIZE_FILE=""
OUTDIR=""
THREADS=8
READ_TYPE="ont_r10"
PLASSEMBLER_DB_ARG="NONE"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate) ISOLATE="$2"; shift 2 ;;
        --assembler) ASSEMBLER="$2"; shift 2 ;;
        --sample) SAMPLE="$2"; shift 2 ;;
        --reads) READS="$2"; shift 2 ;;
        --genome-size) GENOME_SIZE_FILE="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        --threads) THREADS="$2"; shift 2 ;;
        --read-type) READ_TYPE="$2"; shift 2 ;;
        --plassembler-db) PLASSEMBLER_DB_ARG="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISOLATE" || -z "$ASSEMBLER" || -z "$SAMPLE" || -z "$READS" || -z "$GENOME_SIZE_FILE" || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument"
    exit 1
fi

if [[ ! -f "$READS" ]]; then
    echo "[ERROR] Reads file not found: $READS"
    exit 1
fi

if [[ ! -f "$GENOME_SIZE_FILE" ]]; then
    echo "[ERROR] Genome size file not found: $GENOME_SIZE_FILE"
    exit 1
fi

GENOME_SIZE=$(cat "$GENOME_SIZE_FILE")

if [[ "$GENOME_SIZE" == "NA" || -z "$GENOME_SIZE" ]]; then
    echo "[ERROR] Invalid genome size for ${ISOLATE}: $GENOME_SIZE"
    exit 1
fi

mkdir -p "$OUTDIR"

if [[ "$ASSEMBLER" == "plassembler" ]]; then
    if [[ "$PLASSEMBLER_DB_ARG" == "NONE" || -z "$PLASSEMBLER_DB_ARG" ]]; then
        echo "[ERROR] Plassembler selected but --plassembler-db was not provided."
        echo "[ERROR] Download the database with:"
        echo "        conda activate <assembly_env>"
        echo "        plassembler download -d /path/to/plassembler_db"
        echo "[ERROR] Then rerun with:"
        echo "        --plassembler_db /path/to/plassembler_db"
        exit 1
    fi

    if [[ ! -d "$PLASSEMBLER_DB_ARG" ]]; then
        echo "[ERROR] Provided Plassembler database path does not exist: $PLASSEMBLER_DB_ARG"
        exit 1
    fi

    export PLASSEMBLER_DB="$PLASSEMBLER_DB_ARG"
fi

autocycler helper "$ASSEMBLER" \
    --reads "$READS" \
    --out_prefix "$OUTDIR/${ASSEMBLER}_${SAMPLE}" \
    --threads "$THREADS" \
    --genome_size "$GENOME_SIZE" \
    --read_type "$READ_TYPE" \
    --min_depth_rel 0.1 \
    > "$OUTDIR/${ASSEMBLER}_${SAMPLE}.stdout" \
    2> "$OUTDIR/${ASSEMBLER}_${SAMPLE}.stderr"
