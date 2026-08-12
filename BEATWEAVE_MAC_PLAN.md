# BeatWeave for macOS — Development Plan

> Goal: Build a native macOS video editor focused on **music beat analysis, beat markers, automatic beat-synced cutting, fast manual refinement, preview, and local export**.
>
> Target: **macOS 27+**
>
> Recommended stack: **Swift 6 / SwiftUI / AVFoundation / Accelerate(vDSP) / Core Image**, with Metal introduced only when profiling proves it necessary.

---

## 1. Product positioning

BeatWeave should not start as a Final Cut Pro / Premiere replacement.

The first versions should make one workflow exceptionally fast:

1. Import video clips.
2. Import a music track.
3. Analyze music automatically.
4. Display waveform + BPM + beat markers.
5. Select clips.
6. Automatically cut/reorder clips to beats.
7. Let the user quickly adjust cuts on a timeline.
8. Preview smoothly.
9. Export a finished video.

Typical use cases:

- Travel montage
- Drone footage
- Vlog highlight reel
- Sports/action montage
- Short-form social video
- Photo + video music montage
- Automatically generated beat-synced highlight video

Primary design principles:

- Local-first and offline.
- Non-destructive editing.
- Native macOS interaction.
- Keyboard-friendly.
- Automatic results must remain manually editable.
- Never hide the generated cuts from the user.
- Keep the project model independent from the UI and render engine.
- Do not introduce cloud AI or accounts in the MVP.

---

# 2. MVP scope

## 2.1 Media import

Support:

- MOV
- MP4
- M4V
- common H.264 / HEVC media supported by AVFoundation
- M4A
- AAC
- MP3
- WAV

Media browser should display:

- thumbnail
- filename
- duration
- resolution
- frame rate
- audio/video indicator
- source URL status

Operations:

- drag files from Finder
- file picker import
- drag clips from media bin to timeline
- delete media reference from project
- reveal source in Finder
- relink missing media

Do not physically modify source files.

---

## 2.2 Project format

Create a custom project type:

```text
MyVideo.beatweave
```

Prefer a package/document structure rather than one opaque binary.

Suggested internal structure:

```text
MyVideo.beatweave/
├── project.json
├── thumbnails/
├── waveforms/
├── analysis/
│   └── music-analysis.json
├── proxies/
└── autosave/
```

`project.json` should store:

- project UUID
- project version
- canvas size
- frame rate
- media references
- timeline tracks
- clip edits
- music track
- volume
- transitions
- beat markers
- BPM
- analysis parameters
- user markers
- export defaults

External media should remain external by default.

Use security-scoped access/bookmarks when required by the sandbox.

Project data must be versioned from day one:

```swift
projectFormatVersion: Int
```

Never encode view-layer SwiftUI types directly into project files.

---

# 3. Main interface

Desktop layout:

```text
┌──────────────────────────────────────────────────────────┐
│ Toolbar                                                  │
├─────────────┬─────────────────────────────┬──────────────┤
│ Media Bin   │          Viewer             │ Inspector    │
│             │                             │              │
│ clips       │          preview            │ clip/music   │
│ music       │                             │ properties   │
├─────────────┴─────────────────────────────┴──────────────┤
│ Timeline / Waveform / Beat Grid                          │
│                                                          │
│ V1 ─ clip ─── clip ───── clip ───── clip                │
│ A1 ─ original audio ─────────────────────                │
│ M1 ─ music + waveform + beat markers ─────────────────  │
└──────────────────────────────────────────────────────────┘
```

Important interactions:

- space: play / pause
- J / K / L: reverse / pause / forward
- left/right: frame or small seek
- command +/-: timeline zoom
- B: blade tool
- A: selection tool
- delete: remove selected item
- command Z / shift-command Z: undo/redo
- S: snapping toggle
- M: manual marker
- optional custom shortcut: jump previous/next beat

The user must be able to perform common edits without opening modal dialogs.

---

# 4. Architecture

Use a modular native architecture.

Suggested modules:

```text
BeatWeave/
├── App/
├── Domain/
│   ├── Project/
│   ├── Media/
│   ├── Timeline/
│   ├── Beat/
│   └── Export/
├── Services/
│   ├── MediaImportService
│   ├── ThumbnailService
│   ├── WaveformService
│   ├── BeatAnalysisService
│   ├── PlaybackService
│   ├── RenderService
│   └── ExportService
├── Engines/
│   ├── TimelineEngine
│   ├── CompositionBuilder
│   ├── AutoCutEngine
│   └── BeatDetectionEngine
├── Features/
│   ├── MediaBrowser/
│   ├── Viewer/
│   ├── Timeline/
│   ├── Inspector/
│   └── Export/
└── Tests/
```

