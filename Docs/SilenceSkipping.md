# Silence Skipping

The package currently contains three silence handling modes:

- `smart`
- `speedUp`
- `adaptiveSpeed`

The processors share rate smoothing and multi-channel sample analysis where possible. The implementation remains intentionally close to the previous working code so the audio behavior can be tuned before a larger public API redesign.
