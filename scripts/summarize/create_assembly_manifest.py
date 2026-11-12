#!/usr/bin/env python3
"""Create an editable assembly manifest from per-isolate preparation results."""
import argparse
import csv
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--coverage-dir', required=True)
p.add_argument('--coverage-summary', required=True)
p.add_argument('--output', required=True)
p.add_argument('--staged-dirs', nargs='*', default=[])
a = p.parse_args()
root = Path(a.coverage_dir).expanduser().resolve()
with open(a.coverage_summary, newline='') as fh:
    rows = list(csv.DictReader(fh))
seen = set()
staged = {d.name: d for d in (Path(x) for x in a.staged_dirs)}
with open(a.output, 'w', newline='') as fh:
    writer = csv.writer(fh)
    writer.writerow(['Isolate', 'Reads', 'GenomeSize', 'MinReadDepth', 'Assemble'])
    for row in rows:
        isolate = row['isolate'].strip()
        if isolate in seen:
            raise SystemExit(f'Duplicate isolate in coverage summary: {isolate}')
        seen.add(isolate)
        status = row['status'].strip()
        valid = status == 'OK' or (bool(status) and all(
            flag in {'LOW_TOTAL_BASES', 'LOW_GENOME_SIZE', 'LOW_COVERAGE'}
            for flag in status.split(';')))
        size = row['genome_size'].strip()
        depth = row['min_read_depth'].strip()
        reads = root / isolate / 'trimmed_reads' / f'{isolate}.trimmed.fastq.gz'
        if not (size.isdigit() and int(size) > 0 and depth.isdigit() and int(depth) > 0):
            valid = False
        staged_reads = staged.get(isolate, Path('/nonexistent')) / 'trimmed_reads' / f'{isolate}.trimmed.fastq.gz'
        if not staged_reads.is_file() or staged_reads.stat().st_size == 0:
            valid = False
        writer.writerow([isolate, str(reads) if staged_reads.is_file() else '',
                         size if size.isdigit() and int(size)>0 else 'NA',
                         depth if depth.isdigit() and int(depth)>0 else '',
                         'true' if valid else 'false'])