Rules:

1. SwiftUI Views do not contain AVFoundation editing logic.
2. Domain models must be independently testable.
3. Timeline state is the source of truth.
4. `AVMutableComposition` or other AVFoundation render objects are generated from project state.
5. Never use the AVFoundation composition itself as persistent project state.
6. Expensive media work must not execute on the main actor.
7. Analysis/export jobs must support cancellation.
8. Avoid global singletons.
9. Use structured concurrency and actors where practical.
10. Each major engine needs unit tests.

---

# 5. Core domain model

Suggested conceptual model:

```swift
Project
 ├─ MediaLibrary
 ├─ Timeline
 │   ├─ VideoTrack[]
 │   ├─ AudioTrack[]
 │   └─ MusicTrack?
 ├─ BeatAnalysis?
 └─ ExportSettings
```

Timeline item:

```swift
TimelineClip
- id
- mediaID
- sourceRange
- timelineStart
- timelineDuration
- playbackRate
- transform
- opacity
- volume
- transitionIn
- transitionOut
```

Beat model:

```swift
BeatAnalysis
- bpm
- confidence
- beatTimes[]
- strongBeatTimes[]
- downbeatTimes[]
- waveformCache
- analysisVersion
```

All timeline times should use a precise time representation.

Prefer `CMTime` internally for media calculations.

For persisted JSON, define a stable Codable representation rather than serializing framework implementation details directly.

---

# 6. Beat analysis engine

This is BeatWeave's key capability.

## 6.1 Audio preprocessing

Pipeline:

```text
music file
   ↓
AVAssetReader
   ↓
PCM samples
   ↓
mono conversion
   ↓
normalization
   ↓
windowing
   ↓
FFT / spectral analysis
```

Use AVFoundation to decode the source.

Use Accelerate/vDSP for signal processing.

Suggested initial parameters:

- sample rate: source rate or normalized 44.1/48 kHz
- FFT window: 1024 or 2048
- hop size: 256 / 512
- Hann window
- compute spectral flux
- optional low/mid/high-band onset strength

Do not hardcode one parameter set without tests.

---

## 6.2 Onset detection

Implement an onset strength envelope.

Initial algorithm:

1. FFT each window.
2. Compute magnitude spectrum.
3. Compare current spectrum with previous spectrum.
4. Keep positive spectral differences.
5. Sum weighted differences.
6. Smooth envelope.
7. Adaptive local threshold.
8. Peak picking.
9. Produce onset candidates.

Store:

```swift
Onset {
    time
    strength
}
```

Visualize detected onsets during development.

---

## 6.3 BPM estimation

Generate BPM candidates using onset intervals and/or autocorrelation.

Recommended initial search range:

```text
60–200 BPM
```

Handle half/double-tempo ambiguity:

```text
75 BPM
150 BPM
```

Rank candidates using:

- onset alignment
- autocorrelation strength
- interval consistency

Return:

```swift
BPMResult {
    bpm
    confidence
    alternateBPMs
}
```

The UI must let the user manually:

- enter BPM
- choose x0.5
- choose x2
- tap tempo
- rerun analysis

---

## 6.4 Beat grid

After BPM estimation:

1. Find likely beat phase/offset.
2. Generate beat grid.
3. Refine beat locations toward nearby strong onsets.
4. Prevent unstable large local drift.
5. Assign strength.

Result:

```text
| . . . | . . . | . . . | . . . |
^         ^         ^         ^
strong beats / possible downbeats
```

First release does not need perfect musical downbeat recognition.

A stable beat grid is more important than attempting overly complex AI classification.

---

## 6.5 Beat analysis acceptance target

Use a test music set containing at least:

- EDM
- pop
- rock
- hip-hop
- cinematic
- acoustic
- tracks with intro silence
- tracks with tempo ambiguity

Required behaviors:

- analysis never crashes
- UI remains responsive
- BPM can be manually corrected
- detected markers stay stable after save/reopen
- cached results avoid unnecessary reanalysis

Keep test music outside the public repository unless redistribution is permitted.

---

# 7. Waveform

Generate a waveform cache independently from beat detection.

Store downsampled peak/RMS data.

Requirements:

- waveform available at multiple zoom levels
- waveform does not require decoding the entire audio file every frame
- timeline scroll remains responsive
- beat markers overlay directly on waveform
- current playhead stays synchronized

