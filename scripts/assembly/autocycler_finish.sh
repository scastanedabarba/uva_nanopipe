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

mkdir -p "$OUTDIR"
cd "$OUTDIR"

echo "[INFO] Running Autocycler finish steps for ${ISOLATE}"

autocycler compress \
    -i "$ASSEMBLIES" \
    -a autocycler_out \
    2>> autocycler.stderr

autocycler cluster \
    -a autocycler_out \
    2>> autocycler.stderr

for c in autocycler_out/clustering/qc_pass/cluster_*; do
    autocycler trim -c "$c" 2>> autocycler.stderr
    autocycler resolve -c "$c" 2>> autocycler.stderr
done

autocycler combine \
    -a autocycler_out \
    -i autocycler_out/clustering/qc_pass/cluster_*/5_final.gfa \
    2>> autocycler.stderr

echo "[INFO] Autocycler finish complete for ${ISOLATE}"
