# Emperor iOS — Status, Platform Analysis, and the v1 Build Plan

Written 2026-08-26. Supersedes the planning half of `ROADMAP.md`; §1 of that file remains a
readable narrative, but where the two disagree **this document is the later verification** and
says so explicitly in §C.

**Method.** The iOS figures are measured against the working tree. The platform findings come
from a source-only audit of `../emperor-ai/` — five parallel passes over routes/auth, the data
layer, background jobs and notifications, the web frontend, and the chat wire contract. The
platform snapshot has no `node_modules`, no database and no `.git`, and **cannot be run**;
nothing was executed and every platform claim carries a `file:line` citation. Where a figure
could only come from a database that is absent, it is labelled an unverified documentation
claim.

---

# BUILD STATUS — updated 2026-08-26

Phases 1 through 5 are **built and verified on Linux**. Phase 0 is backend work and was not
attempted: `../emperor-ai/` is a read-only snapshot with no `node_modules` and no database, so
no change there could be verified, and unverifiable edits to production backend source are
worse than none.

| Phase | State | Evidence |
|---|---|---|
| P0 Backend | **Not done** — server work, unverifiable here | — |
| P1.1 Get it building | `xcodegen generate` **verified on Linux**; type-check still needs a Mac | 71 files reach the target |
| P1.2 Wire bugs | Done | `ChatStreamParserTests` 16, `StreamContentTests` 20 |
| P1.3 HTTP layer | Done | `APIClientTests` 12, `ServiceWireTests` 15 |
| P1.4 Environments | Done | `APIEnvironmentTests` 9 |
| P1.5 Load states | Done | `LoadStateTests` 11 |
| P1.6 Offline cache | Done | `ResponseCacheTests` 10 |
| P1.7 CI | Done | `.github/workflows/ci.yml` |
| P2 Cases + cause list | Done | `CaseModelTests` 18, `CaseViewModelTests` 14, `CauseListViewModelTests` 15 |
| P3 Notifications | Done (in-app; push needs P0.5) | `NotificationTests` 15 |
| P4 OCR + translate | Done | `OCRTests` 15 |
| P5 Calendar | Done (no reminders — see below) | `CalendarTests` 14 |
| P6 Polish | Partly | markdown tables, accessibility, empty/failure states |
| P7 Release | Partly | privacy manifest, disclaimer, Settings; signing needs a Mac |

**389 tests, 0 failures.** 40 core files (~6,250 lines), 24 app files (~2,900), 28 test files
(~5,050).

## Verification used

Two gates, both in CI:

- `swift test` — full semantic verification of `Sources/EmperorCore`.
- `swiftc -parse` over `Emperor/**/*.swift` — syntax-only, but it runs without the iOS SDK and
  catches every unbalanced brace and malformed builder body. It does **not** type-check.

The gap between them is real and was demonstrated twice: two genuine compile errors
(a `@Sendable` closure capturing a `@Bindable` local; a non-`Sendable` `UserDefaults` in a
`Sendable` struct) parsed cleanly and were found only by an audit that reproduced each
construct against `swiftc -swift-version 6 -typecheck`. **The SwiftUI layer is still not
type-checked.** P1.1 remains the largest unknown in this plan.

## Two live bugs found and fixed

1. **`<truncate:N/>` sliced the wrong buffer.** The server computes `N` over `fullContent`,
   which receives content deltas only and never the `<think>` blocks written alongside them
   (`OpenRouterProvider.js:528, 616, 642`). `ChatStreamParser.raw` carried those blocks, so a
   rollback cut earlier than intended and **deleted real answer text** — on the `thinking`
   model only, which is why no test caught it. Fixed by translating the offset through the
   reasoning spans.
2. **A token-truncated draft was reported as complete.** `/chat`'s `onDone`
   (`sync-server.js:7797`) discards the provider's `status`/`incomplete` verdict, so a draft
   stranded inside an unclosed `<canvas_content>` is persisted with no marker and
   `/stream-status` says `done:true, incomplete:false`. The client now re-derives the
   provider's own `unclosedBlock` test instead of trusting the server's word.

## Deliberate omissions, and why

These are features the backend cannot honour. Shipping them would be a promise the product
does not keep, so each is left out with the reason recorded in source:

- **No reminder picker on the diary.** `compliance_events.remind_days` is written, returned and
  rendered — and read by nothing. No scheduler scans it, the `reminder` notification type has
  no producer, and the ICS feed emits no `VALARM`. The sheet says so in its footer rather than
  offering a control that does nothing.
- **No in-app calendar subscription link.** `GET /calendar/my.ics` is keyed only on `?userId=`,
  making the URL a permanent unrevocable bearer credential for a whole calendar.
- **No OCR history list, and no "clear history".** `GET /ocr-history` returns **every user's**
  jobs and `GET /ocr-download` serves **any user's** output to anyone, with no auth and no
  ownership check; output filenames are guessable and collide silently. `POST /ocr-clear` wipes
  the map for the entire installation. The app tracks only the job it started.
- **No auction screen.** The `auction` notification's own `link` points at an API path with no
  UI route, so tapping it currently lands on NotFound. The client intercepts the link rather
  than following it.
- **No `reminder` or `system` notification types in the UI.** Whitelisted server-side, but
  neither has a producer anywhere in the repository.
- **No Corporate Calendar.** It reads company profiles from browser `localStorage` with no
  server representation, so an iOS client would render it permanently empty.
- **No pricing or upgrade surface anywhere**, keeping the StoreKit obligation from attaching.

## What still needs a Mac

- `xcodegen generate`, then the first real type-check of the SwiftUI layer (P1.1.3).
- Device run: VisionKit needs a camera; `WKWebView`, PDFKit and Keychain have never executed.
- Signing, archive, TestFlight, submission.
- Verifying the eight pre-existing features against production for the first time (P1.1.6).


---

# PART A — What exists today (iOS, as of the original audit)

## A.1 Headline

| | |
|---|---|
| Swift files | **31** — 21 core, 10 app |
| Lines of core logic | ~3,200 |
| Lines of SwiftUI | ~1,280 |
| Lines of test | ~2,130 |
| Tests | **151, all passing** |
| Test runtime | 1.1 s from a clean build |
| Toolchain verified | Swift 6.3.3, `x86_64-unknown-linux-gnu` |
| Buildable on Linux | Core + tests only |
| Buildable on a Mac | **Unverified — never compiled** |
| Backend endpoints consumed | **10 of 169** |
| CI | **None** |
| Git | 11 commits, origin `/srv/git/Emperor.git`, working tree dirty |

## A.2 Architecture

Two layers, one rule: *a view holds no logic worth testing.*

- **`Sources/EmperorCore/`** — Foundation-only. No UIKit, no SwiftUI, no Security framework.
  Compiles and tests on Linux, so wire-format edge cases are pinned by tests rather than
  discovered on a device.
- **`Emperor/`** — what genuinely needs UIKit, SwiftUI, WebKit, PDFKit, VisionKit or Keychain.

`project.yml` compiles `Sources/EmperorCore` directly into the app target, so tested code and
shipped code are the same bytes.

Five protocol seams let every screen run with no server: `ChatProviding`, `ChatListProviding`,
`FileProviding`, `UploadProviding`, `CredentialStore`.

