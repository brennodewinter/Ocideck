"""Word-time attribution to actual model activity, with explicit unknowns.

No fabricated word boundaries, voice identities or alternating speaker numbers.
The cutoffs are conservative decisions, not calibrated accuracy percentages.
"""
import math


def classify_interval(start, end, probabilities, frame_seconds):
    first = max(0, math.floor(start / frame_seconds))
    last = min(len(probabilities), max(first + 1, math.ceil(end / frame_seconds)))
    if first >= last:
        return []
    slots = len(probabilities[first])
    means = [sum(float(probabilities[f][slot]) for f in range(first, last)) /
             (last - first) for slot in range(slots)]
    order = sorted(range(slots), key=lambda slot: means[slot], reverse=True)
    overlapping = [slot for slot in range(slots) if means[slot] >= 0.6]
    if len(overlapping) > 1:
        return ['nemo-' + str(slot + 1) for slot in overlapping]
    if len(order) > 1 and means[order[0]] >= 0.5 and means[order[0]] - means[order[1]] >= 0.1:
        return ['nemo-' + str(order[0] + 1)]
    return []


def _valid_words(segment):
    words = segment.get('words')
    if not words or ''.join(word['text'] for word in words) != segment['text']:
        return False
    previous = 0.0
    for word in words:
        start, end = word['start'], word['end']
        if (not math.isfinite(start) or not math.isfinite(end) or
                start < previous or end < start):
            return False
        previous = start
    return True


def align_segments(segments, probabilities, frame_seconds):
    """Preserve every ASR character; split only on its genuine word times.

    Every assignment stays uncertain in this reference experiment. Unknown
    activity gives no IDs; simultaneous strong activity permits multiple IDs.
    A word-text mismatch preserves the original complete segment as unknown.
    """
    if not math.isfinite(frame_seconds) or not 0 < frame_seconds <= 0.1:
        raise ValueError('Invalid model frame cadence')
    output = []
    for segment in segments:
        base = {key: value for key, value in segment.items() if key != 'words'}
        if not _valid_words(segment):
            output.append(base | {'speaker_ids': [], 'speaker_uncertain': True})
            continue
        group = None
        for word in segment['words']:
            ids = classify_interval(word['start'], word['end'], probabilities, frame_seconds)
            if group is not None and group['speaker_ids'] == ids:
                group['text'] += word['text']
                group['end'] = max(group['end'], word['end'])
            else:
                group = base | {'text': word['text'], 'start': word['start'],
                                'end': word['end'], 'speaker_ids': ids,
                                'speaker_uncertain': True}
                output.append(group)
    if ''.join(s['text'] for s in output) != ''.join(s['text'] for s in segments):
        raise ValueError('Word attribution must preserve the ASR text')
    return output
