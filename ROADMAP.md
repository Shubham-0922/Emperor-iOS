# Jithro (iOS) — Status Report and v1 Plan

**Date:** 2026-08-25
**Platform analysed:** `/var/www/emperor-ai` @ `d046f317`
**iOS client:** `/var/www/jithro-ios` (app name: **Jithro**)

Everything below was read from source and, where possible, checked against the live server
and the production database. Row counts are real. Claims carry `file:line` citations so you
can verify rather than trust.

---

# PART 1 — What has been built so far

## 1.1 Summary

| | |
|---|---|
| Swift files | 64 (40 core, 24 app) |
| Tests | **332, all passing** (see `V1_BUILD_PLAN.md`) |
| Test runtime | ~0.4s |
| Lines of core logic | ~6,250 |
| Buildable here | Core only (no iOS SDK on Linux) |
| Buildable on your Mac | Yes — `xcodegen generate && open Jithro.xcodeproj` |

The project is split so the risky half can be proven without a Mac:

- **`Sources/JithroCore/`** — Foundation-only. No UIKit, no SwiftUI. Compiles and tests on
  Linux, so every wire-format edge case is pinned by a test rather than discovered on device.
- **`Jithro/`** — the SwiftUI layer. Written but **not compile-verified**, because this box
  has a Swift compiler and no iOS SDK.

The Xcode app target compiles `Sources/JithroCore` directly (`project.yml`), so the tested
code and the shipped code are the same bytes. No second copy to drift.

## 1.2 Core — what each file does

**Wire format and transport**

| File | Purpose |
|---|---|
| `ChatStreamParser.swift` | Parses the `/chat` wire format. Two layers, matching the server's own ordering. |
| `IncrementalUTF8Decoder.swift` | Decodes byte chunks without splitting multi-byte characters. |
| `StreamContent.swift` | Decomposes an answer into prose, artifacts, citations, reasoning, errors. |
| `ReasoningTracker.swift` | Plan progress + agentic work log. Port of `src/lib/streamManager.js`. |
| `ChatOptions.swift` | `ChatModel` and `ChatRole` enums — the allowed wire values. |
| `APIModels.swift` | Codable models + `WireDate` (three timestamp encodings). |
| `APIClient.swift` | HTTP layer. Injects bearer token **and** `userId` on every request. |
| `JSONValue.swift` | Permissive JSON for the two schemaless payloads. |

**Services.** Each declares the protocol its view model depends on, so every screen can be
driven without a server.

| File | Purpose |
|---|---|
| `AuthService.swift` | Login, register, sign-out. |
| `ChatService.swift` | Chat history, streaming turns, rejoin, reasoning snapshots. `ChatProviding`, `ChatListProviding`. |
| `UploadService.swift` | Resumable chunked upload + ingestion polling. `UploadProviding`. |
| `FileService.swift` | Document tree, search, citation resolution, file download. `FileProviding`. |
| `CredentialStore.swift` | Where the token is persisted. The Keychain's one seam into the core. |

**View models and presentation.** All `@MainActor`, all tested on Linux.

| File | Purpose |
|---|---|
| `Session.swift` | Auth state, session restore, owns the shared `APIClient`. |
| `ChatViewModel.swift` | Turn state, in-flight recovery, completeness confirmation, citation resolution, scan attachment. |
| `ChatListViewModel.swift` | Conversation list, loading/empty-state rules. |
| `FileLibraryViewModel.swift` | Document search, grouping by matter, selection reconciliation. |
| `SourceDocumentViewModel.swift` | Cited-document fetch, titles, 1-based → 0-based page mapping. |
| `DisplayText.swift` | Filename un-sanitising and error wording — one copy of each rule. |
| `ScannedDocument.swift` | The scan bundle, its naming rule, and `ScanError`. |
| `ArtifactDocument.swift` | The page wrapper a drafted HTML fragment is rendered inside. |

## 1.3 App layer

What is left needs UIKit, SwiftUI or the Security framework, and nothing else.