## A.3 Core inventory — 21 files

**Wire format and transport**

| File | Lines | Purpose |
|---|--:|---|
| `ReasoningTracker.swift` | 356 | Plan progress + agentic work log. Port of `src/lib/streamManager.js`. |
| `APIModels.swift` | 340 | Codable models + `WireDate` (three timestamp encodings). |
| `StreamContent.swift` | 322 | Decomposes an answer into prose, artifacts, citations, reasoning, errors. |
| `ChatStreamParser.swift` | 219 | Parses the `/chat` wire format. Two layers, matching the server's ordering. |
| `APIClient.swift` | 179 | HTTP layer. Injects bearer token **and** `userId` on every request. |
| `ChatOptions.swift` | 91 | `ChatModel` / `ChatRole` — the allowed wire values. |
| `JSONValue.swift` | 73 | Permissive JSON for the two schemaless payloads. |
| `IncrementalUTF8Decoder.swift` | 48 | Decodes byte chunks without splitting multi-byte characters. |

**Services**

| File | Lines | Purpose | Seam |
|---|--:|---|---|
| `ChatService.swift` | 314 | History, streaming turns, rejoin, reasoning snapshots | `ChatProviding`, `ChatListProviding` |
| `UploadService.swift` | 216 | Resumable chunked upload + ingestion polling | `UploadProviding` |
| `FileService.swift` | 146 | Document tree, search, citation resolution, download | `FileProviding` |
| `AuthService.swift` | 51 | Login, register, sign-out | — |
| `CredentialStore.swift` | 42 | Token persistence abstraction + in-memory impl | `CredentialStore` |

**View models and presentation**

| File | Lines | Purpose |
|---|--:|---|
| `ChatViewModel.swift` | 316 | Turn state, in-flight recovery, completeness confirmation, citation resolution, scan attachment |
| `Session.swift` | 120 | Auth state, session restore, owns the shared `APIClient` |
| `FileLibraryViewModel.swift` | 115 | Search, grouping by matter, selection reconciliation |
| `SourceDocumentViewModel.swift` | 88 | Cited-document fetch, titles, 1-based → 0-based page mapping |
| `ChatListViewModel.swift` | 56 | Conversation list, loading/empty-state rules |
| `ScannedDocument.swift` | 40 | Scan bundle, naming rule, `ScanError` |
| `ArtifactDocument.swift` | 35 | Page wrapper for a drafted HTML fragment |
| `DisplayText.swift` | 30 | Filename un-sanitising and error wording |

## A.4 App layer — 10 files

| File | Lines | Needs |
|---|--:|---|
| `ChatThreadView.swift` | 363 | SwiftUI |
| `ReasoningPanel.swift` | 181 | SwiftUI |
| `FileLibraryView.swift` | 151 | SwiftUI |
| `ArtifactView.swift` | 125 | WebKit |
| `SourceDocumentView.swift` | 109 | PDFKit, UIKit |
| `ChatListView.swift` | 104 | SwiftUI |
| `LoginView.swift` | 100 | SwiftUI |
| `DocumentScannerView.swift` | 73 | VisionKit |
| `Keychain.swift` | 46 | Security |
| `EmperorApp.swift` | 31 | SwiftUI |

## A.5 Tests — 151 across 13 suites

| Suite | Tests |
|---|--:|
| `ReasoningTrackerTests` | 17 |
| `ArtifactAndMentionTests` | 16 |
| `FileLibraryViewModelTests` | 15 |
| `ChatViewModelTests` | 14 |
| `StreamContentTests` | 14 |
| `ChatStreamParserTests` | 13 |
| `ChatCitationAndScanTests` | 12 |
| `APIModelTests` | 11 |
| `FileServiceTests` | 10 |
| `SourceDocumentViewModelTests` | 10 |
| `PresentationTests` | 8 |
| `SessionTests` | 6 |
| `ChatListViewModelTests` | 5 |

### Coverage gaps

| Not covered | Consequence |
|---|---|
| **`APIClient` — no HTTP-layer tests at all** | Request construction is unpinned: bearer + `userId` injection, query encoding, the `folderName="."` root rule, error-envelope parsing. `APIClient(config:session:)` already accepts a `URLSession`, so this needs a `URLProtocol` stub, not a redesign. |
| `AuthService` | Zero references; every path is network-bound. |
| `Session.signIn` / `.register` | Go through a real `APIClient`; no URL-session seam. |
| `JSONValue`, `IncrementalUTF8Decoder` | No direct tests (the latter is exercised indirectly). |
| **The whole SwiftUI layer** | A *compilation* gap, not a coverage gap. |

## A.6 Working features

Sign in / register with Keychain restore · streaming chat with rejoin after backgrounding ·
model and persona pickers · VisionKit scan → chunked resumable upload → ingestion polling →
auto-attach · document library with search and multi-select · two-stage citation resolution
opening the cited page · artifact rendering with format sniffing · reasoning panel with live
plan progress.

## A.7 Bugs found and fixed during the build

| # | Bug | Consequence had it shipped |
|---|---|---|
| 1 | `Data.suffix(from:)` index-based on a re-sliced `Data` | Crash on every stream containing a multi-byte character |
| 2 | `<truncate:N/>` sliced by `Character` offset | Corrupted any draft containing an emoji or non-BMP character |
| 3 | Filename sanitisation over grapheme clusters | Every Hindi-named upload appears to hang forever |
| 4 | Truncate clamped to buffer length | Stray `<truncate:N/>` rendering as prose |
| 5 | Literal `<` in prose eaten as a partial tag | "damages < 50,000" silently truncated |
| 6 | Only `<think>` stripped | Model's private reasoning shown under five other wrappers |
| 7 | Citation regex required a page *range* | `<@file.pdf:P-5:7>` renders verbatim inside a pleading |
| 8 | Attachments sent only at top level | Bypasses the scanned-document refusal check |
| 9 | Artifact rendered by declared wrapper | A pleading inside `<table_content>` renders as raw tags |
| 10 | Empty state shown before the first load starts | "No conversations yet" flashes on every cold open |

## A.8 Not verified — read before trusting A.6

1. **The SwiftUI layer has never been compiled.** No iOS SDK on the build machine.
2. **No feature has ever run against the live server from the app.** Every wire claim is
   derived from reading platform source and pinned against a fake.
3. `xcodegen` is not installed; `Emperor.xcodeproj` has never been generated.
4. No device or simulator run. VisionKit, WKWebView, PDFKit and Keychain have never executed.
5. The base URL is hard-coded with no environment switch.

## A.9 Endpoints consumed — 10

`POST /login` · `POST /register` · `GET /chats` · `GET /messages` · `POST /chat` ·
`GET /stream-status` · `POST /upload-chunk` · `GET /upload-status` · `GET /user-files` ·
`GET /view-file`

---

# PART B — Platform analysis

## B.1 What the product is

A legal-AI platform for Indian litigation and corporate practice. A React SPA (Vite) talks to
a single Node process, `sync-server.js` — **852 KB, ~13,665 lines**, raw `http.createServer`
with one `if/else if` chain on `urlPath` (`sync-server.js:6129`). No Express, no router, no
middleware. Data is SQLite via `better-sqlite3`; retrieval is ChromaDB with BGE-M3 embeddings.