Waveform cache should be reproducible and disposable.

It should never be the sole source of project data.

---

# 8. Timeline engine

MVP timeline:

- 1 primary video track
- original clip audio
- 1 music track

Then extend to:

- multiple video tracks
- multiple audio tracks

Required editing operations:

- insert
- append
- move
- trim in
- trim out
- split
- delete
- ripple delete
- reorder
- snapping
- beat snapping
- playhead snapping
- marker snapping

All edits must support Undo/Redo.

Use an explicit command/action layer for destructive timeline operations rather than spreading mutation logic across SwiftUI views.

---

# 9. Beat snapping

Snapping priority:

1. exact playhead
2. beat marker
3. clip boundary
4. user marker

Allow toggles:

```text
[x] Snap
[x] Beats
[x] Clip edges
[x] Markers
```

When dragging an edit near a beat:

- show a visual snap indicator
- optionally give subtle haptic/visual feedback if supported
- never make the timeline feel "sticky" from excessive snap range

Snap threshold should scale with timeline zoom.

---

# 10. AutoCut engine

This is the second key BeatWeave feature.

Input:

```swift
AutoCutRequest
- selectedMedia
- beatAnalysis
- targetDuration
- cutPattern
- minimumClipDuration
- maximumClipDuration
- useStrongBeatsOnly
- preserveSourceOrder
- randomSeed
```

Output:

```swift
AutoCutPlan
- placements[]
- unusedMedia[]
- diagnostics
```

The engine should return a PLAN first.

Do not directly mutate the timeline during planning.

Then apply the plan as one undoable transaction.

---

## 10.1 AutoCut modes

### Mode A — Every Beat

Cut on every beat.

Best for:

- fast EDM
- action shots

### Mode B — Strong Beats

Cut every 2 / 4 / 8 beats.

Best for:

- travel
- drone
- cinematic montage

Options:

```text
1 beat
2 beats
4 beats
8 beats
```

### Mode C — Adaptive

Use:

- beat strength
- source duration
- minimum shot duration
- music section activity

Example:

```text
calm section    → 8 beat clips
normal section  → 4 beat clips
energetic       → 1–2 beat clips
```

Adaptive mode can be implemented after deterministic fixed-grid modes work well.

---

# 11. Automatic clip selection — later phase

Do not block MVP on AI clip understanding.

Phase 2 can add source analysis:

- blurry-frame detection
- exposure score
- camera motion estimate
- duplicate/near-duplicate detection
- face/person presence
- shot boundary detection
- clip stability
- orientation

Then assign:

```swift
ClipScore
- technicalScore
- motionScore
- peopleScore
- uniquenessScore
- userFavoriteWeight
```

AutoCut can prefer higher-scoring ranges.

Important:

The app must let the user pin/include/exclude clips manually.

Automatic selection is an assistant, not hidden project logic.

---

# 12. Viewer and playback

Use AVPlayer-based preview for the first implementation.

Requirements:

- play/pause
- scrub
- frame stepping where practical
- timeline playhead sync
- audio sync
- looping selection
- fit/fill viewer
- display current timecode
- display project resolution/frame rate

Build project timeline state into a playback composition.

Composition rebuilds must be debounced/coalesced when the user performs rapid edits.

Never rebuild expensive playback state on every SwiftUI body update.

---

# 13. Transitions

MVP:

- hard cut
- cross dissolve
- dip to black

Later:

- zoom
- slide
- blur
- whip/push style
- custom Metal transitions

Transitions should be represented as project data rather than baked into clips.

AutoCut should default to hard cuts.

Music beat editing usually looks better with deliberate hard cuts than excessive automatic transitions.

---

# 14. Speed controls

Phase 2:

- 0.25x
- 0.5x
- 1x
- 2x
- 4x
- custom speed

Later:

- speed ramp
- automatic speed fit to beat interval

Potential feature:

```text
Fit clip to 4 beats
```

The engine calculates the required duration and allowed playback-rate range.

Do not silently use extreme speed changes.

---

# 15. Audio controls

MVP:

- original clip audio enable/disable
- music volume
- master volume
- fade in
- fade out

Phase 2:

- per-clip audio level
- duck original audio under music
- audio keyframes
- normalization
- limiter

Optional future capability:

- voice detection
- automatic music ducking

---

# 16. Color and LUT

Do not make advanced color grading part of the first BeatWeave milestone.

Phase 2 should support:

- exposure
- contrast
- saturation
- temperature/tint
- highlights/shadows
- LUT import
- LUT intensity