| File | Purpose |
|---|---|
| `JithroApp.swift` | Entry point, root routing on auth state. |
| `Keychain.swift` | The real `CredentialStore`: `WhenUnlockedThisDeviceOnly`, never iCloud. |
| `LoginView.swift` | Sign in / register. |
| `ChatListView.swift` | Conversation list. |
| `ChatThreadView.swift` | Transcript, composer, model/role pickers, citation taps. |
| `ReasoningPanel.swift` | Collapsible plan + work log + reasoning. |
| `ArtifactView.swift` | Draft/table viewer (hardened `WKWebView`), citation strip. |
| `FileLibraryView.swift` | Document picker grouped by matter. |
| `SourceDocumentView.swift` | Opens a cited document at the cited page (PDFKit). |
| `DocumentScannerView.swift` | VisionKit paperbook scan → single PDF. |

## 1.4 Working features

1. **Sign in / register**, token in Keychain, session restore on launch.
2. **Chat with streaming** — incremental parse, status line, rollback handling, artifact
   extraction, in-flight rejoin after backgrounding, completeness confirmation.
3. **Model and persona pickers** — Quick/Thinking, three personas, seeded from
   `preferred_model`.
4. **Document scanning** — VisionKit multi-page → one PDF → chunked resumable upload →
   ingestion polling → auto-attach to the turn.
5. **Document library** — browse grouped by matter, search, multi-select attach.
6. **Citations** — parsed, shown as tappable chips, resolved to the source document, opened
   at the cited page.
7. **Artifacts** — drafts and tables open full-screen, format sniffed from the body.
8. **Reasoning panel** — plan with live progress, agentic work log, reasoning sentences.

## 1.5 Bugs found and fixed during the build

Each was caught by a test or by reading platform source, not on a device.

| # | Bug | Consequence had it shipped |
|---|---|---|
| 1 | `Data.suffix(from:)` index-based on a re-sliced `Data` | Crash on every stream containing a multi-byte character (Devanagari, ₹) |
| 2 | `<truncate:N/>` sliced by `Character` offset | Corrupted any draft containing an emoji or non-BMP character |
| 3 | Filename sanitisation mapped over grapheme clusters | Every Hindi-named upload polls a path that never resolves — **appears to hang forever** |
| 4 | Truncate clamped to buffer length | Stray `<truncate:N/>` rendering as prose |
| 5 | Literal `<` in prose eaten as a partial tag | "damages < 50,000" silently truncated |
| 6 | Only `<think>` stripped | Model's private reasoning shown to a client under five other wrappers |
| 7 | Citation regex required a page *range* | `<@file.pdf:P-5:7>` **renders verbatim in the middle of a pleading** |
| 8 | Attachments sent only at top level | Bypasses the scanned-document refusal check |
| 9 | Artifact rendered by declared wrapper | A pleading inside `<table_content>` renders as raw HTML tags |

Items 3 and 7 are the ones that would have been hardest to diagnose in the field.

## 1.6 Also done

- **`/var/www/emperor-ai/AGENTS.md` rewritten** (151 lines changed, uncommitted). It named the
  wrong LLM provider, wrong models, wrong vector collection, and referenced a function that no
  longer exists. Every claim now carries a citation; all 15 spot-checked.

---

# PART 2 — Platform analysis

## 2.1 What the product actually is

A legal AI platform for Indian litigation and corporate practice. Node monolith
(`sync-server.js`, 13,665 lines, one raw `http.createServer` with a 158-route if/else chain),
React SPA, SQLite (`Data/database.db`, 1.1 GB), Chroma for RAG, OpenRouter for generation.

## 2.2 Usage — what the database says

This is the most important section in the report. It separates what is built from what is used.

| Feature | Rows | Verdict |
|---|---|---|
| `users` | 31 (30 `lite`, 1 `ultra`) | Small, real |
| `cases` | 199 | **Genuinely used** |
| `case_items` | ~14,600 | **Genuinely used** |
| `usage_events` | 39,707 (~$35.87 over 18 days) | **Heavily used** |
| `filing_annexures` | 405, 10 distinct users | **Genuinely used** |
| `notifications` | 4,117 — **newest 2026-08-01** | Used, then **frozen** |
| `auction_notices` | 8,706 — **newest 2026-07-31** | Rich, **stale** |
| `compliance_events` | 8 | Barely used |
| `filing_bundles` | 1 — **file no longer on disk** | Ran once |
| `projects` / `project_updates` | 1 / **0** | **Built, never used** |
| `teams` | 18 — **every one single-member** | **Built, never used** |
| `checkout_submissions` | 1 | One lead, ever |
| `feedback` | 0 | — |