## B.2 Processes

`ecosystem.config.cjs` declares six apps. Three are documented as **opt-in, not autostarted**
(`ecosystem.config.cjs:35,45`): `court-scraper`, `compliance-scheduler`, `compliance-api`.

`court-scraper` is the only timer-driven notification producer: a 30-minute `refreshTick` and a
45-minute `ibbiAuctionsTick` (`court-scraper/index.js:17-18`). **The dev config omits it
entirely** — so `dev.emperorailabs.com`, which the iOS app currently targets, generates zero
notifications by construction.

Production also omits `bge-embed`, the local embedder, which only the dev config declares
(`ecosystem.dev.config.cjs:37-40`). If prod runs `ecosystem.config.cjs`, `embedLocal()` fails
on every call and all embedding silently bills through OpenRouter.

## B.3 API surface — 169 endpoints

| Auth class | Count | Meaning |
|---|--:|---|
| UNAUTHENTICATED | **81** | Trusts a client-supplied `userId` from query or body |
| PUBLIC | 57 | No identity read at all |
| TOKEN-PREFERRED | 25 | Verifies a token *if present*; falls back to client `userId` if the header is omitted |
| LOOPBACK | 4 | Gated on a `127.0.0.1` peer |
| **TOKEN (hard)** | **2** | Rejects without a valid token |

By feature area: court lookup 26 · files/DMS 22 · filing 20 · admin 18 · chat 15 · cases 8 ·
projects 8 · reference library 8 · misc 8 · auth 7 · OCR 6 · calendar 5 · auctions 5 ·
notifications 4 · teams 3 · documents 3 · billing 2 · cause list 1.

## B.4 Security

The blocking issue for App Store submission, and worse than previously recorded.

**1. Admin authentication is bypassable by anyone.** `isAdminUser` takes a *user id*, not a
request (`sync-server.js:3870-3872`), and all 14 admin call sites pass a client-supplied value.
`GET /api/admin/users?userId=<any admin's integer id>` returns the full user table to an
anonymous caller. `POST /api/admin/add-user` creates accounts. `POST /api/admin/smtp` rewrites
mail credentials. Admin ids are small integers. Two routes (`:6162`, `:6210`) *do* use
`getUserFromRequest` correctly, which proves the right check was to hand.

**2. `requireAuth` has zero call sites.** Imported at `sync-server.js:35`; a repo-wide grep
finds only the import, the definition, and comments admitting it is never called.

**3. CORS `*` plus identity-in-query-string is itself the exfiltration vector.**
`Access-Control-Allow-Origin: *` is set unconditionally on every response
(`sync-server.js:6140-6142`). Because identity travels as a query parameter, a cross-origin
`GET` is a CORS-*simple* request — no preflight, no credentials. Any web page can
`fetch('.../api/user-files?userId=1216')` and read the JSON. `Allow-Headers` omits
`Authorization`, so the *correct* credential is the only thing CORS blocks.

**4. Three of five credential write paths store plaintext.** A `scrypt` helper exists
(`src/lib/authToken.js:127`) and is used by `/register` and the login lazy-upgrade. Not used by
`POST /reset-password` (`sync-server.js:10519` — which actively *downgrades* an already-hashed
account), `POST /admin/add-user` (`:8629`), or the boot seed (`:4144-4146`, which contains a
hardcoded live admin credential committed in source).

**5. Plaintext secrets in SQLite columns.** Every provider API key via `app_settings`
(`sync-server.js:10457`), and `smtp_config.password` (`:3562`).

**6. `/documents/content` has no owner predicate at all** — `SELECT content FROM
canvas_documents WHERE id = ?` (`sync-server.js:10640`). A token check is necessary but not
sufficient there.

**7. `lib/filing/` is not a correct template.** Its `resolveUserId` falls back to the
client-supplied id when no token is present (`lib/filing/index.js:92-93`); an attacker simply
omits the header. The module's own comment admits this.

**8. The server binds `0.0.0.0`** (`sync-server.js:13623`), so port 3001 is reachable on any
exposed interface, bypassing nginx and its proxy headers.

**9. The dev tunnel carries real client matters with no Access policy** —
`ecosystem.dev.config.cjs:9-16` states this plainly in its own header.

**One piece of good news:** `src/main.jsx:34-61` already monkey-patches `window.fetch` to
attach `Authorization: Bearer` to every `/api/` request. **Clients already send tokens.** The
gap is entirely server-side, so the fix needs no client migration, and
`REQUIRE_UPLOAD_AUTH` (`sync-server.js:313`, currently defaulting off) can be flipped now.

## B.5 Data model — 43 tables across two SQLite files

`Data/database.db` (primary, `sync-server.js:1240`) and `compliance.db` (`db/index.js:6`). The
server opens both; no schema doc acknowledges the split.

**Dead tables (5):** `feedback` and `google_file_registry` have zero writers. `document_fts` is
created, deleted from, renamed and audited but **never populated and never queried** — its only
writer, `src/lib/librarian.js:124`, was deliberately dropped. `company_events` has zero
writers; `companies` is written only by verification scripts.

**Live but unreachable (4):** the `projects` family. Full CRUD exists
(`sync-server.js:9924-10203`) but `src/App.jsx:150-153` states it is deliberately unlinked —
no home card, no sidebar entry, no palette action — "reachable only by typing /projects".

**Write-only (1 column):** `compliance_events.remind_days`. Written (`sync-server.js:10264`),
displayed back as a "{n}d before" chip (`MyCalendar.jsx:409`), read by nothing. No scanner, no
`VALARM` in the ICS feed, and the `'reminder'` notification type has zero producers.

**Declared column types are unreliable** by the code's own admission
(`sync-server.js:3622-3635`): `CREATE TABLE IF NOT EXISTS` statements against pre-existing
tables never executed, so their declared types "are fiction". Note `notifications.user_id` is
TEXT while `users.id` is INTEGER; the codebase coerces at each join.

**Row counts in the docs are unverified.** The database is absent from the snapshot. Claims
such as "31 users, 199 cases, 1,355 conversations"
(`marketing/product-brief-digital-marketing.md:198`) have no data behind them here. Several
docs are provably stale: `ARCHITECTURE.md:14` and `PROJECT_DETAILS.md:194` both describe
`sync-server.js` as "~3,900 lines" — off by 3.5×.

## B.6 Ingestion and retrieval

Upload → hash → dedupe → disk → **HTTP 200 returned here** → durable `ingest_jobs` row →
extraction (`extract_hybrid.py`, per-page text layer, OCR fallback via Gemini) → chunking
(800/150) → BGE-M3 embedding → Chroma upsert → `document_page_index` → knowledge index.

Retrieval is Chroma only, two mechanisms: Pre-RAG metadata injection (`collection.get`, no
embedding) and the `search_knowledge_base` tool (true dense search). **No hybrid fusion, no
reranker.**

**A gap that undercuts the product's core claim:** `page_number` is never written to Chroma
metadata on any normal ingest path (`sync-server.js:4950, 6011, 6098, 6643, 6986, 11905` all
build `{userId, folderName, fileName, chatId}`). Only the scanned-page path sets it (`:1813`).
So `search_knowledge_base` returns `page_number: 'Unknown'` for every text document (`:2189`) —
the model cannot pin-cite a page from a vector hit. Citations still work when sourced from
Pre-RAG or the page-reading tool, which read `document_page_index`.

