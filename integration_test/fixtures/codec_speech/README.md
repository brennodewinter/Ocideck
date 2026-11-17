# Limited speech import probe

The JFK sample is from the pinned whisper.cpp v1.9.5 sample corpus; its URL
and SHA-256 are in the manifest. It contains an extract of the US presidential
inaugural speech. The other files encode the same speech as Vorbis, Opus, AAC
or PCM in the named containers, generated locally with FFmpeg. No user audio.

The probe checks real file-source decoding followed by the production local
Whisper engine with the catalog-pinned `base` model. It is a limited English
speech regression, not a complete UI/release, multilingual or quality benchmark.
It does not establish video-track behavior: use the separate tone corpus for
containers carrying simultaneous audio and video tracks.