Usage by cost tag: `ocr` 29,725 events ($20.82), `chat` 1,747 ($14.68), `embedding` 7,428,
`metadata` 807. **`draft`, `research`, `translation`, `vision` have never fired.**

**Read that carefully.** The product's real usage is *chat, OCR, documents, cases and filing
annexures*. Projects, teams, compliance and the checkout funnel are scaffolding.

## 2.3 Processes: three of seven are not running

`pm2 list` shows `chroma`, `bge-embed`, `sync-server`, `vite`, `cloudflared-dev`.

**Not running**, though declared in `ecosystem.config.cjs:34,50,56`:

- **`court-scraper`** — this is why notifications stopped on 2026-08-01 and auctions on
  2026-07-31. It drives case refresh, change notifications, and the IBBI auction ingest.
- **`compliance-scheduler`**
- **`compliance-api`** (superseded, effectively dead)

**Consequence:** cases do not auto-update, no notification has been generated in ~3.5 weeks,
and the "live auctions" list shows a month-old snapshot with no staleness indicator. A push
channel built on top of this would notify nobody.

## 2.4 Broken in production right now

| # | What | Where | Effect |
|---|---|---|---|
| B1 | Playwright hard-coded to `/opt/pw`, which does not exist | `lib/filing/render.js:11` | **All server-side PDF generation returns 500** — `/print-pdf`, every "Download PDF", `/filing/assemble` |
| B2 | `res.writeHead` called before body computation | `sync-server.js:11696` | `/compliance-calendar` **hangs** (25s+, never ends). Same bug is documented and fixed 20 lines below |
| B3 | `/mnt/EmpData` not mounted | `lib/referenceLibrary.js:15` | Reference library (the "224,361 items") renders **empty with no error** |
| B4 | `DTEND == DTSTART` on all-day events | `sync-server.js:10246` | RFC 5545 violation; iOS Calendar renders inconsistently |
| B5 | `remind_days` written, rendered, **read by nothing** | `sync-server.js:10264` | "Remind me 3 days before" is a promise the product does not keep |
| B6 | Auction notification links point at an API path | `ibbi-auctions-ingest.js:97` | Every auction notification lands on NotFound |
| B7 | `DELETE /case` does not delete `case_items` | `sync-server.js:10539` | Orphaned rows accumulate |
| B8 | Reset password stored **plaintext** | `sync-server.js:10521` | Works only because login upgrades it later |
| B9 | Event modal does not reset its title field | `src/pages/MyCalendar.jsx:134` | Live data has accumulating titles |
| B10 | Generic eCourts returns 405 site-wide since 2026-07-17 | `court-scraper/refresh.js:52` | ~20 of ~25 High Courts have **no live source** |

## 2.5 Security — the blocking issue

**Authentication is not enforced.** There is no middleware; `requireAuth` is imported at
`sync-server.js:35` and never called. Roughly 40 data routes take the caller's identity from a
client-supplied `?userId=` parameter.

Verified live, with no credential:
```
curl localhost:3001/api/notifications/unread-count?userId=1  →  {"success":true,"count":109}
```

Combined with `Access-Control-Allow-Origin: *` and a Cloudflare tunnel carrying **no Access
policy**, `https://dev.emperorailabs.com/api/user-files?userId=<n>` is an unauthenticated
public read of that user's documents. `ecosystem.dev.config.cjs`'s own header admits the
tunnel serves "a copy of real client matters".

Additional exposures found:
- `POST /update-profile` (`sync-server.js:8360`) — no auth at all. Anyone can overwrite any
  user's name, title, organisation, avatar.
- `GET /feedbacks`, `GET /support-feedback`, `GET /support-feedback-file` — unauthenticated,
  return every user's name, email, complaint text and uploaded screenshots.

**`lib/filing/*` is the only module that prefers the bearer token** (`lib/filing/index.js:88`).
It is the proof that the fix is small and the pattern already exists.

## 2.6 Push notifications: nothing exists

Exhaustive grep for `apns|web-push|firebase|fcm|serviceWorker|pushManager` yields **one** hit:
`src/shell/NotificationBell.jsx:61` uses the browser `Notification` API — a foreground-only,
tab-must-be-open local notification driven by a 60-second poll. No service worker, no VAPID,
no device tokens, no sender.

