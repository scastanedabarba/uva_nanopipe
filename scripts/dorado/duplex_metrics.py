#!/usr/bin/env python3
"""Stream BAM via samtools; summarize dx-tag counts and sequence bases."""
import csv, subprocess, sys
from collections import defaultdict
bam, output = sys.argv[1:]
counts = defaultdict(int); bases = defaultdict(int)
proc = subprocess.Popen(['samtools','view',bam], stdout=subprocess.PIPE, text=True)
for line in proc.stdout:
    fields = line.rstrip('\n').split('\t')
    tags = [x[5:] for x in fields[11:] if x.startswith('dx:i:')]
    category = {'0':'simplex','1':'duplex','-1':'duplex_parent'}.get(tags[0] if tags else '', 'other')
    counts[category] += 1
    bases[category] += len(fields[9]) if fields[9] != '*' else 0
if proc.wait(): sys.exit('ERROR: samtools view failed')
den = counts['simplex'] + counts['duplex_parent']
base_den = bases['simplex'] + bases['duplex']
metrics = {**{f'{k}_reads':counts[k] for k in ('simplex','duplex','duplex_parent','other')},
           **{f'{k}_bases':bases[k] for k in ('simplex','duplex','duplex_parent','other')},
           'duplex_rate_pct':round(200*counts['duplex']/den,4) if den else 'NA',
           'duplex_base_fraction_pct':round(100*bases['duplex']/base_den,4) if base_den else 'NA'}
with open(output,'w',newline='') as f:
    writer=csv.writer(f,delimiter='\t');writer.writerow(['metric','value']);writer.writerows(metrics.items())