Recommended internal pipeline:

```text
source frame
  ↓
transform/crop
  ↓
basic adjustments
  ↓
LUT
  ↓
transition/composite
  ↓
output
```

Use Core Image initially.

Introduce a custom Metal compositor only when required by performance or effect complexity.

---

# 17. Crop / canvas

Support project presets:

- 16:9
- 9:16
- 1:1
- 4:5
- source resolution
- custom

Common output presets:

```text
3840×2160
1920×1080
1080×1920
1080×1080
1080×1350
```

Clip controls:

- fit
- fill
- scale
- X/Y position
- rotation

Later:

- keyframes
- automatic subject reframing

---

# 18. Export

MVP export settings:

- resolution
- frame rate
- codec
- bitrate/quality preset
- output URL

Preferred output:

- H.264
- HEVC

Preserve audio sync.

Show:

- progress
- elapsed state
- cancel
- success/failure
- reveal in Finder

Never block the main thread during export.

Export must be generated from the same canonical timeline model used for preview.

Add regression tests to detect preview/export timing mismatches.

---

# 19. Proxy workflow

Not required in the earliest MVP, but architecture must anticipate it.

Add when 4K/HEVC editing shows poor responsiveness.

Possible workflow:

```text
original 4K HEVC
      ↓
proxy generation
      ↓
editing/preview proxy
      ↓
export uses original
```

Store proxy mapping in project cache.

Proxy deletion must never invalidate the project.

---

# 20. Reliability requirements

BeatWeave is a media editor; project corruption is unacceptable.

Required:

- autosave
- atomic project writes
- project schema version
- backup previous project state
- recover from missing source media
- cancellation-safe analysis
- cancellation-safe export
- recoverable cache
- structured error reporting

Do not store absolute assumptions about temporary cache paths.

---

# 21. Performance requirements

Measure before optimizing.

Add signposts / metrics around:

- media import
- thumbnail generation
- waveform generation
- beat analysis
- project composition build
- timeline scrolling
- first preview frame
- export

Performance rules:

- UI operations must stay on the main actor only when required.
- decoding/analysis runs off the UI path.
- use bounded task concurrency.
- cache thumbnails.
- cache waveform data.
- cache analysis result.
- cancel stale jobs when source settings change.
- avoid decoding full-resolution frames just to draw timeline thumbnails.

---

# 22. Development phases

---

## Phase 0 — Repository and foundation

### Deliver

- create Xcode project
- native macOS SwiftUI application
- macOS 27 deployment target
- Swift 6
- basic module/folder structure
- project document model
- test target
- CI build
- README
- LICENSE
- `docs/architecture.md`

### Acceptance

- clean clone builds
- tests run from command line
- application launches
- create/open/save `.beatweave` project
- no placeholder architecture code that is knowingly unused

### Commit

```text
feat: bootstrap BeatWeave macOS project
```

---

## Phase 1 — Media import and viewer

### Deliver

- Finder drag/drop
- file picker
- media browser
- metadata extraction
- thumbnail generation
- AVPlayer preview
- missing media handling

### Acceptance

Import at least:

- 1080p H.264
- 4K H.264
- 4K HEVC
- audio file

The app can:

- import
- preview
- save
- reopen
- resolve stored media references

### Commit

```text
feat: add media import and preview
```

---

## Phase 2 — Music + waveform

### Deliver

- music track import
- PCM decoding
- waveform cache
- waveform timeline view
- music playback synchronization
- timeline zoom

### Acceptance

- long waveform scroll does not freeze UI
- waveform persists via cache
- cache can be deleted and regenerated
- playhead remains synchronized

### Commit

```text
feat: add waveform timeline
```

---

## Phase 3 — Beat detection

### Deliver

- onset detection
- BPM estimation
- beat grid
- confidence value
- manual BPM
- half/double tempo
- tap tempo
- analysis cache
- debug diagnostics

### Acceptance

For test music:

- analysis completes without UI blocking
- beats appear on waveform
- markers remain identical after project reopen
- user can fix incorrect BPM manually
- unit tests cover signal-processing helpers

### Commit

```text
feat: add local beat analysis
```

---

## Phase 4 — Real timeline editor

### Deliver

- video timeline
- drag media to timeline
- trim
- split
- delete
- ripple delete
- reorder
- undo/redo
- snapping
- beat snapping
- current playhead
- timeline zoom

### Acceptance

User can manually create a complete simple montage aligned to beat markers without AutoCut.

### Commit