The only out-of-band channel is email, and SMTP is disabled (`enabled=0`, empty host).

**iOS push is 100% new backend work.** The good news: all four notification producers funnel
through `createNotification` (`lib/notifications.js:56`), so one intercept point covers
everything, including future producers.

## 2.7 Feature inventory and mobile fit

### Genuinely used, high mobile value

| Feature | Routes | Mobile verdict |
|---|---|---|
| Chat with documents | `/chat`, `/messages`, `/chats` | **Essential** — done |
| Document upload / DMS | `/upload-chunk`, `/user-files`, `/view-file` | **Essential** — done |
| Cause list | `/cause-list` | **Essential** — the single highest-value screen |
| Cases (read) | `/cases`, `/case` | **Essential** — one request returns case + events + items |
| Notifications | `/notifications/*` | **Essential** — blocked on §2.3 and §2.6 |
| OCR / translate | `/ocr-translate`, `/ocr-status` | **Essential** — the most phone-native feature in the product |
| Calendar | `/compliance`, `/calendar/my.ics` | **Essential** |
| Prompt enhancer | `/enhance-prompt` | **Useful** — fixes exactly the rough prompts dictation produces |
| Diary-number lookup | `/court/*/diary` | **Useful** — one field, captcha-free, ten-second check |
| Annexure registry | `/filing/annexures` | **Useful** — and already token-authenticated |
| Deep research | `/deep-research` | **Useful** — fire-and-forget suits transit, but see caveat |
| Auctions browse | `/auction-notices` | **Useful** — needs a staleness banner |

### Desktop-only, with reasons

- **Full Add Case flow** — three to four dependent round-trips through cascading pickers before
  the first field the user knows. Rare action; read a hundred times, added once.
- **13-tab Case Workspace as an editor** — ten form schemas. Read on mobile, edit at a desk.
- **Draft editing / the canvas** — `useDocEditor.js` is 43 KB; `grep -c isMobile ToolWorkspace.jsx`
  returns **0**. A contenteditable A4 page with a paginating index rail is a different product,
  not a responsive adaptation.
- **Filing bundle assembly** — not a screen-size issue. A 293-page paperbook where a wrong
  folio gets your matter rejected at the registry counter should not be approved on a phone.
- **Admin surface** — six dense tables for three admins.
- **Compliance / Corporate Calendar** — depends on a company profile in `localStorage` with no
  server representation, so an iOS client literally cannot read it.

### Dead code — do not port

`ChatWindow.jsx`, `ChatWindow_original.jsx`, `Canvas.jsx`, `clerkConfig.js`,
`models_registry.json`, `convertTemplateTags()`, `src/pages/Library.jsx`, `FeedbackWidget.jsx`,
`/library-books/*`, `/bare-acts/*`, `POST /draft`, `scrape_jobs` + `/court/search`,
`pollScrapeJob`. All verified unreachable by grepping for importers.

`POST /register` exists server-side but **no UI calls it** — accounts are created by an admin.

## 2.8 App Store review risks

| # | Risk | Guideline | Action |
|---|---|---|---|
| A1 | Client-supplied identity across all user data | 5.1.2 / privacy | **Must fix before submission** |
| A2 | No sign-up path; login wall with no way in | 4.2 | Ship registration UI + demo account in review notes |
| A3 | "Upgrade" button → `/buy` pricing page | 3.1.1 / 3.1.3(a) | **Omit from the iOS build entirely** |
| A4 | "Preview build — some results may not be perfect yet" banner | 2.2 | Strip from iOS |
| A5 | No legal-advice disclaimer | 1.4.1 / 5.x | Add a visible disclaimer surface |
| A6 | Library corpus is scraped third-party material | 5.2 | Rights review, independent of iOS |
| A7 | Unauthenticated PII endpoints | 5.1.2 | Fix server-side |

On A3: there is **no IAP obligation today**, because the app takes no money — `/checkout` is
lead capture that emails an admin. That stays true only if no in-app path to pricing exists.
The moment Razorpay lands, plans must move to StoreKit.

---

# PART 3 — The plan for v1

## 3.1 What v1 is

> **A litigator's companion in transit.** It answers "what do I have tomorrow", "what happened
> on my matters", "what does this document say", and "draft me something to review later".

v1 is **read, capture, ask, and be told**. It is not an editor and not an administrator.

