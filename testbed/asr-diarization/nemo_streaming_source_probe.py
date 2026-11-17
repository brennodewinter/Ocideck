"""Retain initial streaming confusion and later stability; never report it as DER."""
import argparse
import json
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('activity', type=Path)
    parser.add_argument('fixtures', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.activity.suffix == '.npz':
        with np.load(args.activity, allow_pickle=False) as archive:
            data = archive['activity']
    else:
        data = np.load(args.activity, allow_pickle=False)
    manifest = json.loads((args.fixtures / 'manifest.json').read_text())
    source = next(case for case in manifest['cases'] if case['file'] == 'nl-aba.wav')
    duration = source['duration_s']
    source_order = list(dict.fromkeys(s['source_ids'][0] for s in source['source_spans']))
    report = {'scope': 'diagnostic native activity over repeated known source intervals; no ASR-word/activity-aligned DER',
              'source_sha256': source['sha256'], 'native_frame_seconds': .01,
              'evaluation_slot_mapping_by_source_arrival': dict(zip(source_order, range(len(source_order)))),
              'cycles': []}
    for cycle in range(12):
        measured = []
        for span in source['source_spans']:
            first = round((cycle * duration + span['start']) * 100)
            last = round((cycle * duration + span['end']) * 100)
            values = data[first:last]
            if not len(values):
                raise ValueError('Missing repeated source activity')
            counts = {}
            for row in values:
                order = np.argsort(row)[::-1]
                ids = np.flatnonzero(row >= .6).tolist()
                if len(ids) < 2:
                    ids = [int(order[0])] if row[order[0]] >= .5 and row[order[0]] - row[order[1]] >= .1 else []
                key = ','.join(str(index) for index in ids) or 'unknown'
                counts[key] = counts.get(key, 0) + 1
            measured.append({'source_ids': span['source_ids'], 'source_start_seconds': span['start'],
                             'native_frames': len(values), 'assigned_slot_sets': counts})
        report['cycles'].append({'cycle': cycle, 'sources': measured})
    report['diagnostic_only'] = True
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
