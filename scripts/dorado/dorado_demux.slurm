#!/usr/bin/env bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=12:00:00
set -euo pipefail
(($#==2)) || { echo 'Usage: dorado_demux.slurm RUN_DIR DORADO_BIN' >&2;exit 2; }

RUN_DIR=$1
DORADO=$2
ROOT="${PIPELINE_ROOT:-/home/sgj4qr/github_repos/uva_nanopipe}"

[[ -f "$ROOT/scripts/dorado/mapping_to_manifest.py" ]] || {
    echo "ERROR: Cannot find mapping_to_manifest.py under $ROOT" >&2
    exit 1
}

module purge;module load miniforge;module use /project/som_infc_dis_mathers/modulefiles/;module load samtools
source "$RUN_DIR/preparation/preparation_config.sh"
[[ -f $RUN_DIR/basecalling/.basecalling_complete ]] || { echo 'Basecalling not complete' >&2;exit 1; }
INPUT="$RUN_DIR/basecalling/calls.demux_input.bam";MAP="$RUN_DIR/preparation/mapping.normalized.tsv"
[[ -s $INPUT && -s $MAP ]] || { echo 'Missing BAM or mapping' >&2;exit 1; }
OUT="$RUN_DIR/demux";READS="$OUT";mkdir -p "$OUT" "$RUN_DIR/qc";rm -f "$OUT/.demux_complete"
# Keep barcode classification independent from alias assignment; mapping TSV is authoritative.
# This permits changing sample assignments without redoing GPU basecalling.
rm -rf "$OUT/raw";mkdir -p "$OUT/raw"
"$DORADO" demux --output-dir "$OUT/raw" --kit-name "$KIT_NAME" --emit-fastq --emit-summary --threads "${SLURM_CPUS_PER_TASK:-8}" "$INPUT" 2> "$OUT/demux.log"
python3 - "$MAP" "$OUT/raw" "$OUT" <<'PY2'
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
python3 - "$MAP" "$OUT" "$READS" "$DORADO" "$KIT_NAME" "${SLURM_CPUS_PER_TASK:-8}" "$RUN_DIR/qc/trim_summary.tsv" <<'PY2'
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
# Preserve demux summaries, logs and raw reads for inspection; cleanup can be done manually.
touch "$OUT/.demux_complete"
echo "Final FASTQs: $READS";echo "Manifest: $RUN_DIR/prep_input.csv";echo "Extended manifest: $RUN_DIR/prep_input_extended.csv"