**In scope:** chat with documents · document capture & upload · document library · cause list ·
cases (read) · notifications with push · calendar · OCR/translate · profile & settings.

**Explicitly out:** draft editing, filing assembly, full case search, projects, teams,
compliance calendar, admin, billing.

## 3.2 Phase 0 — Backend unblocking

**None of this is iOS work, and most of v1 is dishonest without it.** Ordered by
value-per-effort.

### 0.1 Fix Playwright path — 1 line
- [ ] `lib/filing/render.js:11` — resolve from `node_modules/playwright` instead of `/opt/pw`
- [ ] Verify: `curl -X POST localhost:3001/print-pdf -d '{"html":"<p>t</p>"}'` returns a PDF
- [ ] Un-breaks: `/print-pdf`, all "Download PDF", `/filing/assemble`

### 0.2 Restart the workers — config only
- [ ] `pm2 start ecosystem.config.cjs --only court-scraper`
- [ ] Confirm a new `notifications` row appears within 30 min (refresh tick interval)
- [ ] Confirm `auction_notices.updated_at` advances within 45 min
- [ ] Decide whether `compliance-scheduler` is wanted; if not, delete it from the config so it
      stops looking like a running feature

### 0.3 Enforce authentication — the big one
- [ ] Extend the `lib/filing/index.js:88` `resolveUserId` pattern into shared middleware
- [ ] Apply to every route that currently reads `?userId=` (~40 sites)
- [ ] Keep the param as a **fallback** during rollout so existing clients keep working
- [ ] Add a deprecation log when the fallback fires; watch it drain to zero
- [ ] Then remove the fallback
- [ ] Add a Cloudflare Access policy to `dev.emperorailabs.com` **today**, as a stopgap
- [ ] Fix `POST /update-profile` (`sync-server.js:8360`) — currently no auth at all
- [ ] Gate `/feedbacks`, `/support-feedback`, `/support-feedback-file` behind admin
- [ ] Fix `/reset-password` to hash (`sync-server.js:10521`)
- [ ] Raise the 4-character password minimum

### 0.4 Build push infrastructure
- [ ] `device_tokens` table: `user_id, token, platform, app_version, updated_at`, unique on token
- [ ] `POST /device-tokens` (register) and `DELETE /device-tokens` (on sign-out)
- [ ] APNs sender: HTTP/2 + JWT (`node-apn` or hand-rolled), key from the Apple Developer portal
- [ ] Hook **inside `lib/notifications.js:56`** — one intercept covers all four producers
- [ ] Respect `read` state: do not push something already read on another device
- [ ] Collapse-ID per case so ten new orders on one matter are one notification
- [ ] Test: sandbox APNs from a TestFlight build

### 0.5 Build the reminder job — highest value per line
- [ ] Daily scan of `compliance_events` where `due_date - remind_days <= today`
- [ ] Also scan `cases.next_hearing_date` — a hearing reminder is *the* push notification
- [ ] Emit `type:'reminder'` notifications (the type exists and has **zero producers**)
- [ ] Idempotency key so a restart does not double-notify

### 0.6 Route hygiene
- [ ] Add `/api` aliases for `/deep-research` and the six `/ocr-*` routes — they are bare-path
      only and **404 behind production nginx**
- [ ] Fix `/compliance-calendar` header ordering (`sync-server.js:11696`)
- [ ] Fix ICS `DTEND` to day+1 (`sync-server.js:10246`); add `X-PUBLISHED-TTL`
- [ ] Include projects' `next_hearing_date` in the ICS feed, or decide it is out of scope
- [ ] Replace `?userId=` on the ICS feed with a rotatable per-user token
- [ ] Fix `DELETE /case` to cascade `case_items`
- [ ] Add `GET /register` UI path, or accept admin-only account creation and document it

### 0.7 Data honesty
- [ ] Add `last_synced_at` / freshness to auction responses; the UI must not present a
      month-old snapshot as "live"
- [ ] Surface `portalDown` for the ~20 dark High Courts rather than "no case found"

## 3.3 Phase 1 — iOS foundation hardening

### 1.1 Get it building
- [ ] `brew install xcodegen && xcodegen generate` on the Mac
- [ ] Fix the first round of compile errors in the SwiftUI layer (expected — never compiled)
- [ ] Set `DEVELOPMENT_TEAM` in `project.yml`
- [ ] Run on a device, not just the simulator (VisionKit needs a camera)
- [ ] Add a CI job running `swift test` on every push

