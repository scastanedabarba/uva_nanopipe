#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash bin/run_dorado.sh \
    --pod5-dir DIR --run-name NAME --mapping TSV \
    --kit SQK-RBK114-24 --outdir DIR \
    [--account ACCOUNT] [--partition PARTITION] [--dry-run]

Mapping TSV header: barcode<TAB>isolate<TAB>r1<TAB>r2
Use NA in both r1 and r2 if short reads are unavailable.
Dorado paths are configured in conf/dorado.config.sh.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 2; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_FILE="${DORADO_CONFIG:-$ROOT/conf/dorado.config.sh}"
[[ -f "$CONFIG_FILE" ]] || die "Configuration not found: $CONFIG_FILE"
# shellcheck source=/dev/null
source "$CONFIG_FILE"
: "${DORADO_BIN:?Set DORADO_BIN in conf/dorado.config.sh}"
: "${DORADO_MODEL:?Set DORADO_MODEL in conf/dorado.config.sh}"

# Existing Slurm scripts take MODELS_DIR, not the model path.
# Both the SUP and stereo models must be discoverable in this directory.
MODELS_DIR=$(dirname "$DORADO_MODEL")

POD5='' RUN='' MAPPING='' KIT='' OUTDIR=''
ACCOUNT='som_infc_dis_mathers' PARTITION='standard' DRY=0
while (($#)); do
  case "$1" in
    --pod5-dir|--run-name|--mapping|--kit|--outdir|--account|--partition)
      (($# >= 2)) || die "Missing value for $1"
      opt=$1; val=$2; shift 2
      case "$opt" in
        --pod5-dir) POD5=$val;;
        --run-name) RUN=$val;;
        --mapping) MAPPING=$val;;
        --kit) KIT=$val;;
        --outdir) OUTDIR=$val;;
        --account) ACCOUNT=$val;;
        --partition) PARTITION=$val;;
      esac
      ;;
    --dry-run) DRY=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

[[ -n "$POD5" && -n "$RUN" && -n "$MAPPING" && -n "$KIT" && -n "$OUTDIR" ]] || { usage >&2; exit 2; }
[[ "$RUN" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid run name: $RUN"
[[ -d "$POD5" ]] || die "POD5 directory not found: $POD5"
[[ -f "$MAPPING" ]] || die "Mapping TSV not found: $MAPPING"
[[ -x "$DORADO_BIN" ]] || die "Dorado executable not found: $DORADO_BIN"
[[ -d "$DORADO_MODEL" ]] || die "SUP model directory not found: $DORADO_MODEL"
[[ "$(basename "$DORADO_MODEL")" == 'dna_r10.4.1_e8.2_400bps_sup@v5.2.0' ]] || die 'The existing Slurm scripts require SUP model v5.2.0 at the standard directory name.'

# Existing preparation script requires a stereo model under MODELS_DIR.
if ! find "$MODELS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'dna_r10.4.1_e8.2_5khz_stereo@*' -print -quit | grep -q .; then
  die "No named stereo model directory found under $MODELS_DIR. Check the existing '1.4.0' directory before running."
fi

POD5=$(realpath "$POD5")
MAPPING=$(realpath "$MAPPING")
DORADO_BIN=$(realpath "$DORADO_BIN")
MODELS_DIR=$(realpath "$MODELS_DIR")
mkdir -p "$OUTDIR"
RUN_DIR=$(realpath "$OUTDIR")
mkdir -p "$RUN_DIR/logs" "$RUN_DIR/preparation"

# Validate and normalize the mapping before submitting any jobs.
python3 "$ROOT/scripts/dorado/mapping_to_manifest.py" \
  --mapping "$MAPPING" --outdir "$RUN_DIR/preparation"
MAPPING="$RUN_DIR/preparation/mapping.normalized.tsv"

# Record the exact configuration used for this run.
{
  printf 'DORADO_BIN=%q\n' "$DORADO_BIN"
  printf 'DORADO_MODEL=%q\n' "$DORADO_MODEL"
  printf 'MODELS_DIR=%q\n' "$MODELS_DIR"
} > "$RUN_DIR/preparation/dorado_config_used.sh"

printf 'Run directory: %s\nDorado: %s\nSUP model: %s\nModels directory: %s\n' \
  "$RUN_DIR" "$DORADO_BIN" "$DORADO_MODEL" "$MODELS_DIR"
if ((DRY)); then
  echo 'DRY RUN: prepare (CPU) -> basecall (GPU) -> demux/trim (CPU)'
  exit 0
fi
command -v sbatch >/dev/null 2>&1 || die 'sbatch not found'

prep=$(sbatch --parsable \
  --account="$ACCOUNT" --partition="$PARTITION" \
  --job-name="dprep_${RUN}" \
  --output="$RUN_DIR/logs/prepare.%j.out" \
  --error="$RUN_DIR/logs/prepare.%j.err" \
  "$ROOT/scripts/dorado/dorado_prepare.slurm" \
  "$POD5" "$RUN_DIR" "$MAPPING" "$KIT" "$DORADO_BIN" "$MODELS_DIR")

base=$(sbatch --parsable \
  --dependency="afterok:${prep%%;*}" --account="$ACCOUNT" \
  --job-name="dbc_${RUN}" \
  --output="$RUN_DIR/logs/basecall.%j.out" \
  --error="$RUN_DIR/logs/basecall.%j.err" \
  "$ROOT/scripts/dorado/dorado_basecall.slurm" \
  "$RUN_DIR" "$DORADO_BIN" "$MODELS_DIR")

demux=$(sbatch --parsable \
  --dependency="afterok:${base%%;*}" \
  --account="$ACCOUNT" --partition="$PARTITION" \
  --job-name="ddemux_${RUN}" \
  --output="$RUN_DIR/logs/demux.%j.out" \
  --error="$RUN_DIR/logs/demux.%j.err" \
  "$ROOT/scripts/dorado/dorado_demux.slurm" \
  "$RUN_DIR" "$DORADO_BIN")

printf 'Preparation job: %s\nBasecalling job: %s\nDemultiplexing job: %s\n' \
  "$prep" "$base" "$demux"

