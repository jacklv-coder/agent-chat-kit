# Changelog

All notable changes are documented here. This project follows Semantic Versioning after 1.0.

## [Unreleased]

### Added

- Host-injectable ``AgentComposerProviding`` support for both UITableView and UICollectionView
  conversation controllers, with ``AgentComposerInteracting`` for live draft and keyboard actions,
  optional item-provider import routing, and lifecycle-safe single-stream consumption.
- Swift Package baseline with Core, Markdown, UIKit, Testing, and umbrella products.
- Strongly typed conversation models and runtime-neutral adapter SPI.
- Deterministic actor-based event reducer, main-actor store, and session coordinator.
- Offline demo and mock runtime foundations.
- Native compositional timeline foundations with explicit update scheduling and stable-ID scroll
  anchoring; no third-party chat layout dependency.
- A complete, CI-built QuickStart host with a reference runtime adapter and DocC integration guides.
- Versioned JSON scenario fixtures, deterministic pause/step/rate playback, runtime event-contract
  validation, and an in-app Test Lab with diagnostics.
- Snapshot baselines and Demo XCUITests for rich composer, lifecycle, streaming Markdown, and table
  rendering paths.
- Public API baseline checking, all-block visual regression fixtures, and deterministic coverage for
  all six normative stress scenarios.

### Changed

- Pinned Swift Markdown 0.6.0 so the package remains resolvable with the documented Xcode 16
  minimum toolchain.
- Reorganized the Demo into Chats and Test Lab tabs. Chats now starts from a recent-conversation
  list and pushes the production `UITableView` timeline for interactive message testing.
- Rebuilt the composer as a host-extensible multiline surface with attachment upload states,
  retry/removal, paste and document import routing, model/reasoning/workspace accessories, context
  status, and explicit Send/Stop behavior.
- Disabled submission while disconnected by default and preserved drafts when runtime submission
  fails.
- Added interruptible, smoothly animated bottom-batch insertion to the native table timeline, with
  a dedicated Test Lab scenario and regression coverage.
- Moved table-timeline timestamps from section headers into a final cell for each Turn, aligned
  beneath the corresponding user bubble or assistant response region.
- Added selectable attributed Markdown, horizontal/collapsible fenced code, Markdown images, cached
  background diff parsing, complete block context menus, pointer feedback, and composer drag/drop.
- Preserved semantic anchors through iPad resizing and twenty-page mixed-height history prepends.