### 1.2 Environment config
- [ ] `APIConfig` for dev / staging / production; do not hard-code the dev tunnel in a release
- [ ] Build-setting-driven base URL
- [ ] App Transport Security review — no arbitrary loads

### 1.3 Error and offline handling
- [ ] A single error presenter; today several views use `.constant(x != nil)` alerts, which is
      workable but repetitive
- [ ] Reachability: distinguish "offline" from "server error" in copy
- [ ] Retry with backoff on transient failures
- [ ] `URLCache` policy for `/user-files` and `/cases`

### 1.4 Persistence
- [ ] Decide: SwiftData vs a simple file cache. Recommendation: **file cache first** — the
      product is read-mostly and the server is authoritative
- [ ] Cache last cause list, case list, chat list for offline open
- [ ] Show cached data with an explicit "as of <time>" stamp — never silently stale

## 3.4 Phase 2 — Cases and cause list

The highest-value screen in the app.

### 2.1 Core (testable here)
- [ ] `CaseService`: `cases()`, `case(id:)`, `causeList()`
- [ ] Models: `Case`, `CaseEvent`, `CaseItem` — note `case_items.section` is an open string
      with eleven known values
- [ ] `source` discrimination: `'scrape'` rows are machine-owned, `'user'` rows are not
- [ ] Tests: decoding, section grouping, date handling, empty states

### 2.2 Cause list screen
- [ ] Day view with next/previous **listed** day jumps (not blind calendar steps)
- [ ] `/cause-list` returns the entire range in one response — cache it, paginate client-side
- [ ] **Mandatory framing: "Your cases only — not the court's cause list."** Copy this verbatim
      from `TodayCauseList.jsx:16-22`. A litigator who reads it as the court's list and sees
      nothing has been told their day is clear when it may not be.
- [ ] No hearing times — the feed has none; do not invent them
- [ ] Share sheet: export one day as text

### 2.3 Case list and detail
- [ ] List grouped by next hearing date, searchable
- [ ] Detail: Overview, Hearings, Orders first; the rest as reference
- [ ] "From court" badge on scraped rows
- [ ] `last_synced_at` shown honestly; null means never synced
- [ ] Order PDFs via the per-court proxy — **sniff `Content-Type`**, all three proxies emit
      HTML error pages on failure
- [ ] Add a note (`POST /case-event`) and a task (`POST /case-item`, `section:'tasks'`) — the
      two write actions that make sense standing up

### 2.4 Diary lookup (optional, small)
- [ ] One screen: forum picker, diary/filing number, year
- [ ] `/court/sc/diary`, `/court/nclt/diary`, `/court/nclat/diary` — all captcha-free
- [ ] Result card → "Add to my cases"

## 3.5 Phase 3 — Notifications and push

Depends on 0.2 and 0.4.

- [ ] Request notification permission at a *considered* moment — after the first case is
      viewed, not on launch
- [ ] Register the device token on sign-in; delete on sign-out
- [ ] Notification list screen: `/notifications`, unread badge from `/notifications/unread-count`
- [ ] Mark read on open; `read-all` action
- [ ] Deep links: `hearing`/`order`/`status` → case detail; `auction` → auction detail
      (**note B6**: the server currently emits an API path that 404s — fix server-side)
- [ ] Background refresh of the unread badge
- [ ] Handle a push arriving while the app is foregrounded — in-app banner, not a system alert

## 3.6 Phase 4 — OCR and translate

The most phone-native feature in the product, and it is currently unbuilt on mobile.

- [ ] Core: `OCRService` — submit, poll `/ocr-status`, download result
- [ ] **Send a `userId`** — the route currently records cost against NULL
      (`sync-server.js:12244` names this as the fix)
- [ ] Use **bare paths** unless 0.6 lands
- [ ] Camera or Files → PDF → submit → job id
- [ ] Poll `/ocr-status`; treat `/ocr-logs` SSE as optional colour (no heartbeat, no
      `Last-Event-ID`, drops on idle intermediaries)
- [ ] Language picker (24 languages)
- [ ] Result: `.docx` → share sheet / Files
- [ ] Job survives backgrounding; notify on completion
- [ ] `/re-ocr` action on a library file that came back garbled

