# Emperor iOS — parity plan

**Written 2026-09-04**, measured against `Jithro_Android/` at `fc90992` (Emperor 0.3.0) and
`emperor-ai/` as it stands. Every gap below was checked by reading source or running a command,
not recalled. Where this supersedes [GAPS.md](GAPS.md), that is said.

This is the plan to make iOS match the Android client and the shipping web surface. It is
ordered by dependency first and value-per-day second.

**Headline: the feature gap is small and runs both ways. The readiness gap is absolute.**
Android has 1,002 core tests, 146 on-device tests, 34 emulator screenshots and an installable
APK. iOS has 618 passing core tests and a UI layer that has never reached a compiler.

---

## Phase 0 — Make it compile

**Nothing in this document counts until this passes.** Four files, two causes, both confirmed
by reading the source on 2026-09-04.

| # | Error | Files |
|---|---|---|
| 1 | `no such module 'EmperorCore'` | [CourtSearchView.swift:2](Emperor/Features/Cases/CourtSearchView.swift), [DraftHistoryView.swift:2](Emperor/Features/Chat/DraftHistoryView.swift), [EnhancedPromptSheet.swift:2](Emperor/Features/Chat/EnhancedPromptSheet.swift) |
| 2 | `cannot find 'theme' in scope` | [CalendarView.swift:167](Emperor/Features/Calendar/CalendarView.swift) — `ComplianceEventSheet` |

**Cause 1:** [project.yml:38-42](project.yml) compiles `Sources/EmperorCore` *and* `Emperor`
into a single target named `Emperor`. There is no `EmperorCore` module in that build. The other
29 SwiftUI files correctly omit the import; these three are all from the most recent feature
work and were written against the wrong mental model.
**Fix:** delete the three import lines.

**Cause 2:** `ComplianceEventSheet` declares `@Environment(\.dismiss)` but not
`@Environment(\.theme)`, then calls `.background(theme.canvas)`.
**Fix:** add `@Environment(\.theme) private var theme`.

I scanned all 32 SwiftUI files for the second pattern: 3 candidates, 2 false positives
(`EmperorApp` and `RootView` both declare `theme`/`session` as `@State`), 1 real. So the
undeclared-environment class is exhausted.

**These are what `swiftc -parse` cannot see.** It exits 0 on the current tree. Expect a second
round of type errors that only `xcodebuild` will surface — GAPS.md Tier 5 #2 lists the three
classes already found by hand-built repros. Fix, re-run, repeat until green.

**Verification:** push to GitHub and let the `ios` job run. It is already written and has never
executed. Budget two or three iterations.

---

## What "parity" means here

Three denominators, and they are not the same:

1. **The Android client** — the sibling, and the only one of the two that exists as a program.
2. **The web platform's *shipping* surface** — ~170 routes, but `emperor-ai/src/pages/` holds
   ~40 files of which App.jsx imports ~35, and four are `.bak`. The v2 registry replaced them.
3. **Minus what both clients correctly refuse** — unauthenticated routes, the canvas editor,
   admin, billing. Refusing these is not a gap.

**Automation** is the only feature the platform itself marks coming-soon. Neither client can be
penalised for it.

---

## The correction that unlocks the most

[GAPS.md](GAPS.md) Tier 3 rejects, in one line:

> | 30-tool drafting workspace, canvas editing | A contenteditable A4 page with a paginating rail is a different product, not a responsive adaptation. |

**That reason is correct about the editor and wrong about the tools, and the line conflates
them.** They are separate systems on the platform:

- The **canvas editor** is TipTap 3 with tables, pagination and DOCX export. Genuinely a
  different product on a phone. Stay rejected.
- The **tool registry** (`emperor-ai/src/tools/registry.js`, reached at `/w/:toolId`) is the
  platform's *main generation surface*, and each tool is a form, a prompt template, and a
  rendering hint. The compiled prompt goes out as an ordinary `POST /chat` message.
  **`POST /chat` has no tool field.** Nothing server-side is involved.

