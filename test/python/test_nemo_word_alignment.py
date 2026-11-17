"""Contract tests do not require a model, network or native library."""
import importlib.util
from pathlib import Path
import unittest

source = Path(__file__).resolve().parents[2] / 'testbed/asr-diarization/nemo_word_alignment.py'
spec = importlib.util.spec_from_file_location('nemo_word_alignment', source)
alignment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alignment)


class WordAttributionTest(unittest.TestCase):
    def segment(self):
        return {'text': ' A B A', 'start': 0.0, 'end': 0.3,
                'language': 'nl', 'language_uncertain': True,
                'words': [{'text': text, 'start': start, 'end': end}
                          for text, start, end in [(' A', 0.0, 0.1),
                                                   (' B', 0.1, 0.2), (' A', 0.2, 0.3)]]}

    def test_returning_voice_keeps_id_and_original_word_clock(self):
        output = alignment.align_segments([self.segment()], [[.9, .0], [.0, .9], [.9, .0]], .1)
        self.assertEqual([s['speaker_ids'] for s in output], [['nemo-1'], ['nemo-2'], ['nemo-1']])
        self.assertEqual([s['start'] for s in output], [0.0, .1, .2])
        self.assertEqual([s['end'] for s in output], [.1, .2, .3])
        self.assertTrue(all(s['language'] == 'nl' and s['speaker_uncertain'] for s in output))
        self.assertEqual(''.join(s['text'] for s in output), ' A B A')

    def test_low_or_ambiguous_activity_stays_unknown(self):
        for probability in [[.1, .2], [.55, .54]]:
            self.assertEqual(alignment.classify_interval(0, .1, [probability], .1), [])

    def test_overlap_requires_simultaneous_strong_activity(self):
        self.assertEqual(alignment.classify_interval(0, .1, [[.8, .7]], .1), ['nemo-1', 'nemo-2'])
        self.assertEqual(alignment.classify_interval(0, .1, [[.7, .2]], .1), ['nemo-1'])

    def test_missing_or_mismatched_words_preserve_full_segment(self):
        for words in [[], [{'text': 'different', 'start': 0, 'end': .1}]]:
            segment = self.segment() | {'words': words}
            output = alignment.align_segments([segment], [[.9, .0]], .1)
            self.assertEqual(output[0]['text'], segment['text'])
            self.assertEqual(output[0]['start'], 0)
            self.assertEqual(output[0]['end'], .3)
            self.assertEqual(output[0]['speaker_ids'], [])

    def test_invalid_word_timing_does_not_invent_a_split(self):
        segment = self.segment()
        segment['words'][1]['end'] = .01
        output = alignment.align_segments([segment], [[.9, .0]], .1)
        self.assertEqual(len(output), 1)
        self.assertEqual(output[0]['speaker_ids'], [])

    def test_outside_model_extent_is_unknown(self):
        self.assertEqual(alignment.classify_interval(3, 4, [[.9, .0]], .1), [])

    def test_adjacent_same_voice_coalesces_without_losing_spaces(self):
        output = alignment.align_segments([self.segment()], [[.9, .0]] * 3, .1)
        self.assertEqual(len(output), 1)
        self.assertEqual(output[0]['text'], ' A B A')


if __name__ == '__main__':
    unittest.main()
