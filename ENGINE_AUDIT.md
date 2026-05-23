# Engine Audit — Open Items

Known Issues in code or open questions.

Tags: `[THREAD]` concurrency/race, `[BUG]` correctness, `[LIFETIME]` retain/leak, `[STYLE]` clarity, `[UI]` examples logic or UI issues, `[DESIGN]` open question.

---

## PlayerEngine.swift

### #32 [DESIGN] Download failure during streaming leaves `state` unchanged
`PlayerEngine.swift:streamer(_, failedDownloadWithError:...)` — emits `.downloadFailed` and stashes `ResumableData`, but `state` stays at whatever it was (typically `.playing`). The next `play()` call goes through `resumeDirect()` because `hasError == true`, so retry works — but until the user reacts to the edge event, the UI keeps showing "playing" while playback will silently buffer to EOF. Open question: should stream / progressive policies transition to `.failed` (recoverable via `resume(_:)`), or stay put and let the edge event drive the UI? Predownload should probably go `.failed`.