Android proved this by porting all 29 with no backend change at all
(`core/tools/LegalTools.kt`). That is the largest single parity item available to iOS and it is
blocked on nothing.

**Action: split that Tier 3 row in two.** Keep the editor rejected; move the registry to Tier 2.

---

## Phase 1 — Report an AI answer

**Smallest item with the largest consequence.** iOS has no in-app way to report a generated
answer; Android does, and treats it as a listing requirement for a product that ships AI output.
Apple applies guideline 1.2 to the same class of content.

| | |
|---|---|
| Route | `POST /draft-feedback` — already live, already used by Android |
| Android reference | `core/FeedbackService.kt` (108 L), `ui/chat/ReportAnswerDialog.kt` (132 L) |
| New iOS files | `Sources/EmperorCore/FeedbackService.swift`, `Emperor/Features/Chat/ReportAnswerSheet.swift` |
| Wire body | `{userId, chatId, documentTitle, rating: "down", categories: [...], comment}` |
| Effort | Half a day |

Two details worth copying from Android: the comment is capped at 5,000 characters client-side
(the server truncates rather than rejects, so an uncapped field silently loses the tail), and
the **answer prose is deliberately not attached** — the report carries a chat id, not a copy of
the content.

**Verification:** `HTTPStub` test on the service; the sheet is thin enough not to need one.

---

## Phase 2 — The tool registry (29 tools)

**The biggest parity win in the document, and it needs nothing from the backend.**

Android's port is 2,143 lines across `core/tools/`, and it is almost entirely string templates.
More importantly, **the test fixtures port verbatim**:

```
Jithro_Android/core/src/test/resources/tools/*.txt   60 golden files
Jithro_Android/core/src/test/resources/tool-cases.json  the input values
```

Those were generated by **running the platform's real JavaScript under Node** and capturing the
output. They are plain text — language-neutral. Copy them into
`Tests/EmperorCoreTests/Resources/tools/` and the Swift port is verified byte-for-byte against
the same source of truth, on Linux, with no server and no device.

### Structure

| New file | Ports from | Contents |
|---|---|---|
| `Sources/EmperorCore/Tools/ToolSpec.swift` | `ToolSpec.kt` (107 L) | `ToolFieldType`, `ToolField`, `ToolOutput`, `ToolSpec`, `ToolValues` |
| `Sources/EmperorCore/Tools/Forums.swift` | `Forums.kt` (19 L) | the 8-entry forum list |
| `Sources/EmperorCore/Tools/AnalysisTools.swift` | `BlindSpots`/`Highlighter`/`DocIndex`/`ListOfDates`/`Caseflow` (~1,000 L) | the 5 promoted tools |
| `Sources/EmperorCore/Tools/RegistryTools.swift` | `RegistryTools.kt` (948 L) | the other 24 + `FORUM_FORMATS` |
| `Sources/EmperorCore/Tools/LegalTools.swift` | `LegalTools.kt` (67 L) | the catalogue + `legalTool(id:)` |
| `Sources/EmperorCore/ToolFormViewModel.swift` | — | field state, validation, prompt build |
| `Emperor/Features/Tools/ToolsListView.swift` | `ToolsListScreen.kt` (143 L) | two groups, 29 rows |
| `Emperor/Features/Tools/ToolFormView.swift` | `ToolFormScreen.kt` (250 L) | dynamic form → new conversation |

### Three things Android learned the hard way

1. **`Caseflow` takes a date parameter** rather than reading the clock, specifically so it is
   testable. Keep that — `Date.now` in a prompt builder makes the golden test unpinnable.
2. **`BlindSpots` branches on document kind** (litigation sweep vs contract sweep). It is not
   one template.
