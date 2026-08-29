# Jithro iOS — what is missing

**Updated after closing Tier 1 item 6 and most of Tier 2.** Struck-through items are done; the
rest stand. 618 tests.

Measured 2026-08-26 against the live web product, not recalled. Every "not built" below was
checked by grepping for the route or the view; every "deliberate" carries the reason.

**Short answer: no, it does not have all the platform's functions — and most of what remains
missing is on purpose.** Seven Tier 1 gaps were not on purpose; six are now closed. Of the nine
Tier 2 features, six are now built, one was rejected on the merits, and two remain.

---

## Tier 1 — real gaps. Not deliberate, not blocked on a Mac.

### 1. ~~A document can only get in through the camera~~ — CLOSED

`ChatViewModel.attach` is the **only** path to `POST /upload-chunk`. There is no "upload a file"
anywhere. An advocate with a PDF in Files, iCloud Drive or an email attachment cannot put it in
their document library at all.

The OCR screen has a file picker, but that posts to `/ocr-translate` — a different subsystem
that never writes to the DMS. So the file it reads is not the file you can then ask about.

*Fix:* a `.fileImporter` in `FileLibraryView` feeding the existing `UploadService`. Small — the
upload path already works and is tested.

### 2. ~~An expired session is a dead end~~ — CLOSED

`LoadState.requiresReauthentication` is computed and **read by nothing**. When the 30-day token
expires, every screen shows "Session expired" with no retry (correctly — retrying is pointless)
and no way to sign in again. The only escape is deleting the app.

*Fix:* `Session.signOut()` when any view model reports it.

### 3. ~~Maintenance mode renders as a generic failure~~ — CLOSED

The server answers 503 with `{maintenance: true, message, since}` and `Retry-After: 600`
(`sync-server.js:6244-6262`), and the web client pre-empts every route to show the operator's
message. iOS shows "Could not load" instead — so during a planned outage every user sees what
looks like a bug.

*Fix:* recognise the 503 body in `APIClient`, add a `.maintenance` `LoadFailure.Kind`.

### 4. ~~No password reset~~ — CLOSED (self-signup remains absent by design)

