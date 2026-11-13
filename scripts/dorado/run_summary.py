#!/usr/bin/env python3
"""Create stable, flat run-level QC from PycoQC JSON and duplex metrics."""
import csv,json,sys
from pathlib import Path
run=sys.argv[1]; directory=Path(sys.argv[2]); metrics={'run_name':run}
path=directory/(run+'.pycoqc.json')
if path.exists():
    try:
        data=json.loads(path.read_text())
        for label,section in [('all','All Reads'),('pass','Pass Reads')]:
            for key in ('run_duration','active_channels'):
                metrics[f'{label}_{key}']=data.get(section,{}).get('run',{}).get(key,'NA')
            for key in ('reads_number','bases_number','N50'):
                metrics[f'{label}_{key}']=data.get(section,{}).get('basecall',{}).get(key,'NA')
    except (ValueError,OSError): metrics['pycoqc_parse_status']='FAILED'
with (directory/(run+'.duplex_metrics.tsv')).open() as fh:
    for row in csv.DictReader(fh,delimiter='\t'): metrics[row['metric']]=row['value']
with (directory/(run+'.basecalling_summary.tsv')).open('w',newline='') as fh:
    w=csv.writer(fh,delimiter='\t');w.writerow(['run_name','metric','value'])
    for key,value in metrics.items():w.writerow([run,key,value])
