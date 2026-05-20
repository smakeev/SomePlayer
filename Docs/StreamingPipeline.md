# Streaming Pipeline

The streaming path is split into downloader, parser, reader, streamer, and playback engine layers.

At a high level:

1. `SomePlayerEngine` receives a URL and configures playback state.
2. `Streamer` coordinates downloading and packet parsing.
3. `Parser` reads stream metadata and packet descriptions.
4. `Reader` converts parsed packets into audio buffers.
5. `TimePitchStreamer` schedules buffers into the AVAudioEngine graph.

This document is a starting point for the next cleanup pass, where file names and public API names can be aligned with the new package structure.