```text
feat: add beat-aware timeline editor
```

---

## Phase 5 — AutoCut MVP

### Deliver

AutoCut modes:

- every beat
- every 2 beats
- every 4 beats
- every 8 beats

Options:

- source order
- shuffled
- minimum duration
- target music range

Provide AutoCut preview summary before applying.

Apply as one undoable transaction.

### Acceptance

Workflow:

```text
import 20 clips
→ import music
→ analyze
→ choose 4-beat mode
→ AutoCut
→ preview
→ undo
→ AutoCut again
```

must work reliably.

### Commit

```text
feat: add beat-synced automatic editing
```

---

## Phase 6 — Export

### Deliver

- H.264 export
- HEVC export
- resolution presets
- frame-rate handling
- audio mix
- progress
- cancellation
- Finder reveal

### Acceptance

Exported video:

- opens in QuickTime
- has expected duration
- video/audio remain synchronized
- beat cuts match preview timing
- export cancellation leaves no corrupted final file

### Commit

```text
feat: add video export pipeline
```

At this point BeatWeave reaches **MVP**.

Create first GitHub prerelease:

```text
v0.1.0
```

---

## Phase 7 — Editing quality

### Deliver

- transitions
- volume controls
- clip audio mute
- music fade
- crop
- scale
- position
- rotate
- canvas aspect ratios
- basic color adjustments
- LUT support

### Commit

```text
feat: add essential editing controls
```

Release:

```text
v0.2.0
```

---

## Phase 8 — Smart montage

### Deliver

- media quality analysis
- clip range scoring
- duplicate-range suppression
- motion score
- person/face signal
- adaptive AutoCut
- strong-beat editing
- user include/exclude/pin controls

### Important

Do not make smart analysis mandatory.

The deterministic AutoCut engine must remain available.

### Commit

```text
feat: add adaptive montage generation
```

Release:

```text
v0.3.0
```

---

## Phase 9 — Performance and professional workflow

### Deliver

- proxy media
- background generation queue
- improved thumbnail cache
- optimized large projects
- keyboard customization
- timeline multi-select
- multi-track audio/video
- export presets
- crash recovery
- diagnostics

Test with realistic projects:

- 20 clips
- 100 clips
- 500 clips
- 4K HEVC
- long music track
- 30+ minute project

Do not create artificial extreme benchmarks that do not reflect real personal usage.

Release:

```text
v0.5.0
```

---

# 23. Features intentionally excluded from initial MVP

Do NOT implement these before Phase 6 unless required by the core architecture:

- cloud sync
- accounts
- collaboration
- template marketplace
- AI cloud APIs
- generative video
- speech-to-text subtitles
- multi-camera editor
- professional color scopes
- plugin SDK
- motion graphics editor
- advanced keyframe system
- nested timelines
- multicam synchronization

These features can be revisited only after the beat-editing workflow is solid.

---

# 24. Suggested later roadmap

## v0.6

- automatic music section detection
- verse/chorus/activity sections
- smarter beat strength
- downbeat recognition
- section-based AutoCut pacing

## v0.7

- speed ramps
- motion transitions
- automatic clip speed fitting
- dynamic zoom

## v0.8

- automatic vertical reframing
- face/person subject tracking
- 9:16 social export workflow

## v0.9

- subtitle import
- SRT editing
- speech transcription if added later

## v1.0

Focus on:

- reliability
- performance
- polished Mac UX
- stable project format
- predictable AutoCut output
- excellent timeline manual correction

Do not define v1.0 by feature count.

---

# 25. Testing strategy

## Unit tests

Cover:

- timeline time calculations
- trim
- split
- ripple edit
- undo/redo command behavior
- BPM helper functions
- onset peak selection
- beat-grid generation
- AutoCut planning
- project serialization
- project migration
- export time mapping

## Integration tests

Cover:

```text
import → analyze → AutoCut → save → reopen → export
```

Also:

```text
import → manual timeline edit → save → reopen
```

## UI tests

Only use UI automation for stable critical flows.

Do not try to validate DSP accuracy through UI screenshots.

---

# 26. Fixture strategy

Create a small internal fixture set:

```text
Fixtures/
├── audio/
├── video/
└── projects/
```

Only commit media that is safe to redistribute.

For larger/private fixtures, create a local fixture manifest and exclude source media from Git.

Tests should never depend on the user's personal Movies folder.

---

# 27. Logging

Use unified logging.

Categories:

```text
project
media
timeline
playback
beat-analysis
autocut
export
cache
```