## B.7 Notifications

`createNotification` (`lib/notifications.js:55`) is the **sole** `INSERT INTO notifications` in
the repo. Four producers: court refresh (`hearing`/`order`/`status`), IBBI auction watchlist
(`auction`), team invite and case-added (`team`). The types `reminder` and `system` are
whitelisted and rendered but **have no producers**.

Delivery: in-app polling only. `NotificationBell.jsx:36-41` polls the unread *count* every 60 s
and fetches the list lazily on open. `window.Notification` fires only when the tab is hidden —
no service worker, so it dies with the tab.

Email exists (`lib/email.js`, 7 templates) but `smtp_config.enabled` defaults to `0` with a
NULL host (`sync-server.js:3559-3565`), so every send short-circuits.

**Push does not exist.** An exhaustive grep for
`apns|web-push|firebase|fcm|serviceWorker|pushManager|vapid|device_token|…` across all source
extensions returns **zero matches**. No manifest, no service worker, no PWA plugin, no push
dependency in `package.json`.

The `auction` notification deep-links to `/auction-notices/:id`, but the route is
`/liquidations` (`src/App.jsx:155`) — every auction notification currently lands on NotFound.

## B.8 Court coverage

| Tier | Coverage |
|---|---|
| Supreme Court | Captcha-free refresh via `get_case_details` |
| HC dedicated | 6 registry entries — Delhi, Punjab & Haryana, Bombay, Karnataka, Madras, Allahabad |
| HC generic | 25 state codes via the eCourts aggregator — **status disputed, see §F** |
| Tribunals | 10 modules — TDSAT, NGT, APTEL, DRT, DRAT, ITAT, AFT, CESTAT, CAT, SAT |
| Consumer fora | NCDRC / SCDRC / DCDRC |
| NCLT / NCLAT | Yes |
| District | **Adapter exists (43 KB) but is wired nowhere** |

Known-degraded, per the adapters' own headers: ITAT ~50% end-to-end even with 8 retries
(`tribunal-registry.js:52-65`); Allahabad "slow/flaky (~40–80 s/request)" (`hc-registry.js:69`);
Bombay Original Side is a known gap; AFT is Principal Bench Delhi only.

The `scrape_jobs` queue is effectively dead: its sole adapter unconditionally throws unless
`SCRAPER_FIXTURE=1` (`adapters/supremecourt.js:64-65`). The live path is
`/court/sc/auto` (`sync-server.js:9438`), which runs in-process with a trained captcha solver.

## B.9 Web feature inventory and mobile fit

| Feature | Live | Mobile fit |
|---|---|---|
| AI chat | ✅ | **HIGH** |
| Cause list | ✅ | **HIGH** — the single highest-value screen |
| Cases (read) | ✅ | **HIGH** |
| Notifications | ✅ | **HIGH** |
| OCR & translate | ✅ | **HIGH** — the most phone-native feature in the product |
| My Calendar + `.ics` | ✅ | **HIGH** — native Calendar subscription |
| Files / DMS (capture + read) | ✅ | **HIGH** |
| File viewer | ✅ | **HIGH** |
| Library / History | ✅ | **HIGH** |
| Export Word/PDF via share sheet | ✅ | **HIGH** |
| Case workspace (13 tabs) | ✅ | MEDIUM — read yes, enter rows no |
| Court case search | ✅ | MEDIUM — SC needs manual CAPTCHA |
| Liquidations / MCA registry | ✅ | MEDIUM |
| PDF tools (split/merge/compress) | ✅ | MEDIUM — fully client-side |
| Tool workspace (30 drafting tools) | ✅ | **DESKTOP-ONLY** — hardcoded 380 px rail, no breakpoint |
| Document canvas editing | ✅ | **DESKTOP-ONLY** |
| Filing assembly | ✅ | **DESKTOP-ONLY** |
| Corporate calendar | ✅ | **DESKTOP-ONLY** — and see below |
| Admin hub | ✅ | **DESKTOP-ONLY** |

**Corporate Calendar cannot be ported at all**: company profiles live in `localStorage` only
(`ComplianceCalendar.jsx:111-112`), with no server representation. An iOS client would see no
companies and therefore an empty calendar.

**Registration is dead.** `Register.jsx` has no importer and no route — there is no self-signup
path in the product, though `POST /register` exists server-side.

**Sharing has no producer.** `/share/:shareId` renders, but `shareChat()` (`api.js:398`) has
zero callers.

## B.10 Prominent but broken

A partial list, ordered by how badly each would mislead a user:

1. **A failed fetch renders as "you have nothing."** `store.js:1051-1055` (cases),
   `:1065-1070` (cause list) and `:1217-1219` (compliance) all catch the error and then set
   `*Loaded: true`. So on a server error, `TodayCauseList.jsx:285` **tells a litigator their
   court day is clear.** This is the single most dangerous pattern in the frontend and must not
   be reproduced on iOS.
2. **A fully convincing fake upload ships in the bundle.** `runSimulatedUpload`
   (`uploadQueue.js:174-209`) animates progress and ETA and marks files `done` without sending
   a byte.
3. **Research Sources menu is decorative** — writes to the store; nothing reads it. Its own
   source admits it (`ResearchSourcesMenu.jsx:82-84`).
4. **Chat-feedback intake is severed** — the only writer calls `POST /submit-feedback`, which
   is absent from the server's dispatch table.
5. **"Ask AI about this case" carries no case context** (`CaseWorkspace.jsx:319`).
6. **Compliance History fetches `http://localhost:40010`** (`ComplianceHistory.jsx:30`).
7. **Upload dialog accepts no image formats** on an OCR-centric product
   (`UploadModal.jsx:369`).
8. **`/buy` takes no payment** and says so in its own UI.

## B.11 Chat wire contract — verified

Confirmed against source, and all three previously-suspected hazards hold:

- **`POST /chat` is destructive to history.** `setMessages()` opens with
  `DELETE FROM messages WHERE chat_id = ?` (`sync-server.js:4250`) and re-inserts only what it
  received. The pre-save at `:7712` fires *before* generation, so even an aborted request
  truncates the chat permanently.
- **`role` must be omitted, never sent empty.** `getLeadingIdentity(role = 'Litigator')`
  (`clerk_identity.js:1`) is an ES6 default, which fires only on `undefined`. `role: ""`
  produces "a top-tier, highly experienced , with the precision…". Never validated — any string
  is spliced into the system prompt unescaped, making this the sharpest prompt-injection surface
  in the contract.
- **Attachments must travel in both places** — and it is worse than documented. With
  attachments top-level only, `attachmentsList` is empty, the loop body never executes
  (`:7337`), and the scanned-document denial **silently never fires**.

Wire values: models `fast`, `thinking`, `claude-haiku-4-5`, `claude-sonnet-4-6`, `test`
(admin-only). Roles collapse 7 UI roles → **3 wire values**: `Litigator`, `Corporate Counsel`,
`Judicial Officer` (`src/roles/roleConfig.js`). Neither is validated on `/chat`; an unknown
model string is forwarded to OpenRouter verbatim (`BaseProvider.js:6-8`).