3. **Prompts run 15,000–29,000 characters.** Android could not put them in a navigation route
   and built a file handoff (`PendingPrompts.kt`). On iOS this is simpler — a `@State` value or
   the existing navigation path object carries it — but do not put it in a URL.

### Where it lives

Five tabs is the ceiling ([GAPS.md](GAPS.md) "Navigation"). Tools should be a **toolbar item on
Ask**, beside "Your drafts" — the same reasoning that put drafts there: a tool produces a
conversation, so it belongs where conversations are.

**Effort: 3–5 days.** Mostly mechanical translation with a golden test at the end of it.
**Verification:** 60 fixture assertions on Linux. This is the rare feature that arrives fully
tested.

---

## Phase 3 — Chat surface parity

iOS already has: streaming, stop, retry, model toggle, attachments, citations, artifacts,
reasoning panel, web-search toggle, prompt enhancer, **copy**. Three actions are missing.

| Missing | Android reference | Note |
|---|---|---|
| **Edit a question and re-answer** | `EditQuestionDialog.kt` (95 L) | Must state the discard count out loud — re-answering drops every turn after it, and `POST /chat` persists exactly what you send |
| **Export an answer as PDF** | `share/PrintAnswer.kt` (94 L) | Android routes through the print framework rather than hand-rolling a text-flow engine. On iOS this is `UIPrintInteractionController` or a `PDFDocument` render of the same HTML |
| **Change page size** on an artifact | `ArtifactScreen.kt` | A4 vs Letter, and the export must honour it |

Note one thing Android does that iOS should copy in the export path: it prints **black on white
regardless of theme**, and the disclaimer travels with the document. Both are pinned by
instrumentation tests.

**Effort: 2 days.** **Verification:** view-model tests for the edit-and-discard arithmetic; the
print path needs a device.

---

## Phase 4 — Background upload (Tier 1 #7)

The last open Tier 1 gap, and the one place Android is unambiguously ahead on engineering
rather than scope. Android: `UploadWorker.kt` (531 L), `UploadQueue.kt` (311 L),
`UploadStore.kt` (217 L), `UploadRecord.kt` (162 L), plus a `dataSync` foreground service and 7
on-device tests.

iOS needs `URLSessionConfiguration.background(withIdentifier:)` plus the app-delegate completion
hook. **Do this on a Mac.** GAPS.md is right that writing it blind is the wrong call: it cannot
be exercised on Linux and its failure mode is a 200-page scan lost silently.

Two design points worth stealing from Android:

- **`UploadRecord` has no `PAUSED` state.** A paused, killed or cancelled upload lands in
  `QUEUED`, because recovery is identical — re-enqueue the same id. `FAILED` means a retry
  cannot fix it. Fewer states, fewer wrong transitions.
- **The token is captured while foregrounded.** Android needs this because Keystore reads are
  blocked with the screen off; iOS's `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  ([Keychain.swift](Emperor/App/Keychain.swift)) has exactly the same property. A background
  upload that wakes on a locked phone cannot read the token. Hand it to the task.

**Effort: 2 days on a Mac.**

---

## Phase 5 — On-device PDF tools

The last open Tier 2 item, and **easier on iOS than it was on Android**. Android had to bundle
PDFBox (3.2 MB, and it drags in 8.3 MB of BouncyCastle post-quantum crypto — a quarter of the
26 MB APK). PDFKit does structural page insert and remove natively, in the OS.

Match Android's scope: **Split** (extract pages / ranges / every page / by size), **Merge**
(reorder, remove, clear), **Compress** (image, target KB).

Port `PageRanges.kt` (182 L) — it parses `1-3, 5, 8-10`, is 1-based throughout, and has 33
tests. Straight translation.

The rule Android pinned with a device test and iOS should too: **the output must still be a
text PDF, not a picture of one.** Rasterising destroys search, selection and OCR, and usually
makes the file larger.

**Effort: 2 days.** **Verification:** `PageRanges` tests run on Linux; the PDFKit half needs a
device.

