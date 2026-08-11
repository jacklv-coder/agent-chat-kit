# Implementation Status

Normative baseline: specification v1.1-draft, revision 2026-08-10-r2.

This file records verified implementation, not intent. An item is marked complete only after its
code, tests, demo path, and documentation are present.

## Phase 0 — Repository and baseline

- [x] Swift 6 package and five library products
- [x] iOS/iPadOS 17 deployment target
- [x] `swift-markdown` dependency pinned to an exact version
- [x] License, notice, contribution, security, changelog, and README baseline
- [x] CI workflow baseline
- [x] Offline Demo project source and XcodeGen definition
- [x] Demo Debug build and simulator launch
- [x] All CI jobs green on GitHub

## Phase 1 — Core models and Runtime SPI

- [x] Strong IDs and ordinary-JSON `JSONValue`
- [x] Conversation, turn, block, resource, failure, and built-in block models
- [x] Chunked/sanitized/bounded command output model
- [x] Runtime adapter, single-consumer connection, capabilities, commands, and events
- [x] Codable, compatibility, sanitization, and model unit tests

## Phase 2 — Reducer, store, and session

- [x] Event ID LRU de-duplication and ordered reduction
- [x] Bounded out-of-order buffering, gap detection, and snapshot recovery
- [x] Revision-safe block deltas, type validation, and approval idempotency
- [x] Main-actor Store, patch stream, Session lifecycle, cancellation, and offline retention
- [x] Scripted single-consumer Mock Runtime and end-to-end integration tests

## Phase 3 — Native collection timeline (in progress)

- [x] Native `UICollectionViewCompositionalLayout` factory
- [x] One Turn per section and one Block per item with Diffable stable IDs
- [x] `structural` / `sizeAffecting` / `contentOnly` update classification
- [x] 33–80ms `AgentUpdateScheduler` coalescing
- [x] Stable-ID `AgentScrollCoordinator` and `AgentLayoutAnchor`
- [x] History prepend restoration and deleted-anchor fallback tests
- [x] Bounded, appearance-sensitive `AgentItemSizeCache`
- [x] Jump to Latest and unread tracking
- [ ] Physical-device 2pt drift and sustained-streaming acceptance benchmarks

## Phase 4 — Markdown (in progress)

- [x] Background actor parser and package-owned Sendable render document
- [x] Heading, inline styling, lists/tasks, quote, code, table, image, and HTML fallback model
- [x] Bounded render-document cache
- [x] Unified Diff parser with multi-file, rename, binary, marker, and truncation coverage
- [x] Selectable TextKit fallback with revision/cancellation protection
- [x] Structured UIKit Markdown views for headings, code, and horizontally scrollable tables
- [ ] Complete attributed inline styling and horizontally scrolling fenced code
- [x] Image provider integration with loading, cancellation, reuse safety, and fallback UI
- [x] Host-routed full-screen image preview with pan and zoom in the Demo
- [ ] Markdown-image integration and streaming debounce policy

## Phases 5–7 — UI blocks, composer, and system integration (in progress)

- [x] Built-in display paths and safe custom fallback for every Core block type
- [x] Extensible renderer registry and offline custom weather renderer demo
- [x] Approval buttons disable immediately until runtime confirmation
- [x] Default multiline composer, Send/Stop, draft and attachment metadata
- [x] Interactive Mock Runtime submit flow with thinking, tools, and streaming Markdown results
- [x] Whole-row tool disclosure with icon/title/detail structure and animated height changes
- [x] `keyboardLayoutGuide`, interactive dismissal, and hardware key commands
- [x] Adaptive iPad content width, Light/Dark semantic theme, Dynamic Type, and VoiceOver labels
- [x] English and Simplified Chinese String Catalog
- [ ] Complete context menus, pointer, drag/drop, and remaining rich block behaviors
- [ ] Snapshot and XCUITest matrices

## Phase 8 — Validation and RC (in progress)

- [x] Debug simulator build and package test suite
- [x] Release simulator build
- [x] iPad simulator Demo build
- [x] Swift Format strict lint
- [x] DocC build (dependency-owned warnings are recorded)
- [ ] Physical-device Instruments report and all six normative stress scenarios
- [x] Thread Sanitizer CI result
- [ ] Public API baseline and 1.0 RC

## Normative layout decision

- The production dependency graph contains no third-party chat layout. Phase 3 uses native
  `UICollectionViewCompositionalLayout`, `AgentUpdateScheduler`, `AgentScrollCoordinator`, stable
  `AgentLayoutAnchor` values, and a bounded `AgentItemSizeCache`, per specification 1.1.

## Latest local validation

Validated 2026-08-10 with Xcode 26.6 / Swift 6.3.3:

- iOS 26.1 iPhone simulator: all package tests passed;
- generic iOS Simulator: Debug and Release package builds passed;
- iPad Pro simulator destination: Demo build passed;
- Core and integration suites passed locally with Thread Sanitizer enabled;
- Demo installed and launched successfully on an iPhone simulator;
- DocC completed; warnings originated from `swift-markdown` 0.8.0 documentation collisions and
  missing upstream snippets, not AgentChatKit sources.
- GitHub Actions run `31400327437` passed all 11 jobs on Xcode 16.4.