Avoid noisy per-frame logs in release builds.

For beat analysis diagnostics record:

- duration
- sample rate
- analysis settings
- detected BPM
- alternate BPM
- confidence
- onset count
- beat count
- execution duration

Do not log full user file paths unless required for local diagnostics.

---

# 28. Codex execution rules

Codex must execute this plan **phase by phase**.

Do not implement all phases in one giant change.

For each phase:

1. Read this `PLAN.md`.
2. Inspect the current repository.
3. Summarize the current codebase state.
4. State which phase is being implemented.
5. Implement only that phase plus strictly necessary foundation work.
6. Build from command line.
7. Run unit/integration tests.
8. Fix warnings introduced by the change.
9. Manually inspect important UI behavior where automation is not sufficient.
10. Update documentation.
11. Update `CHANGELOG.md`.
12. Commit the completed phase.
13. Push the branch.
14. Report:
    - files changed
    - architecture decisions
    - tests
    - unresolved issues
    - manual verification still required
15. Stop after the phase is complete unless explicitly instructed to continue.

Never claim UI behavior has been verified unless it was actually exercised.

Never claim a test passed unless the command was actually run.

---

# 29. Code-quality rules for Codex

Required:

- no force unwraps in ordinary production flow
- no `try!`
- no unexplained magic timing constants
- no media processing in SwiftUI `body`
- no blocking IO on main actor
- no giant `ContentView`
- no project state duplicated across unrelated observable objects
- no silent error swallowing
- no destructive edits without undo support once timeline editing exists
- no unversioned project schema
- no source media modification
- no hidden automatic timeline mutation
- no dependency added simply to avoid implementing a small native capability

Prefer Apple frameworks for the core MVP.

External dependencies require a written justification in the pull request.

---

# 30. Git workflow

Recommended repository:

```text
taoking/beatweave-mac
```

Main branch:

```text
main
```

Feature work:

```text
agent/phase-0-foundation
agent/phase-1-media
agent/phase-2-waveform
agent/phase-3-beat-analysis
...
```

Each phase should have:

- focused commits
- a PR or clear phase commit
- validation notes

Never commit:

- signing secrets
- API keys
- user media
- large generated caches
- DerivedData

---

# 31. GitHub releases

After MVP:

```text
v0.1.0
```

Release assets should include, where practical:

- source code
- packaged `.app` or archive for personal testing
- release notes
- known limitations
- tested macOS version
- tested Mac architecture

Do not block development on App Store submission or notarization.

Signing configuration must not embed private credentials in the repository.

---

# 32. Definition of MVP success

BeatWeave MVP succeeds when a user can do this from a clean launch:

```text
New Project
    ↓
Import several videos
    ↓
Import one music file
    ↓
See waveform
    ↓
Analyze beats
    ↓
See and hear beat alignment
    ↓
Choose "4 beats per clip"
    ↓
Generate AutoCut
    ↓
Play result
    ↓
Trim/split/move individual cuts manually
    ↓
Undo/redo
    ↓
Save project
    ↓
Close and reopen
    ↓
Export H.264/HEVC video
```

No crash.

No source-file modification.

No lost timeline state.

No frozen UI during analysis/export.

Manual correction remains possible at every important automatic step.

---

# 33. First instruction to give Codex

Use this after placing this file in the repository root as `PLAN.md`:

```text
Read PLAN.md completely before making changes.

We are building BeatWeave, a native macOS 27+ video editor centered on
music beat analysis and automatic beat-synced editing.

Start with Phase 0 only.

First inspect the current directory/repository and report the existing state.
Then implement Phase 0 according to PLAN.md.

Requirements:
- Swift 6
- SwiftUI
- native macOS app
- AVFoundation-oriented architecture
- project/document model designed for .beatweave projects
- tests from the beginning
- command-line build and test verification
- keep media/editing logic outside SwiftUI views
- do not start Phase 1
- do not claim manual verification you did not actually perform

After implementation:
1. run build/tests;
2. fix issues;
3. update README/CHANGELOG/docs;
4. show validation results;
5. commit the phase;
6. push to the configured GitHub repository if one exists;
7. stop and wait for the next phase instruction.
```

---

# 34. Recommended development priority

The priority order for BeatWeave is:

```text
Beat accuracy
    >
Timeline correctness
    >
Preview/export consistency
    >
Editing speed
    >
Performance
    >
Advanced effects
    >
AI features
```

A plain editor that cuts accurately on beats is more valuable than a visually impressive editor whose beat analysis and timeline are unreliable.