---

## Phase 6 — Projects

Eight routes, live and working, read-only on Android. [GAPS.md](GAPS.md) Tier 3 rejects it as
"deliberately unlinked on the web too, while it is trialled" — which was true and is a
reasonable reading, but Android shipped it read-only anyway and the API is ungated.

**Recommendation: build it read-only, matching Android.** `GET /projects`, `GET /project`.
Android's `ProjectDetailScreen` keeps the project's own timeline and the linked scraped case's
history as **two separate sections rather than interleaving them**, which is the right call —
the web interleaves and it reads as one chronology when it is two.

Skip the write half (`POST /project`, `/project-update`, `/project-file`, `/project-chat`)
until the feature is out of trial on the web.

**Effort: 2 days.**

---

## Phase 7 — MCA Registry

An offline CIN/LLPIN decoder. **No backend routes exist for it at all** — the web page is built
on `/auction-notices` plus client-side decoding. Android's `Cin.kt` is 660 lines of decode
tables with 63 tests.

Mechanical port, fully testable on Linux. Copy Android's discipline on the edges: uppercase the
input, count down while half-typed, and show an **unrecognised registrar raw rather than
guessing**.

**Effort: 1–2 days**, almost all of it transcription.

---

## Phase 8 — Reconsider three refusals

iOS and Android read the same backend source and reached **opposite conclusions three times**.
This is a product decision, not an engineering one, and it should be settled centrally rather
than per-client.

| Route | Android | iOS today |
|---|---|---|
| `/delete-file`, `/delete-folder` | refuses — unauthenticated, recursive, no undo | **ships full CRUD** |
| `/auction-watchlists` | refuses — built and held | **ships** |
| `/ocr-history` | ships | refuses — returns every user's jobs |

Both agree on `/calendar/my.ics` and chat sharing.

The routes are open to any caller regardless of what a client does, so neither position is
indefensible. But `delete-folder` is recursive with no undo and takes the user id from the
request body — iOS is offering a destructive action the server will not authorise. **Either
iOS should hold it as Android does, or Android should ship it.** Pick one.

---

## Phase 9 — Web-platform surface neither client has

Ordered by what actually helps on a phone.

| Feature | Routes | Verdict |
|---|---|---|
| **Pre-upload duplicate check** | `POST /check-duplicates` | **Build.** Returns `content-dupe` / `name-conflict` / `new`, and it is one of the few routes that uses the *verified* identity rather than a body `userId`. Cheap, and prevents the most common DMS mess |
| **Preferred model** | `GET /preferred-model`, `POST /set-preferred-model` | **Build the read at least.** Neither client calls the setter; iOS already has a per-chat toggle, so this is just honouring the account default on launch |
| **Teams** | `GET/POST /teams`, `/team-invite` | **Defer.** Cases already resolve across teams; explicit management is a desktop errand |
| **Office preview** | `/office-preview`, `/office-preview-pdf` | **Build later.** A `.docx` in the library currently cannot be viewed at all. Note it answers `200 {success:false}` on failure |
| **Multi-file ZIP download** | `POST /download-files` | **Skip.** A zip on a phone has nowhere useful to go |
| **Filing assembly** | 14 routes | **Stay rejected.** GAPS.md's reason holds — a wrong folio gets the matter rejected at the registry |
| **Deep research** | `POST /deep-research` | **Stay rejected.** One socket, 1–10 minutes, no job id, no poll, no resume. Backend blocker, not client |
| **Role personas** | client-side | **Defer.** 7 personas × 12 practice areas is a card-deck UI; the 3 wire values already work and Android skipped it too |
| **Canvas editing** | `/save-document` | **Stay rejected** |
| **Admin, billing** | 11 + `/checkout` | **Stay rejected** |

---

## Small corrections