Citation grammar (`lib/filing/registry.js:478`):
`/<@([^:>]+):([A-Za-z]+-\d+)(?::(\d+)(?:-(\d+))?)?>/g` — **a page range is not required**; all
of `<@f.pdf:P-5>`, `<@f.pdf:P-5:7>` and `<@f.pdf:P-5:41-45>` are legal.

**`GET /messages` returns raw `<@…>` tokens** — only the `canvas_documents` copy is stripped
(`sync-server.js:4298`). A client rendering message content directly prints citation tokens
into the pleading.

**`/stream-status` always returns 200**, even for `Missing chatId`, `Missing userId`,
`Forbidden` and `No messages` — `res.writeHead(200)` is written at `:13007`, before any
validation. Branch on the `error` field, never the HTTP status.

**Upload:** `chunkSize` must always be sent. With it, each chunk is written at an absolute
offset and order does not matter; without it the server falls back to append-mode
(`sync-server.js:6842-6846`), which silently scrambles any parallel upload. A 200 on the final
chunk means only "bytes written to a `.part` file" — assembly, verification, rename and
ingestion all happen after the response closes (`:6852-6853`). Poll `/upload-status`; the only
terminal states are `"ready"` and a `ERROR…` prefix.

Filename sanitisation is `[^a-zA-Z0-9._-] → _` (`sync-server.js:288-292`), applied **per UTF-16
code unit** — so a BMP character becomes one `_` and an astral character becomes two.

---

# PART C — Corrections to prior documentation

`ROADMAP.md` was written 2026-08-25 and is broadly sound. This audit changes five things.

| # | ROADMAP says | Verified position |
|---|---|---|
| C1 | "Roughly 40 data routes" take a client-supplied `userId` | **81 UNAUTHENTICATED + 25 spoofable, out of 169 endpoints.** Only 2 hard-require a token. |
| C2 | `lib/filing/index.js` "is the only module that authenticates properly — copy this pattern" | **It does not.** `resolveUserId` falls back to the client id when the header is omitted (`lib/filing/index.js:92-93`). Copy `getUserFromRequest` instead; `sync-server.js:6162` is the correct shape. |
| C3 | Open question: "`projects` is documented as the intended successor to `/cases` — which is the future?" | **Answered: they coexist by design.** `sync-server.js:3377-3388` says projects are "deliberately separate from the `cases` tables rather than an extension of them" — cases are team-scoped and scraper-owned, projects are user-owned and hand-made. **Build iOS on `cases`.** |
| C4 | B8: reset password stored plaintext, "works only because login upgrades it later" | Understated. **Three of five credential write paths bypass `scrypt`**, and reset actively *downgrades* a hashed account. A live admin credential is hardcoded at `sync-server.js:4145-4146`. |
| C5 | Admin routes were not called out as a distinct risk | **Admin auth is bypassable by any anonymous caller** via `?userId=<admin id>` (`sync-server.js:3870`). This is the single most severe finding in the audit and outranks everything in §2.5. |

Two additions with no ROADMAP counterpart:

- **C6 — The web client renders a failed fetch as an empty result**, including telling a
  litigator their cause list is clear. iOS must distinguish "loaded and empty" from "failed".
- **C7 — Per-role prompt guardrails are injected client-side** (`ToolWorkspace.jsx:2437-2474`),
  not server-side. The Judicial Officer guardrail is a compliance boundary forbidding the model
  from drafting judgments, orders, findings, sentencing, bail or interim orders. **iOS exposes
  that role and sends no guardrail.**

---

# PART D — What v1 is

> **A litigator's companion in transit.** It answers "what do I have tomorrow", "what happened
> on my matters", "what does this document say", and "draft me something to review later".

v1 is **read, capture, ask, and be told**. Not an editor, not an administrator.

**In scope:** chat with documents · document capture & upload · document library & viewer ·
cause list · cases (read + two small writes) · notifications with push · calendar ·
OCR/translate · profile & settings.

**Out of scope:** draft editing, filing assembly, the 30-tool drafting workspace, full case
search, projects, teams administration, corporate compliance calendar, admin, billing.

## D.1 Acceptance criteria

v1 is done when all of these hold on a physical device against production:

1. A user signs in, force-quits, reopens, and is still signed in.
2. A streaming answer survives backgrounding the app for 60 s and rejoins on return.
3. A truncated answer is *identified as truncated* — not silently rendered as complete.
4. A paperbook scanned in court appears in the library and is attachable to the next turn.
5. Every citation chip opens the named document at the named page, or says precisely why not.
6. Tomorrow's cause list is visible offline, stamped with when it was fetched.
7. A hearing change fires a push notification that deep-links to the case.
8. **No screen ever renders a network failure as an empty result.**
9. No screen offers a capability the backend does not actually deliver.

---

# PART E — The build plan

Steps are numbered `P<phase>.<group>.<step>` so they can be referenced. Each carries a
**Done when** that is observable, not "implemented". Phase 0 is backend work and is not iOS.

## Phase 0 — Backend unblocking

**Most of v1 is dishonest without this.** Ordered by value per unit of effort.

### P0.1 — Restart the data flow *(config only, ~1 hour)*

- **P0.1.1** `pm2 start ecosystem.config.cjs --only court-scraper` on production.
- **P0.1.2** Confirm a new `notifications` row appears within 30 minutes (one refresh tick).
- **P0.1.3** Decide whether `compliance-scheduler` is wanted. If not, delete it from
  `ecosystem.config.cjs:41-50` rather than leaving a declared process that never runs.
- **P0.1.4** Add `bge-embed` to `ecosystem.config.cjs`, mirroring
  `ecosystem.dev.config.cjs:32-40`, or accept that all embedding bills through OpenRouter.
  Decide deliberately; today it is an accident of config drift.
- **P0.1.5** Add `court-scraper` to `ecosystem.dev.config.cjs` **or** accept that no
  notification work can be tested on dev. If accepted, record it — otherwise Phase 3 will be
  debugged against a system that cannot produce the event being debugged.
- *Done when:* a `notifications` row created after the restart is visible via
  `GET /notifications`, and you know which embedder is serving production.

### P0.2 — Fix the admin bypass *(highest severity, smallest diff)*

- **P0.2.1** Add `isAdminRequest(req)` beside `isAdminUser` (`sync-server.js:3870`), deriving
  identity from `getUserFromRequest(req)` rather than an argument.
- **P0.2.2** Replace all 14 call sites: `sync-server.js:8304, 8346, 8503, 8533, 8557, 8588,
  8619, 10456, 10465, 10474, 10482, 10491, 12586, 12623, 12803`.
- **P0.2.3** Gate the three ungated admin-facing routes: `/feedbacks` (`:8425`),
  `GET /support-feedback` (`:8443`), `/support-feedback-file` (`:8469`).
- **P0.2.4** Delete the hardcoded seed credentials at `sync-server.js:4144-4146`, or move them
  behind an env-gated dev-only branch. **Rotate the `admin@demo.com` password** — it is in
  source history.
- *Done when:* `curl '.../api/admin/users?userId=1'` with no `Authorization` header returns 401.

### P0.3 — Enforce authentication *(the long pole)*

