#!/bin/bash
set -euo pipefail

ISOLATE=""
ASSEMBLIES=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --isolate) ISOLATE="$2"; shift 2 ;;
        --assemblies) ASSEMBLIES="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISOLATE" || -z "$ASSEMBLIES" || -z "$OUTDIR" ]]; then
    echo "[ERROR] Missing required argument"
    exit 1
fi

if [[ ! -d "$ASSEMBLIES" ]]; then
    echo "[ERROR] Assemblies directory not found: $ASSEMBLIES"
    exit 1
fi

ASSEMBLIES=$(readlink -f "$ASSEMBLIES")

mkdir -p "$OUTDIR"
cd "$OUTDIR"

echo "[INFO] Running Autocycler finish steps for ${ISOLATE}"
echo "[INFO] Assemblies directory: $ASSEMBLIES"

n_assemblies=$(find "$ASSEMBLIES" -name "*.fasta" -type f | wc -l)

if [[ "$n_assemblies" -eq 0 ]]; then
    echo "[ERROR] No FASTA assemblies found in: $ASSEMBLIES" >&2
    exit 1
fi

echo "[INFO] Found $n_assemblies FASTA assemblies"

autocycler compress \
    -i "$ASSEMBLIES" \
    -a autocycler_out \
    >> autocycler.stdout \
    2>> autocycler.stderr

autocycler cluster \
    -a autocycler_out \
    >> autocycler.stdout \
    2>> autocycler.stderr

shopt -s nullglob
clusters=(autocycler_out/clustering/qc_pass/cluster_*)
shopt -u nullglob

if [[ ${#clusters[@]} -eq 0 ]]; then
    echo "[ERROR] No Autocycler QC-pass clusters found" >&2
    exit 1
fi

for c in "${clusters[@]}"; do
    autocycler trim -c "$c" \
        >> autocycler.stdout \
        2>> autocycler.stderr

    autocycler resolve -c "$c" \
        >> autocycler.stdout \
        2>> autocycler.stderr
done

autocycler combine \
    -a autocycler_out \
    -i autocycler_out/clustering/qc_pass/cluster_*/5_final.gfa \
    >> autocycler.stdout \
    2>> autocycler.stderr

echo "[INFO] Autocycler finish complete for ${ISOLATE}"
