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

## Phase 3 — Native conversation timelines (in progress)

- [x] Native `UICollectionViewCompositionalLayout` factory
- [x] One Turn per section and one Block per item with a traditional data source and stable IDs
- [x] `structural` / `sizeAffecting` / `contentOnly` update classification
- [x] 33–80ms `AgentUpdateScheduler` coalescing
- [x] Stable-ID `AgentScrollCoordinator` and `AgentLayoutAnchor`
- [x] History prepend restoration and deleted-anchor fallback tests
- [x] Cursor-backed history loading with one-request-per-drag gating and visible progress
- [x] Bounded, appearance-sensitive `AgentItemSizeCache`
- [x] Jump to Latest and unread tracking
- [x] Streaming-aware follow policy with direct-manipulation cooldown and deterministic tests
- [x] Recommended native `UITableView` timeline with batched tail insertion, smooth bottom following,
  interruptible scrolling, and deterministic regression coverage
- [x] Table Turn metadata rendered as a content-adjacent cell instead of section headers
- [ ] Physical-device 2pt drift and sustained-streaming acceptance benchmarks

## Phase 4 — Markdown

- [x] Background actor parser and package-owned Sendable render document
- [x] Heading, inline styling, lists/tasks, quote, code, table, image, and HTML fallback model
- [x] Bounded render-document cache
- [x] Unified Diff parser with multi-file, rename, binary, marker, and truncation coverage
- [x] Selectable TextKit fallback with revision/cancellation protection
- [x] Structured UIKit Markdown views for headings, code, and horizontally scrollable tables
- [x] Complete attributed inline styling and horizontally scrolling fenced code
- [x] Image provider integration with loading, cancellation, reuse safety, and fallback UI
- [x] Host-routed full-screen image preview with pan and zoom in the Demo
- [x] Markdown-image integration and streaming debounce policy

## Phases 5–7 — UI blocks, composer, and system integration

- [x] Built-in display paths and safe custom fallback for every Core block type
- [x] Extensible renderer registry and offline custom weather renderer demo
- [x] Approval buttons disable immediately until runtime confirmation
- [x] Default multiline composer, Send/Stop, draft and attachment metadata
- [x] Rich composer attachment upload/retry/removal, host accessories, file paste/import routing,
  context status, and offline draft preservation
- [x] Interactive Mock Runtime submit flow with thinking, tools, and streaming Markdown results
- [x] Complete conversation Demo is the default launch; isolated renderer scenarios remain in Test Lab
- [x] State-aware Test Lab playback plus replay, paused reset, step, and one-tap sample response
- [x] Whole-row tool disclosure with icon/title/detail structure and animated height changes
- [x] `keyboardLayoutGuide`, interactive dismissal, and hardware key commands
- [x] Adaptive iPad content width, Light/Dark semantic theme, Dynamic Type, and VoiceOver labels
- [x] English and Simplified Chinese String Catalog
- [x] Complete context menus, pointer, drag/drop, and remaining rich block behaviors
- [x] Initial phone/iPad Light/Dark composer snapshots, lifecycle renderer matrix, and Demo XCUITests
- [x] Full language, Dynamic Type, rotation, and all-scenario visual regression matrix

## Phase 8 — Validation and RC (in progress)

- [x] Debug simulator build and package test suite
- [x] Release simulator build
- [x] iPad simulator Demo build
- [x] Swift Format strict lint
- [x] DocC build (dependency-owned warnings are recorded)
- [x] Automated coverage for all six normative stress scenarios
- [ ] Physical-device Instruments report (Release build/install passed; launch was blocked when the
  device locked)
- [x] Thread Sanitizer CI result
- [x] Public API baseline and CI check configured
- [ ] 1.0 RC physical-device acceptance

## Normative layout decision

- The production dependency graph contains no third-party chat layout. The recommended page uses
  native `UITableView`; the optional collection page uses `UICollectionViewCompositionalLayout`.
  Both use an `AgentUpdateScheduler`, stable layout anchors, and bounded height caches.

## Latest local validation

Validated 2026-08-13 with Xcode 26.6 / Swift 6.3.3:

- iOS 18.2 iPhone simulator: all package suites passed;
- iOS 18.2 iPhone simulator: composer plus all-block conversation snapshots passed across
  Light/Dark, English/Chinese/RTL content, Dynamic Type, High Contrast, and rotation;
- all six normative scenarios have deterministic coverage, including iPad resize at 4pt and a
  20-page mixed-height history prepend at 2pt;
- Markdown inline styles, selectable text, horizontal code, Markdown images, raw diff background
  parsing, context menus, pointer interactions, and composer drop routing passed targeted tests;
- generic iOS Simulator: Debug and Release package builds passed;
- iOS 18.2 iPhone 16 simulator: all deterministic Demo XCUITests passed;
- iOS 26.6 iPhone 14 Pro: signed Release build and installation passed; launch/Instruments remains
  pending because the device locked;
- iPhone and iPad simulators: Demo and complete QuickStart builds passed;
- Core and integration suites passed locally with Thread Sanitizer enabled;
- Demo installed and launched successfully on an iPhone simulator;
- DocC completed without documentation warnings.
- Public API baseline recording is configured with `Scripts/check-api-baseline.sh`; CI regenerates
  both the base revision and current API under its pinned Xcode 16.4 toolchain before comparison.
- GitHub Actions run `31400327437` passed all 11 jobs on Xcode 16.4.