- **P0.3.1** Hoist a single gate above the route chain, after the maintenance check
  (`sync-server.js:6243`). Deny by default; allowlist public paths. `MAINTENANCE_OPEN_PATHS`
  (`:3890-3896`) is almost exactly the right starting list. **This is the first actual call to
  `requireAuth`.**
- **P0.3.2** Make `resolveUserId` strict — delete the `explicitUserId` fallback at
  `lib/filing/index.js:92-93`.
- **P0.3.3** Make `resolveUploadUser` strict — delete the `formUserId` fallback at
  `sync-server.js:317`; flip `REQUIRE_UPLOAD_AUTH` (`:313`) to default on.
- **P0.3.4** Replace client-supplied ids with `caller.id` across the 81 UNAUTHENTICATED
  handlers. The SQL predicates are already correct; they are simply being fed an
  attacker-controlled value. Mechanical, but verify per site.
- **P0.3.5** Add the missing owner predicate to `/documents/content`
  (`sync-server.js:10640`) — `AND user_id = ?`. Audit sibling canvas queries for the same
  omission.
- **P0.3.6** Tighten CORS (`sync-server.js:6140-6142`): replace `*` with an origin allowlist,
  **add `Authorization` to `Allow-Headers`** — without this, P0.3.1 breaks every cross-origin
  client — and add `Vary: Origin`.
- **P0.3.7** Bind to `127.0.0.1` (`sync-server.js:13623`) so nginx is the only ingress.
- **P0.3.8** Put a Cloudflare Access policy in front of `cloudflared-dev`, or stop running it.
- *Done when:* every `/api/*` route except the public allowlist returns 401 without a token,
  and the web client still works end to end.

### P0.4 — Fix the credential paths

- **P0.4.1** `POST /reset-password` → `hashPassword` (`sync-server.js:10519`).
- **P0.4.2** `POST /admin/add-user` → `hashPassword` (`:8629`).
- **P0.4.3** Hash `password_resets.token` at rest (`:3568`, `:10507`).
- **P0.4.4** Move provider API keys and the SMTP password out of plaintext SQLite columns, or
  document the decision to accept it.
- *Done when:* no code path writes an unhashed password.

### P0.5 — Build push infrastructure

- **P0.5.1** Add a `push_subscriptions` table to the schema block (`sync-server.js:3554+`):
  `(id, user_id, platform, token, bundle_id, created_at, last_seen_at, failed_at)`.
  **`user_id` must be TEXT** to match `notifications.user_id`, not INTEGER like `users.id` —
  get this wrong and the join silently returns nothing.
- **P0.5.2** Add `POST /push/subscribe` and `DELETE /push/subscribe`. **Do not copy the pattern
  of the four notification routes** — they authenticate with a bare `userId` param, which would
  let anyone register a device against any account.
- **P0.5.3** Add an outbox table, or a `setImmediate` drain. **`createNotification` is
  synchronous and is called inside a transaction by `fanToTeam`** (`lib/notifications.js:76-82`)
  — awaiting an HTTP send there holds a write lock on a WAL database shared by two processes.
- **P0.5.4** Hook the dispatch at `lib/notifications.js:64`, after the insert. This one seam
  covers all four producers and both module systems.
- **P0.5.5** Add APNs credentials via the `getSetting()` pattern (`sync-server.js:3848`), which
  reads `app_settings` then falls back to env. Clone `smtp_config`'s admin UI if a toggle is
  wanted.
- **P0.5.6** Map the payload: `{type, title, body, link, caseId}` already maps 1:1 onto an APNs
  payload; `link` becomes the deep-link path.
- **P0.5.7** Handle token invalidation — record `failed_at` on a 410 and stop sending.
- *Done when:* a row inserted by `createNotification` produces a device notification on a test
  handset.

### P0.6 — Fix what push would amplify

- **P0.6.1** Fix the auction deep link: `ibbi-auctions-ingest.js:97` emits
  `/auction-notices/:id`; the route is `/liquidations` (`src/App.jsx:155`).
- **P0.6.2** Write `page_number` into Chroma metadata at every ingest site
  (`sync-server.js:4950, 6011, 6098, 6643, 6986, 11905`). Without it
  `search_knowledge_base` returns `'Unknown'` and the model cannot pin-cite from a vector hit —
  which is the product's central claim.
- **P0.6.3** Fix `POST /chat`'s `onDone` (`sync-server.js:7797`) to destructure the provider's
  `status`/`incomplete` verdict instead of discarding it. Today a run ending `status:'length'`
  is persisted as complete with no marker, and `/stream-status` reports
  `done:true, incomplete:false`. **No client can currently detect this.**
- *Done when:* a deliberately token-limited generation is reported `incomplete: true`.

### P0.7 — Build the reminder job *(highest value per line in the whole plan)*

- **P0.7.1** Add a scanner that reads `compliance_events` by `due_date` minus `remind_days` and
  calls `createNotification` with `type:'reminder'`.
- **P0.7.2** Emit `VALARM`/`TRIGGER` blocks in `GET /calendar/my.ics`
  (`sync-server.js:10246`) so a subscribing Calendar also fires.
- **P0.7.3** Fix `DTEND == DTSTART` on all-day events (`sync-server.js:10246`) — an RFC 5545
  violation that iOS Calendar renders inconsistently.
- *Done when:* an event with `remind_days: 3` produces a notification three days before, and
  `remind_days` is no longer a promise the product does not keep.

### P0.8 — Route hygiene *(do last; it touches every route line)*

- **P0.8.1** Anchor the prefix strip at `sync-server.js:6131`:
  `replace(/^\/api(?=\/|$)/, '')`. Today `.replace('/api','')` turns `/apifoo` into `/foo`.
- **P0.8.2** Delete the ~120 dead `|| urlPath === '/api/...'` clauses, unreachable since the
  strip at `:6131`.
- **P0.8.3** Add a `userId` to the OCR routes so cost is not recorded against NULL
  (`sync-server.js:12244` names this as the fix).
- **P0.8.4** Gate `POST /ocr-clear` (`:12333`) — it currently lets anyone wipe the global OCR
  job map.

## Phase 1 — iOS foundation

### P1.1 — Get it building *(needs the Mac)*

- **P1.1.1** `brew install xcodegen`, then `xcodegen generate`.
- **P1.1.2** Set `DEVELOPMENT_TEAM` in `project.yml:21`.
- **P1.1.3** Open in Xcode and fix the first round of compile errors. **Expect a real batch** —
  ~1,280 lines across 10 files have never been through a compiler. Highest-risk spots: the
  `@Bindable` locals in `ChatThreadView.thread(_:)` and `FileLibraryView.content(_:)`, and the
  `.sheet(item: $model.openSource)` binding.
- **P1.1.4** Run on the simulator.
- **P1.1.5** Run on a **physical device** — VisionKit needs a camera.
- **P1.1.6** Verify the eight features in §A.6 against production, one at a time. This is the
  first time any of them has run.
- *Done when:* the app launches on a device and a streaming answer renders.

### P1.2 — Close the two known wire bugs

- **P1.2.1** **Fix the `<truncate:N/>` offset mismatch.** The server computes `N` over
  `fullContent`, which receives content deltas only (`OpenRouterProvider.js:642,646`) and never
  `<think>` or `<usage>`. `ChatStreamParser.raw` accumulates `<think>` blocks — the file has
  zero references to `think`; reasoning is stripped later in `StreamContent`. So `applyTruncate`
  slices a buffer inflated by every reasoning block, cutting **earlier** than intended and
  deleting real answer text. Maintain a separate content-only accumulator for offset arithmetic.
  Fires only on `thinking`, which is why no test caught it.