- **`FolderName.sanitized` walks `Character`s, not UTF-16 code units.**
  [FileManagementService.swift:231](Sources/EmperorCore/FileManagementService.swift) — I
  reproduced the divergence in Swift: it disagrees with the server on 3 of 6 test names,
  including Devanagari and emoji (`देवनागरी.pdf` → 5 underscores against the server's 8).
  **Low severity** — this one only drives a folder-name preview string, and
  [UploadService.swift:69](Sources/EmperorCore/UploadService.swift), which is the path where a
  mismatch means polling a name that never appears, correctly walks `.utf16`. Fix it anyway and
  pin it with a test, as Android did.
- **`POST /move-file` is implemented and unwired.** `FileManaging.move(name:from:to:)` has no
  caller and no UI. Either surface it or delete it.
- **Doc drift.** `README.md`'s "Still to do" claims the file library is picker-only and that
  markdown artifacts render as monospace; both are contradicted by shipped code. `REPORT.md`
  and `ROADMAP.md` both say 151 tests; the real number is 618. Android has the identical
  problem in the other direction — its README understates four shipped features. Fix both.
- **`CLAUDE.md:54`** says origin is `/srv/git/Emperor.git`; it is `/srv/git/Jithro.git`.

---

## What only the backend can unblock

Consolidated from [GAPS.md](GAPS.md) Tier 4 and `Jithro_Android/BACKEND_REQUESTS.md`. **These
affect both clients**, and the first one blocks listing on both stores.

| # | Change | Why | Size |
|---|---|---|---|
| 1 | `POST /delete-account` | **Store blocker, both platforms.** No delete route, no logout, no token revocation. 21 tables carry a user column | Half a day |
| 2 | Token check on `/calendar/my.ics` | Any user's hearing and limitation dates, keyed on a sequential integer | 2 lines |
| 3 | Token check on `/auction-watchlists` | Which companies a firm is tracking — litigation strategy, not a preference | 4 lines |
| 4 | Token check on `/delete-file`, `/delete-folder` | Destructive, recursive, unauthenticated | 4 lines |
| 5 | `POST /unshare-chat` + a CSPRNG share token | Currently `Math.random()` twice-concatenated, and once shared a chat is public forever | 1 hour |
| 6 | `DELETE /chat`, `POST /rename-chat` | Otherwise mobile chat management has to go through `POST /sync`, which would delete every conversation the phone had not loaded | 1 hour |
| 7 | `diaryNumber` in the `save-case` `extId` tuple | Every NCLAT case computes `ext_id = "trib-nclat\|\|\|"`; a team can hold exactly one | **1 line** |
| 8 | `page_number` in Chroma metadata | Without it the model cannot pin-cite from a vector hit — the product's central claim | — |
| 9 | Push infrastructure | The in-app feed works; the lock-screen half does not exist | — |

Items 2–4 are **nine lines total** and close three live exposures. `requireAuth` is already
imported at `sync-server.js:35` and never called.

---

## Ordering

```
P0  Compile ........................... blocks everything          1 day + iterations
P1  Report an answer .................. store requirement          0.5 day
P2  Tool registry (29) ...............  largest win, 0 backend     3–5 days
P3  Chat parity (edit, export) ........                            2 days
P5  PDF tools ........................  last Tier 2                2 days
P7  MCA Registry .....................  mechanical                 1–2 days
P6  Projects (read-only) .............                             2 days
────────────────────────────────────── Linux-verifiable to here
P4  Background upload ................  needs a Mac                2 days
P9  check-duplicates, preferred model, office preview              3 days
P8  Settle the three refusals ........  a decision, not a task     —
```

**Roughly three weeks of client work to reach and pass Android**, of which everything except
Phase 4 and the device half of Phases 3 and 5 is verifiable on Linux.

The sequencing matters more than the total. P0 is a gate. P1 is small and gates the store. P2
is where the parity gap actually closes — 29 features, no backend, and it arrives with 60
golden fixtures already written.
