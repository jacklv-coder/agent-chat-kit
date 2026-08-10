# Performance

Physical-device performance acceptance measurements have not yet been recorded. Release 1.0
requires all six normative scenarios and a record of device, OS, build mode, main-thread p95, memory
growth, anchor drift, and cache release behavior.

## Automated sanity coverage

On 2026-08-10, Xcode 26.6 / Swift 6.3.3 simulator tests verified:

- construction of a 2,000-Turn / 6,000-Block fixture;
- bounded parsing of a 5,000-line unified diff;
- a capacity-limited item-size cache keyed by block ID, revision, width, content size, and theme;
- stable-ID restoration across a top prepend and deleted-anchor fallback;
- scheduler coalescing of repeated size-affecting patches;
- bounded 200KB / 2,000-line command output behavior.

These are correctness smoke tests, not the required Instruments report. Main-thread p95, 10-minute
streaming, 20-page mixed-height prepend, memory growth, and final 2pt/4pt drift targets remain open.
