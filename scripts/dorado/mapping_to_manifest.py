#!/usr/bin/env python3
"""Validate barcode mapping, emit canonical mapping and assembly manifests."""
import argparse,csv,re,sys
from pathlib import Path
ap=argparse.ArgumentParser()
ap.add_argument('--mapping',required=True); ap.add_argument('--outdir',required=True)
ap.add_argument('--reads-dir'); ap.add_argument('--require-reads',action='store_true')
a=ap.parse_args(); out=Path(a.outdir).resolve();out.mkdir(parents=True,exist_ok=True)
with open(a.mapping,encoding='utf-8-sig',newline='') as fh:
 reader=csv.DictReader(fh,delimiter='\t'); required=['barcode','isolate','r1','r2']
 if reader.fieldnames!=required: sys.exit('ERROR: mapping TSV header must be exactly: '+ '\t'.join(required))
 rows=list(reader)
if not rows:sys.exit('ERROR: empty mapping')
barcodes=set();isolates=set();clean=[]
for n,row in enumerate(rows,2):
 if None in row:sys.exit(f'ERROR: extra columns on row {n}')
 b,i,r1,r2=[(row[k] or '').strip() for k in required]
 if not re.fullmatch(r'barcode\d{2,3}',b):sys.exit(f'ERROR: invalid barcode row {n}: {b}')
 if not re.fullmatch(r'[A-Za-z0-9._-]+',i) or i.lower()=='unclassified':sys.exit(f'ERROR: invalid isolate row {n}: {i}')
 if b in barcodes or i in isolates:sys.exit(f'ERROR: duplicate barcode/isolate row {n}')
 barcodes.add(b);isolates.add(i)
 r1='' if r1.upper() in ('NA','NONE','') else r1
 r2='' if r2.upper() in ('NA','NONE','') else r2
 if bool(r1)!=bool(r2):sys.exit(f'ERROR: R1/R2 must both be present or absent for {i}')
 for label,value in [('R1',r1),('R2',r2)]:
  if value:
   path=Path(value).expanduser().resolve()
   if not path.is_file():sys.exit(f'ERROR: {label} not found for {i}: {path}')
   if not path.name.endswith(('.fastq.gz','.fq.gz','.fastq','.fq')):sys.exit(f'ERROR: {label} not FASTQ for {i}: {path}')
   if label=='R1':r1=str(path)
   else:r2=str(path)
 if r1 and r1==r2:sys.exit(f'ERROR: identical R1/R2 for {i}')
 clean.append(dict(barcode=b,isolate=i,r1=r1,r2=r2))
with (out/'mapping.normalized.tsv').open('w',newline='') as fh:
 w=csv.DictWriter(fh,fieldnames=required,delimiter='\t',lineterminator='\n');w.writeheader();w.writerows(clean)
if a.reads_dir:
 reads=Path(a.reads_dir).resolve()
 with (out/'assembly_input.csv').open('w',newline='') as fh1, (out/'assembly_input_extended.csv').open('w',newline='') as fh2:
  basic=csv.writer(fh1);extended=csv.writer(fh2);basic.writerow(['Isolate','Reads']);extended.writerow(['Isolate','Reads','R1','R2'])
  for row in clean:
   fastq=reads/(row['isolate']+'.fastq.gz')
   if a.require_reads and (not fastq.is_file() or fastq.stat().st_size==0):sys.exit(f'ERROR: missing trimmed reads for {row["isolate"]}: {fastq}')
   basic.writerow([row['isolate'],str(fastq)]);extended.writerow([row['isolate'],str(fastq),row['r1'] or 'NA',row['r2'] or 'NA'])
print(f'Validated {len(clean)} isolates')