- **P1.2.2** Add a regression test: interleave `<think>` blocks with content, then a
  `<truncate:N/>`, and assert the surviving prose.
- **P1.2.3** **Add independent truncation detection.** Balance `<canvas_content>` and
  `<table_content>` tags in `StreamContent`; an unclosed block means truncated regardless of
  what `/stream-status` says. Needed until P0.6.3 lands, and worth keeping after.
- **P1.2.4** Add the Judicial Officer guardrail. Port the `adjLine` text from
  `ToolWorkspace.jsx:2444-2447` and send it with the turn when the role is `judicialOfficer`.
  Without it, an adjudicator on iOS can be handed a drafted judgment.
- *Done when:* a `thinking` turn with a rollback renders correctly, and a token-limited answer
  is flagged.

### P1.3 — Test the HTTP layer

- **P1.3.1** Add a `URLProtocol` stub. `APIClient(config:session:)` already accepts a session,
  so this needs no redesign.
- **P1.3.2** Test that both the bearer token **and** `userId` are attached to every request.
- **P1.3.3** Test the `folderName="."` root rule (`FileService.fileData`) — sending `"_"`
  addresses a directory that does not exist.
- **P1.3.4** Test error-envelope parsing, including a route that returns 200 with an `error`
  body.
- **P1.3.5** Test `WireDate` against all three encodings with a real payload.
- **P1.3.6** Add `AuthService` tests through the stub.
- *Done when:* `APIClient` and `AuthService` are no longer zero-coverage.

### P1.4 — Environment configuration

- **P1.4.1** Add `APIConfig.development` / `.staging` / `.production`. Today
  `https://dev.emperorailabs.com/api` is hard-coded at `APIClient.swift:18`.
- **P1.4.2** Drive the base URL from a build setting, not a compile-time constant.
- **P1.4.3** **A release build must not point at the dev tunnel.** Add a test asserting it.
- **P1.4.4** App Transport Security review — no arbitrary loads.
- *Done when:* a Release archive resolves to production and a Debug build to dev.

### P1.5 — Error and offline handling

- **P1.5.1** Build one error presenter. `DisplayText.message(for:)` already centralises the
  wording; the presentation is still per-view.
- **P1.5.2** Add reachability so "offline" and "server error" read differently.
- **P1.5.3** **Make every list distinguish "loaded and empty" from "failed to load."** The
  `hasLoaded` rule in `ChatListViewModel` and `FileLibraryViewModel` is the pattern; extend it
  with a failure state. This is the guard against replicating B.10.1 — the web bug that tells a
  litigator their court day is clear.
- **P1.5.4** Retry with backoff on transient failures.
- **P1.5.5** Handle 401 explicitly — sign out and prompt. The web client has **no 401 handling
  anywhere**; do not copy that.
- *Done when:* airplane mode produces "You're offline", and a 500 produces the server's message
  — never an empty list.

### P1.6 — Persistence

- **P1.6.1** Choose a file cache over SwiftData. The product is read-mostly and the server is
  authoritative.
- **P1.6.2** Cache the chat list, cause list and case list.
- **P1.6.3** Stamp every cached view "as of <time>". Never render stale data silently.
- **P1.6.4** Clear all caches on sign-out, alongside the Keychain.
- *Done when:* the app opens offline and shows yesterday's cause list, correctly stamped.

### P1.7 — CI

- **P1.7.1** Add a workflow running `swift test` on every push. There is none today.
- **P1.7.2** Add `xcodebuild build` for the iOS target once P1.1 passes — that is the check
  that would have caught the never-compiled layer.
- *Done when:* a pushed branch reports pass/fail without a local run.

## Phase 2 — Cases and cause list

The screen that makes the app worth opening. Build on `cases`, not `projects` (§C3).

### P2.1 — Core

- **P2.1.1** `CaseService` with `cases()`, `case(id:)`, `causeList()`, behind a `CaseProviding`
  protocol.
- **P2.1.2** Models `Case`, `CaseEvent`, `CaseItem`. `case_items.section` is an open string
  with eleven known values — decode permissively.
- **P2.1.3** Discriminate `source`: `'scrape'` rows are machine-owned and are deleted and
  re-inserted on every refresh (`materialize.js:60`); `'user'` rows are not.
- **P2.1.4** Tests: decoding, section grouping, date handling, empty vs failed states.

### P2.2 — Cause list

- **P2.2.1** Day view with next/previous **listed** day jumps, not blind calendar steps.
- **P2.2.2** `/cause-list` returns the whole range in one response — cache it, paginate
  client-side.
- **P2.2.3** **Mandatory framing, copied verbatim from `TodayCauseList.jsx:16-22`: "Your cases
  only — not the court's cause list."** A litigator who reads it as the court's list and sees
  nothing has been told their day is clear when it may not be.
- **P2.2.4** Do not invent hearing times. The feed has none.
- **P2.2.5** Share sheet: export one day as text.
- **P2.2.6** A failed fetch says so. See P1.5.3 — this screen is exactly where the web bug does
  its damage.

### P2.3 — Case list and detail

- **P2.3.1** List grouped by next hearing date, searchable.
- **P2.3.2** Detail with Overview, Hearings and Orders first; the other tabs as reference.
- **P2.3.3** "From court" badge on scraped rows.
- **P2.3.4** Show `last_synced_at` honestly; null means never synced.
- **P2.3.5** Order PDFs via the per-court proxy — **sniff `Content-Type`**; all three proxies
  emit HTML error pages on failure.
- **P2.3.6** Two write actions that make sense standing up: add a note (`POST /case-event`) and
  add a task (`POST /case-item`, `section:'tasks'`).
- **P2.3.7** Surface court coverage honestly. Per §B.8, ITAT refreshes succeed roughly half the
  time and District is unwired — a case that cannot refresh should say so, not look current.

### P2.4 — Diary lookup *(optional, small)*

- **P2.4.1** One screen: forum picker, diary/filing number, year.
- **P2.4.2** `/court/sc/diary`, `/court/nclt/diary`, `/court/nclat/diary` — all captcha-free.
- **P2.4.3** Result card → "Add to my cases".

## Phase 3 — Notifications and push

Depends on P0.1 and P0.5.

- **P3.1.1** Request permission at a *considered* moment — after the first case is viewed, not
  on launch.
- **P3.1.2** Register the device token on sign-in; delete it on sign-out.
- **P3.1.3** Notification list screen from `/notifications`; badge from
  `/notifications/unread-count`.
- **P3.1.4** Mark read on open; `read-all` action.
- **P3.1.5** Deep links: `hearing`/`order`/`status` → case detail; `auction` → auction detail
  (needs P0.6.1).
- **P3.1.6** Background refresh of the unread badge.
- **P3.1.7** Handle a push arriving in the foreground — in-app banner, not a system alert.
- **P3.1.8** **Do not render `reminder` or `system` types until they have producers** (P0.7).
  Both are whitelisted and iconned in the web client but have never been emitted.

## Phase 4 — OCR and translate