`/forgot-password` and `/reset-password` exist server-side. iOS offers neither. Accounts are
admin-created (the web's `Register.jsx` is dead code), so a user who forgets their password has
no path forward inside the app at all.

*Fix:* a "Forgot password" link on `LoginView` hitting the two existing routes.

### 5. ~~OCR is buried three levels deep~~ — CLOSED

The most phone-native feature in the product — photograph a paper order, get a searchable
document — is reachable only via: chat → composer "+" → Attach from documents → toolbar button.
It is behind a modal inside a modal.

*Fix:* promote it. Either its own tab or an action on the Today screen.

### 6. ~~No retry with backoff~~ — CLOSED

`RetryPolicy` + `withRetry`, wired into the read paths only. Deliberately narrow about what it
retries: transport failures and 5xx, never a 401 (the session is over), never a 4xx (the request
is wrong), never a decoding failure (deterministic), and **never a maintenance 503** — which is a
scheduled outage measured in minutes and arrives as a 5xx, so without its own case the 5xx rule
would hammer it three times per screen. Jittered so five screens that failed in the same signal
drop do not retry in lockstep. Writes use `RetryPolicy.none`: a duplicate `POST /chat` would
replace the chat's stored messages a second time.

### 7. Uploads die when the app is backgrounded

`URLSessionConfiguration.background` is not used. A 200-page paperbook scan is lost if the user
switches apps mid-upload. Plan step P6.1.7, not built.

---

## Tier 2 — platform features not ported

Each is genuinely reachable on the web and would work on a phone. None is built.

| Feature | Web route | Mobile value | Note |
|---|---|---|---|
| ~~**Library / bare acts**~~ | `/library/*` | **HIGH** | **Built.** Its own tab, with categories, sub-filters, search, server-side paging, and an unavailable state that distinguishes a detached corpus volume from an empty one. |
| ~~**Liquidations / auctions**~~ | `/auction-notices*` | MEDIUM | **Built**, with watchlists. This is also what the `auction` notification deep-link needed; those taps previously went nowhere. |
| ~~**Diary lookup / add a case**~~ | `/court/*/diary` | MEDIUM | **Built.** All four forums, then `POST /save-case`. This is the change that turns the app from a viewer into a client — a matter could previously only be added from a desktop. |
| ~~**File management**~~ | rename / delete / favourite / folders | MEDIUM | **Built.** Swipe and context actions, folder create/delete, with confirmations that state what is destroyed. |
| ~~**Document & table history**~~ | `/documents`, `/tables` | MEDIUM | **Built.** Every draft across every conversation, grouped by the day in India, openable and shareable. |
| ~~**Prompt enhancer**~~ | `/enhance-prompt` | **Useful** | **Built**, including the `{{PLACEHOLDER}}` fill sheet. |
| **Deep research** | `/deep-research` | — | **Rejected, not deferred.** See below. |
| **PDF split / merge / compress** | `/tools/*` | MEDIUM | Entirely client-side; no backend needed. Still not built. |
| ~~**Web search toggle**~~ | `searchMode` | LOW | **Built.** Worded "Always search the web", because the server searches on its own when the question looks like it needs it — the toggle can turn searching on but cannot turn it off. |

### Why deep research was rejected rather than deferred

`POST /deep-research` is one HTTP response that runs for **one to ten minutes** — a per-file LLM
call across every attached document, then a long streamed synthesis. There is no job id, no
poll route, and no resume: the socket is the only channel. On iOS the app being backgrounded or
the network blinking kills the run invisibly. The server keeps going and even saves the result
to chat history, but the client cannot find out.

Building it would mean shipping a screen that says "keep the app open for ten minutes" and
silently fails when the user does not. That is worse than not having it. It becomes worth
porting the moment the backend grows a job/poll API — and that, not client work, is the blocker.

---

## Tier 3 — deliberately not ported

These are correct omissions. Each is recorded in source with its reason.

| Not ported | Why |
|---|---|
| 30-tool drafting workspace, canvas editing | A contenteditable A4 page with a paginating rail is a different product, not a responsive adaptation. |
| Filing assembly | A 293-page bundle where a wrong folio gets the matter rejected at the registry should not be approved on a phone. |
| Corporate calendar | Reads company profiles from browser `localStorage` with no server representation — iOS would render it permanently empty. |
| Admin hub | Six dense tables for three admins. |
| Projects | Complete but deliberately unlinked on the web too, while it is trialled. |
| Buy / upgrade | Keeps the StoreKit obligation from attaching. |
| OCR history + "clear history" | `/ocr-history` returns **every user's** jobs; `/ocr-download` serves **any user's** output to anyone; `/ocr-clear` wipes the installation. |
| ICS subscription link | The URL is keyed only on `?userId=` — a permanent, unrevocable credential for a whole calendar. |
| Reminder picker | `remind_days` is read by nothing. No scheduler, no `VALARM`, no `reminder` producer. |
| Hearing times on the cause list | The marketing dashboard shows them; the API has no time field. |
| Chat sharing | `shareChat()` has no caller on the web either — nothing can mint a link. |

---

## A server bug the client can only report, not fix

`POST /save-case` files every matter under
`ext_id = cnr || courtCode|caseType|caseNumber|caseYear` (`sync-server.js:9619`) behind
`CREATE UNIQUE INDEX idx_cases_team_ext ON cases(team_id, ext_id)` (`:3492`). But
`bundleToCard` (`:4115`) reads `caseType`/`caseNumber`/`caseYear` off bundles that do not carry
them: NCLAT's `emptyBundle()` has no such keys and sets `cnr = ''` outright, NCLT never assigns
`caseNumber`, and a Supreme Court matter still at diary stage has no CNR.

**So every NCLAT case computes `ext_id = "trib-nclat|||"`, and a team can hold exactly one.**
The second save hits the unique index and comes back 409 — the same 409 that means "already
pinned". NCLT collides per (case type, year); SC per CNR-less matter. The web client sends the
card verbatim and has the identical bug.

iOS now detects this — a card with no CNR and no case number cannot mean "already pinned", so
that 409 is reported as a refusal and the row is **not** ticked — and warns before the save.
That is the honest limit of what a client can do. Deliberately **not** worked around by
decomposing `caseNumberText` into the missing fields: inventing an identity the server will
later disagree with trades a visible failure for an invisible one.

**The server fix is one line:** include `diaryNumber` in the `extId` fallback tuple. Every
diary route sets it, and it is the number the forum itself uses.

## Tier 4 — blocked on the backend (Phase 0)

- **Push notifications.** Zero infrastructure exists. The in-app list works; the lock-screen half does not.
- **Reminders.** Needs a scheduler reading `remind_days`.
- **Auth hardening.** The admin bypass and 81 unauthenticated routes still gate App Store submission under guideline 5.1.2.
- **`page_number` in Chroma metadata.** Without it the model cannot pin-cite from a vector hit — the product's central claim.

## Tier 5 — needs a Mac

In order, first thing to last:

1. **`xcodegen generate`** ✅ *(verified on Linux — the spec is known good and every source
   file reaches the target)*.
2. **Type-check the SwiftUI layer.** Still the largest unknown, and it is a known unknown:
   `swiftc -parse` catches every syntax error but does **not** type-check, so this is the first
   real compile the `Jithro/` directory has ever had. Expect errors; expect them to be small.
   Three classes have already been found and fixed by hand-built repros rather than by eye —
   a mutable `@Bindable` local captured in a `@Sendable` closure, a non-`Sendable`
   `UserDefaults` inside a `Sendable` struct, and ternaries whose two branches were different
   `ShapeStyle` types. Look for those first.
3. **Build the background-upload path** (Tier 1 #7). It is deliberately left undone rather than
   written blind: it cannot be exercised at all on Linux, and the failure mode is a 200-page
   scan lost silently. Write it where it can be run.
4. **Device run.** VisionKit, WKWebView, PDFKit and Keychain have never executed — only their
   call sites are tested.
5. **Signing, TestFlight, submission.**

Everything above the line is the whole of what a Mac is needed for. No feature work is waiting
on one.

---

## Core-review findings — all cleared

The adversarial review of the core logic raised ten findings beyond the two critical ones fixed
earlier. All are now closed:

| # | Finding | Fix |
|---|---|---|
| 4 | `pollUntilFinished` only checked cancellation at the loop top, so a poll in flight when Stop was tapped resurrected `live` and appended the turn **twice** — and, since history is posted back verbatim, persisted the duplicate. | Re-check after each `await`, plus a reentrancy guard on `finishStreaming`. |
| 5 | `applyTruncate` discarded to end-of-buffer, deleting retry content that arrived in the same chunk as the marker. | Keep the tail after the marker; loop for multiple rollbacks. |
| 6 | NCLT/NCLAT order fetch **could never succeed** — the tribunal proxy rejects any `court_type` that is not literally `'tribunal'`, and those cases are stored as `'nclt'`/`'nclat'`. | Return `nil` and say so honestly rather than always returning an HTML error page. |
| 7 | The busy refusal left the typed question as a bubble for a turn that exists nowhere, and it vanished on reload. | Hand it back to the composer. |
| 8 | The cause-list comparator contained a **cycle** (`20 < x`, `x < 3`, `3 < 20`), which `sort` is undefined on and can trap. `"12A"`-style items are routine. | A tuple sort key, which is a total order by construction. |
| 9 | `toggleDone` silently did nothing for an event with an unparseable `due_date`. | Say so. |
| 10 | `pageSetup: "A4"` is `JSON.parse`d server-side, throws, and is discarded. | Send valid JSON. |

Findings 1–3 (OCR logs, the OCR stall deadline, and chat history destroying artifacts and
citations) were fixed earlier.

## What is left

**Tier 1 item 7 (background upload)** is the only unbuilt Tier 1 gap. It needs
`URLSessionConfiguration.background` and an app-delegate completion hook, and — unlike
everything else here — **it cannot be verified on this machine at all**: there is no background
session on Linux and no way to background an app. Writing it unverified would put untested code
on the one path where failure means a 200-page paperbook scan is lost silently. It is the first
thing to do on a Mac, alongside the compile.

**Tier 2** now reads: PDF split/merge/compress. Deep research was rejected on the merits above.

Tiers 3, 4 and 5 are unchanged.

## Where the new screens live

Five tabs is still the ceiling, so nothing new took one:

| Screen | Reached from | Why there |
|---|---|---|
| **Find a case** | `+` on **Matters** | Adding a matter is an occasional errand you finish, not somewhere you live. |
| **Your drafts** | toolbar on **Ask** | A draft is the product of a conversation, and that is where someone goes looking for one — without having to remember *which* conversation. |
| **Liquidation auctions** | toolbar on **Library** | Like the bare acts, this is public reference material rather than the user's own matters, which is exactly what that tab is for. |
| **Auction notice** | tapping an `auction` update | The link the server sends is an API path with no screen even on the web. It is parsed into an id and routed. Those taps previously did nothing. |
| **Rewrite this prompt** | wand in the composer | Dictation and a thumb keyboard produce exactly the rough prompts it fixes. |
| **File management** | swipe / long-press in **Documents** | Editing belongs where the documents already are. |

`NotificationsView` now navigates on a typed `NotificationRoute` rather than a bare id: a
matter and an auction notice both identify themselves with a `String`, so a `[String]` path
could not tell them apart, and an auction id routed to `CaseDetailView` would have asked the
server for a matter that does not exist.

## Navigation, after the Library landed

Five tabs is the ceiling before iOS collapses the bar into a "More" list, so notifications moved
to a topbar bell with an unread count — which is where the platform's own dashboard puts them
(`src/shell/NotificationBell.jsx`) rather than in the nav.

**Today · Matters · Diary · Library · Ask**, with the bell and a Digitise/Share menu on Today.
