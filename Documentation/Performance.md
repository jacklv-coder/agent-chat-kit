# Performance

The release gate combines deterministic regression tests with a physical-device Instruments run.
The tests are intentionally time-compressed: they deliver the same event count and layout changes
without making CI wait ten minutes.

## Automated acceptance matrix

Validated on 2026-08-13 with Xcode 26.6 / Swift 6.3.3 and an iOS 18.2 iPhone 16 simulator:

| Spec scenario | Automated coverage | Result |
| --- | --- | --- |
| A — 2,000 Turns / 6,000 Blocks | Mixed Markdown, Tool, and Command fixture construction | Passed |
| B — 20–30 deltas/second for 10 minutes | 18,000 targeted deltas through `AgentUpdateScheduler`; one coalesced flush in the time-compressed harness | Passed |
| C — 1MB command output | `AgentTextBuffer` retains at most 200KB / 2,000 lines and reports truncation; full-output UI routes to a host action | Passed |
| D — 5,000-line diff | Actor parsing, bounded 1,000-line result, cached revision, summary rendering, and Open Full Diff host action | Passed |
| E — iPad resize | Production TableView page resized through 1,024, 760, 920, 620, and 1,024pt widths with Markdown and expanded tools | Passed; stable block and no more than 4pt drift |
| F — 20-page prepend | 20 × 50 mixed-height history Turns inserted through production batch updates | Passed; stable block and no more than 2pt drift |

Additional coverage verifies bottom batch insertion, interrupted following, parsed-Markdown height
growth, deleted-anchor fallback, bounded Markdown/diff/height caches, memory-warning cleanup hooks,
RTL, Dynamic Type, High Contrast, Light/Dark, and rotation baselines.

Run the deterministic acceptance set with:

```sh
xcodebuild -scheme AgentChatKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:AgentChatPerformanceTests \
  -only-testing:AgentChatUIKitTests/AgentTimelineTests/testTableControllerPreservesSemanticAnchorAcrossIPadResize \
  -only-testing:AgentChatUIKitTests/AgentTimelineTests/testTableControllerPreservesAnchorAcrossTwentyMixedHeightHistoryPages \
  test
```

## Physical-device Instruments gate

Before tagging 1.0 RC, repeat scenarios A–F with a Release build on a connected reference device and
record device, OS, main-thread p95, peak/additional memory, anchor drift, retain-cycle inspection, and
post-scenario cache release. The normative targets remain main-thread p95 below 8ms and less than
120MB additional memory for scenario A.

On 2026-08-13, the Release Demo signed, built, and installed on an iPhone 14 Pro running iOS 26.6.
The device locked before launch, so the Instruments measurements remain pending. Simulator results
are not represented as physical-device data.
