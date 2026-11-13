#!/usr/bin/env python3
"""Summarize raw Dorado barcode assignments, retain unmapped FASTQs compressed."""
import argparse,csv,gzip,re,shutil
from pathlib import Path
ap=argparse.ArgumentParser()
for arg in ('mapping','raw','outdir','summary','run'): ap.add_argument('--'+arg,required=True)
a=ap.parse_args(); raw=Path(a.raw); out=Path(a.outdir); summary=Path(a.summary)
rows=list(csv.DictReader(open(a.mapping),delimiter='\t'))
lookup={r['barcode'].lower():r['isolate'] for r in rows}
records=[]; assigned=set()
files=sorted(raw.rglob('*.fastq'))
if not files: raise SystemExit('No raw demux FASTQs for barcode QC')
for path in files:
    matches=re.findall(r'(?<![A-Za-z0-9])(barcode\d{2,3})(?![A-Za-z0-9])',path.stem,re.I)
    barcode=matches[-1].lower() if matches else 'unclassified'
    category='expected' if barcode in lookup else ('unclassified' if barcode=='unclassified' else 'unexpected')
    n=b=0
    with path.open() as fh:
        for i,line in enumerate(fh):
            if i%4==1: n+=1;b+=len(line.rstrip('\r\n'))
    records.append(dict(run_name=a.run,barcode=barcode,isolate=lookup.get(barcode,'NA'),category=category,reads=n,bases=b))
    if category!='expected':
        target=out/(barcode+'.fastq.gz')
        if target.exists():
            # Multiple raw files can represent the same barcode; append gzip members safely.
            mode='ab'
        else: mode='wb'
        with target.open(mode) as dest, gzip.GzipFile(fileobj=dest,mode='wb') as gz, path.open('rb') as src:
            shutil.copyfileobj(src,gz)
    assigned.add(barcode)
for barcode,isolate in lookup.items():
    if barcode not in assigned: records.append(dict(run_name=a.run,barcode=barcode,isolate=isolate,category='expected',reads=0,bases=0))
total_reads=sum(x['reads'] for x in records);total_bases=sum(x['bases'] for x in records)
for r in records:
    r['read_pct']=round(100*r['reads']/total_reads,4) if total_reads else 'NA'
    r['base_pct']=round(100*r['bases']/total_bases,4) if total_bases else 'NA'
fields=['run_name','barcode','isolate','category','reads','bases','read_pct','base_pct']
with (summary/(a.run+'.barcode_summary.tsv')).open('w',newline='') as fh:
    w=csv.DictWriter(fh,fieldnames=fields,delimiter='\t');w.writeheader();w.writerows(records)
with (summary/(a.run+'.demux_summary.tsv')).open('w',newline='') as fh:
    w=csv.writer(fh,delimiter='\t');w.writerow(['run_name','category','reads','bases','read_pct','base_pct'])
    for cat in ('expected','unexpected','unclassified','total'):
        subset=records if cat=='total' else [r for r in records if r['category']==cat]
        n=sum(r['reads'] for r in subset);b=sum(r['bases'] for r in subset)
        w.writerow([a.run,cat,n,b,round(100*n/total_reads,4) if total_reads else 'NA',round(100*b/total_bases,4) if total_bases else 'NA'])
