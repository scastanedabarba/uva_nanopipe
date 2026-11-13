#!/usr/bin/env bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=12:00:00
set -euo pipefail
(($#==4)) || { echo 'Usage: dorado_demux.slurm RUN_DIR DORADO_BIN RUN_NAME PIPELINE_ROOT' >&2;exit 2; }

RUN_DIR=$1
DORADO=$2
RUN=$3
ROOT=$4

[[ -f "$ROOT/scripts/dorado/mapping_to_manifest.py" ]] || {
    echo "ERROR: Cannot find mapping_to_manifest.py under $ROOT" >&2
    exit 1
}

module purge;module load miniforge;module use /project/som_infc_dis_mathers/modulefiles/;module load samtools
source "$RUN_DIR/basecalling/$RUN/work/preparation/preparation_config.sh"
[[ -f $RUN_DIR/basecalling/$RUN/.basecalling_complete ]] || { echo 'Basecalling not complete' >&2;exit 1; }
INPUT="$RUN_DIR/basecalling/$RUN/demux_input.bam";MAP="$RUN_DIR/basecalling/$RUN/work/preparation/mapping.normalized.tsv"
[[ -s $INPUT && -s $MAP ]] || { echo 'Missing BAM or mapping' >&2;exit 1; }
OUT="$RUN_DIR/demux/$RUN";READS="$OUT";SUM="$RUN_DIR/summary/$RUN";mkdir -p "$OUT/work" "$SUM" "$RUN_DIR/versions";rm -f "$OUT/.demux_complete"
# Keep barcode classification independent from alias assignment; mapping TSV is authoritative.
# This permits changing sample assignments without redoing GPU basecalling.
rm -rf "$OUT/work/raw";mkdir -p "$OUT/work/raw"
"$DORADO" demux --output-dir "$OUT/work/raw" --kit-name "$KIT_NAME" --emit-fastq --emit-summary --threads "${SLURM_CPUS_PER_TASK:-8}" "$INPUT" 2> "$OUT/demux.log"
python3 - "$MAP" "$OUT/work/raw" "$OUT" <<'PY2'
import csv,re,sys,shutil
from pathlib import Path
mapping,source,out=map(Path,sys.argv[1:]);rows=list(csv.DictReader(mapping.open(),delimiter='\t'))
files=sorted(source.rglob('*.fastq')); used=set()
if not files:sys.exit('ERROR: Dorado demux produced no FASTQs')
for row in rows:
 barcode=row['barcode']; isolate=row['isolate']
 # Dorado filenames include the kit and barcode token; match exact barcode boundary.
 rx=re.compile(r'(?<![A-Za-z0-9])'+re.escape(barcode)+r'(?![A-Za-z0-9])',re.I)
 matches=[f for f in files if rx.search(f.stem)]
 if not matches:sys.exit(f'ERROR: No FASTQ for {barcode} ({isolate})')
 if any(f in used for f in matches):sys.exit(f'ERROR: FASTQ assigned to multiple isolates: {barcode}')
 with (out/(isolate+'.fastq')).open('wb') as dest:
  for f in matches:
   with f.open('rb') as src:shutil.copyfileobj(src,dest)
 used.update(matches)
remaining=[f for f in files if f not in used]
if remaining:
 print(f'INFO: Skipping {len(remaining)} FASTQ files not assigned in the mapping:', file=sys.stderr)
 for f in remaining:
  print(f'  {f.relative_to(source)}', file=sys.stderr)
PY2
# Dorado trim after demux, as in the validated worker. Write compressed output atomically.
python3 - "$MAP" "$OUT" "$READS" "$DORADO" "$KIT_NAME" "${SLURM_CPUS_PER_TASK:-8}" "$SUM/$RUN.trim_summary.tsv" <<'PY2'
import csv,gzip,subprocess,sys
from pathlib import Path
mapping,demux,reads,dorado,kit,threads,summary=sys.argv[1:]
rows=list(csv.DictReader(open(mapping),delimiter='\t'))
with open(summary,'w',newline='') as sh:
 w=csv.writer(sh,delimiter='\t');w.writerow(['isolate','input_reads','input_bases','trimmed_reads','trimmed_bases'])
 for row in rows:
  isolate=row['isolate'];src=Path(demux)/(isolate+'.fastq');target=Path(reads)/(isolate+'.fastq.gz');tmp=Path(str(target)+'.tmp')
  def metrics(path,compressed=False):
   op=gzip.open if compressed else open
   with op(path,'rt') as f:
    reads=bases=0
    for idx,line in enumerate(f):
     if idx%4==1:reads+=1;bases+=len(line.rstrip('\r\n'))
   return reads,bases
  ir,ib=metrics(src)
  with tmp.open('wb') as raw:
   with subprocess.Popen([dorado,'trim','--threads',threads,'--sequencing-kit',kit,'--emit-fastq',str(src)],stdout=subprocess.PIPE) as proc:
    with gzip.GzipFile(fileobj=raw,mode='wb') as gz:
     while True:
      data=proc.stdout.read(1024*1024)
      if not data:break
      gz.write(data)
    rc=proc.wait()
    if rc:tmp.unlink(missing_ok=True);sys.exit(f'ERROR: dorado trim failed for {isolate} rc={rc}')
  tr,tb=metrics(tmp,True)
  if ir!=tr or not tr:tmp.unlink(missing_ok=True);sys.exit(f'ERROR: invalid trimmed FASTQ for {isolate}')
  tmp.replace(target);w.writerow([isolate,ir,ib,tr,tb])
PY2
python3 "$ROOT/scripts/dorado/mapping_to_manifest.py" --mapping "$MAP" --outdir "$RUN_DIR" --reads-dir "$READS" --require-reads
# Preserve every intermediate; relocate uncompressed isolate FASTQs to work/.
mkdir -p "$OUT/work/intermediate"
find "$OUT" -maxdepth 1 -type f -name '*.fastq' -exec mv -t "$OUT/work/intermediate" {} +
# Retain unexpected and unclassified barcode FASTQs at top level, compressed.
find "$OUT" -maxdepth 1 -type f -name "barcode*.fastq.gz" -delete
rm -f "$OUT/unclassified.fastq.gz"
python3 "$ROOT/scripts/dorado/barcode_qc.py" --mapping "$MAP" --raw "$OUT/work/raw" --outdir "$OUT" --summary "$SUM" --run "$RUN"
{
 printf 'dorado demux --output-dir %q --kit-name %q --emit-fastq --emit-summary --threads %q %q\n' "$OUT/work/raw" "$KIT_NAME" "${SLURM_CPUS_PER_TASK:-8}" "$INPUT"
 printf 'dorado trim --threads %q --sequencing-kit %q --emit-fastq <isolate.fastq>\n' "${SLURM_CPUS_PER_TASK:-8}" "$KIT_NAME"
} > "$OUT/demux.commands.txt"
# PycoQC is nonfatal: record exit code and retain stderr.
PYCOQC_RC=0
if module load pycoqc; then
  pycoQC -f "$RUN_DIR/basecalling/$RUN/duplex_summary.tsv" --min_pass_qual 10 --min_pass_len 1000 -o "$SUM/$RUN.pycoqc.html" -j "$SUM/$RUN.pycoqc.json" 2> "$SUM/$RUN.pycoqc.log" || PYCOQC_RC=$?
else
  PYCOQC_RC=127
  echo 'pycoqc module unavailable' > "$SUM/$RUN.pycoqc.log"
fi
printf 'run_name\tpycoqc_status\tpycoqc_exit_code\n%s\t%s\t%s\n' "$RUN" "$( ((PYCOQC_RC==0)) && echo SUCCESS || echo FAILED )" "$PYCOQC_RC" > "$SUM/$RUN.pycoqc_status.tsv"
{
 printf 'run_name=%s\n' "$RUN"
 printf 'uvanano_pipe_version=%s\n' "$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)"
 printf 'uvanano_pipe_commit=%s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
 printf 'dorado_version=%s\n' "$("$DORADO" --version 2>&1 | head -1)"
 printf 'samtools_version=%s\n' "$(samtools --version | head -1)"
 printf 'pycoqc_version=%s\n' "$(pycoQC --version 2>&1 | head -1 || echo unavailable)"
 printf 'barcode_kit=%s\n' "$KIT_NAME"
 printf 'pycoqc_min_pass_qual=10\npycoqc_min_pass_len=1000\n'
 cat "$RUN_DIR/basecalling/$RUN/models_used.txt"
} > "$RUN_DIR/basecalling/$RUN/basecalling_demux.versions.txt"
cp "$RUN_DIR/basecalling/$RUN/basecalling_demux.versions.txt" "$RUN_DIR/versions/$RUN.basecalling_demux.versions.txt"
# Generate a stable run-level QC summary.
python3 "$ROOT/scripts/dorado/run_summary.py" "$RUN" "$SUM"
# Preserve demux summaries, logs and raw reads for inspection.
touch "$OUT/.demux_complete"
echo "Final FASTQs: $READS";echo "Manifest: $RUN_DIR/prep_input.csv";echo "Extended manifest: $RUN_DIR/prep_input_extended.csv"