The most phone-native feature in the product, and currently unbuilt on mobile.

- **P4.1.1** `OCRService`: submit, poll `/ocr-status`, download the result.
- **P4.1.2** **Send a `userId`** — the route currently records cost against NULL.
- **P4.1.3** Camera or Files → PDF → submit → job id.
- **P4.1.4** Poll `/ocr-status`. Treat `/ocr-logs` SSE as optional colour — no heartbeat, no
  `Last-Event-ID`, drops on idle intermediaries.
- **P4.1.5** Language picker (24 languages).
- **P4.1.6** Result `.docx` → share sheet / Files.
- **P4.1.7** Job survives backgrounding; notify on completion.
- **P4.1.8** `/re-ocr` action on a library file that came back garbled.
- **P4.1.9** Accept image formats. The web upload dialog does not
  (`UploadModal.jsx:369`) — on an OCR product that is a bug, not a spec.

## Phase 5 — Calendar

- **P5.1.1** Month and agenda views from `/compliance` + `cases.next_hearing_date`.
- **P5.1.2** Create and edit a compliance event.
- **P5.1.3** **Ship the `remind_days` picker only after P0.7.** Until then it is a lie the UI
  tells.
- **P5.1.4** EventKit write-through so hearings appear in the system calendar.
- **P5.1.5** **Do not ship the ICS subscription URL in-app until it has a rotatable token** —
  `/calendar/my.ics?userId=` is a permanent, unrevocable bearer credential for a user's entire
  calendar.
- **P5.1.6** Do not attempt the Corporate Calendar. Company profiles exist only in browser
  `localStorage` (§B.9); an iOS client would render it empty.

## Phase 6 — Polish

- **P6.1.1** Markdown table rendering for `.markdown` artifacts —
  `AttributedString(markdown:)` does **not** support tables.
- **P6.1.2** Dynamic Type throughout; the target user skews older.
- **P6.1.3** VoiceOver labels, especially on the citation strip and reasoning panel.
- **P6.1.4** Dark mode audit.
- **P6.1.5** iPad layout — `TARGETED_DEVICE_FAMILY` is already `1,2`; split view for cases.
- **P6.1.6** Haptics on send and completion.
- **P6.1.7** Background upload via `URLSessionConfiguration.background` so a large paperbook
  survives backgrounding.
- **P6.1.8** Empty states for every list — distinct from failure states (P1.5.3).
- **P6.1.9** Sign-out clears Keychain **and** all caches.

## Phase 7 — Release

- **P7.1.1** App icon and launch screen. *(Icon exists.)*
- **P7.1.2** **Registration UI or a documented demo account.** `Register.jsx` is dead in the web
  product — there is no self-signup path. Guideline 4.2 needs one or an explanation.
- **P7.1.3** **Remove any Upgrade or pricing surface.** There is no IAP obligation today because
  the app takes no money; that stays true only if no in-app path to pricing exists. The moment
  Razorpay lands, plans must move to StoreKit.
- **P7.1.4** Remove any "Preview build" banner.
- **P7.1.5** Legal-advice disclaimer on first run and in Settings.
- **P7.1.6** `PrivacyInfo.xcprivacy` — required. Declare data collection honestly.
- **P7.1.7** App Store privacy nutrition labels.
- **P7.1.8** Crash reporting.
- **P7.1.9** TestFlight with two or three real advocates.
- **P7.1.10** Review notes explaining the closed-account model, with credentials.
- **P7.1.11** **Do not submit until P0.2 and P0.3 are live.** Guideline 5.1.2 — shipping a
  client that reads user data from an endpoint any anonymous caller can also read is the one
  risk that will not survive review.

---

# PART F — Sequencing, risks, open questions

## F.1 Critical path

```
P0.1 workers ─┐
P0.2 admin ───┼─ days       ← do these first, they are small
P0.6 amplify ─┘

P0.3 auth ────────────────  ← the long pole; blocks submission
P0.5 push ────────────────  ← the other long pole; blocks Phase 3
P0.7 reminders ───────────  ← blocks Phase 5

P1 foundation ────────────  ← blocks everything iOS
P2 cases + cause list ────  ← highest user value; parallel with P0.3
P3 notifications ─────────  (needs P0.1, P0.5)
P4 OCR ───────────────────
P5 calendar ──────────────  (needs P0.7)
P6 polish ────────────────
P7 release ───────────────  (needs P0.2, P0.3)
```

Phase 2 can be built entirely in parallel with P0.3 — it is read-only against routes that
already work.

## F.2 Fastest route to something in a lawyer's hands

1. **P0.1 + P0.2** — a day. Restarts the data flow and closes the admin bypass.
2. **P1.1** — get it building on the Mac. Chat and documents already work.
3. **P1.2** — close the two wire bugs before anyone relies on the answers.
4. **Phase 2** — cause list and cases.
5. **P0.3** — auth, in parallel with Phase 2.
6. **P0.5 + P0.7 + Phase 3** — push and reminders. This is what makes it worth *keeping*.

A useful internal build exists after step 4. A defensible submission needs step 5.

## F.3 Risks

| Risk | Mitigation |
|---|---|
| **The SwiftUI layer has never compiled.** P1.1.3 could be a day or a week. | Do it first. It is the largest unknown in the plan and everything downstream depends on it. |
| **P0.3 touches 81 handlers.** A missed site is a silent data leak. | Deny-by-default at the gate (P0.3.1) means a missed site fails closed, not open. Do the gate before the per-handler work. |
| **iOS has never talked to the live server.** | P1.1.6 verifies the eight existing features one at a time before new ones are built on top. |
| Court coverage is narrower than it looks. | P2.3.7 — surface refresh failures honestly rather than showing stale data as current. |
| Backend docs are unreliable. `ARCHITECTURE.md` is stale by 3.5× on file size alone. | Read source. `AGENTS.md` is the only doc with a dated verification warranty. |

## F.4 Open questions — these need your answer, not mine

1. **Is the generic eCourts aggregator live?** The codebase contradicts itself:
   `court-scraper/refresh.js:44-47` says it went dark 2026-07-17 and treats it as dead;
   `hc-registry.js:6-8` says it "came back by 2026-07-24". Nothing resolves it. This is the
   difference between ~7 High Courts and ~32 for v1 case coverage.
2. **Should the District adapter be wired?** `adapters/district.js` is 43 KB and complete but
   referenced nowhere, and `refresh.js:199` excludes `court_type='district'` from refresh
   entirely.
3. **Is `projects` being trialled towards launch, or abandoned?** It is complete and
   deliberately hidden. If it is the future matter model, Phase 2 should be reconsidered — but
   nothing in the source suggests that (§C3).
4. **Razorpay timing.** The moment payment lands, any in-app path to it triggers StoreKit
   obligations. Decide the iOS billing story before, not after.
5. **Is the reference library volume coming back?** The "2,24,361 items" is a headline claim on
   the marketing site; `/mnt/EmpData` is not mounted and the library renders empty.
6. **Multi-user teams.** Every user gets an auto-created solo team called "My Firm"
   (`sync-server.js:4007-4011`), so a `teams` row count is not a signal of adoption. Only two
   roles exist and no authorization branch reads the `role` column. Is collaboration a real
   roadmap item, or should iOS treat `teamId` as invisible plumbing?