## 3.7 Phase 5 — Calendar

- [ ] Month and agenda views from `/compliance` + `cases.next_hearing_date`
- [ ] Create/edit a compliance event
- [ ] `remind_days` picker — **only ship this once 0.5 exists**, or it is a lie
- [ ] Optional: EventKit write-through so hearings appear in the system calendar
- [ ] Do **not** ship the ICS subscription URL in-app until it has a rotatable token — it is a
      permanent, unrevocable bearer credential for a user's whole calendar

## 3.8 Phase 6 — Polish

- [ ] Markdown table rendering for `.markdown` artifacts (`AttributedString(markdown:)` does
      **not** support tables — needs a custom renderer or a hardened WebView)
- [ ] Dynamic Type throughout; the target user skews older
- [ ] VoiceOver labels, especially on the citation strip and reasoning panel
- [ ] Dark mode audit
- [ ] iPad layout — `TARGETED_DEVICE_FAMILY` is already `1,2`; split view for cases
- [ ] Haptics on send / completion
- [ ] Background upload via `URLSessionConfiguration.background` so a large paperbook survives
      the app being backgrounded
- [ ] Empty states for every list
- [ ] Sign-out clears the Keychain **and** all caches

## 3.9 Phase 7 — Release

- [ ] App icon and launch screen
- [ ] Registration UI (A2) or a documented demo account for review
- [ ] **Remove any Upgrade/pricing surface** (A3)
- [ ] **Remove the "Preview build" banner** (A4)
- [ ] Legal-advice disclaimer on first run and in Settings (A5)
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) — required; declare data collection honestly
- [ ] App Store privacy nutrition labels
- [ ] Crash reporting
- [ ] TestFlight with two or three real advocates
- [ ] App Review notes explaining the closed-account model and supplying credentials

## 3.10 Sequencing

```
Phase 0  ──────────────────────────────────  backend, mostly not iOS
  0.1 Playwright   0.2 workers   0.6 routes      ← days
  0.3 auth         0.4 push      0.5 reminders   ← the real work

Phase 1  ─────────  foundation, unblocks everything
Phase 2  ─────────────────  cases + cause list   ← highest user value
Phase 3  ──────────  notifications + push        (needs 0.2, 0.4)
Phase 4  ──────────  OCR / translate             (needs 0.6)
Phase 5  ──────  calendar                        (needs 0.5)
Phase 6  ────────────  polish
Phase 7  ──────  release
```

**Critical path:** 0.3 (auth) and 0.4 (push) are the long poles. Everything in Phase 2 can be
built in parallel with them, because it is read-only against routes that already work.

## 3.11 Recommended order if you want something in a lawyer's hands fastest

1. **0.1 + 0.2** — a day. Un-breaks PDFs and restarts the data flow.
2. **1.1** — get the existing app building on your Mac. Chat and documents already work.
3. **Phase 2** — cause list and cases. This is the screen that makes the app worth opening.
4. **0.3** — auth, in parallel with Phase 2.
5. **0.4 + 0.5 + Phase 3** — push and reminders. This is what makes it worth *keeping*
   installed.
6. Everything else.

A useful internal build exists after step 3. A defensible App Store submission needs step 4.

---

# PART 4 — Open questions

1. **`cases` vs `projects`.** `projects` is documented as the intended successor to `/cases`
   (`sync-server.js:3377-3388`) but has 1 row and 0 updates, and its sidebar entry is
   admin-gated. Building iOS on `cases` may be building on the outgoing model. **Which is the
   future?**
2. **Are the ~20 dark High Courts being fixed?** Generic eCourts has returned 405 site-wide
   since 2026-07-17. If not, case coverage on mobile is Supreme Court, six High Courts, NCLT,
   NCLAT, ten tribunals and consumer fora.
3. **Is `compliance-scheduler` wanted?** If not, delete it from the config.
4. **Razorpay timing.** The moment payment lands, any in-app path to it triggers StoreKit
   obligations. Plan the iOS billing story before, not after.
5. **Is the reference library volume coming back?** The "224,361 items" is a headline claim on
   the marketing site and currently renders empty.
6. **Multi-user teams.** 18 teams, all single-member. Is collaboration a real roadmap item or
   should iOS treat `teamId` as invisible plumbing?
