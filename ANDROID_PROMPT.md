# Prompt: build the Android client

Written to be pasted into a **fresh Claude Code session** started in
`/home/dennis/Documents/JithroApps/Jithro_Android/`, on your local Linux machine. It assumes no prior
context. Everything between the rules is the prompt.

Before pasting, check the layout is in place:

```bash
ls /home/dennis/Documents/JithroApps/
# expect: emperor-ai  Jithro_Android  Jithro_iOS
```

---

Build **Jithro for Android** — a native Kotlin client for the Juristar legal-AI platform.

You are starting fresh with no prior context. Work **in the current directory**,
`/home/dennis/Documents/JithroApps/Jithro_Android/`, and initialise a git repository here.

Two sibling directories are your references. **Never modify either:**

- `../emperor-ai/` — the platform source
- `../Jithro_iOS/` — the finished iOS client for the same backend

## Your environment

- **Local Linux machine.** Unlike the iOS client, Android builds and tests entirely here —
  there is no other machine in the loop. Verify continuously rather than deferring.
- **The backend is not running locally.** `../emperor-ai/` is a read-only source snapshot with
  no `node_modules`, no database, no `.git`. Do not try to start it. Verify claims by
  **reading the source**, not by calling a server.
- The live API is `https://dev.emperorailabs.com/api`. You may need it eventually, but note the
  warning under *Authentication* before you touch it.
- You may need to install a JDK (17+) and the Android SDK command-line tools. Check first and
  tell me what is missing rather than assuming.

## What is already here

- **`../emperor-ai/`** — the platform source. This is the backend the app talks to. Its wire
  format is hand-rolled and largely undocumented, so this is the ground truth.
- **`../Jithro_iOS/`** — a finished, tested iOS client for the same backend, with 95 passing
  tests that encode the backend's real behaviour, including a dozen edge cases that were
  expensive to find. A reference implementation, not something to translate line by line.

Read these first, in order:

1. `../Jithro_iOS/CLAUDE.md` — which platform files matter, which are dead code
2. `../Jithro_iOS/README.md` — the backend contracts that fail silently
3. `../Jithro_iOS/ROADMAP.md` — what the platform actually is, what is broken in it, and why
   v1 is scoped the way it is
4. `../Jithro_iOS/Sources/JithroCore/` and its tests — the behaviour, stated precisely

## Ground rules

**Read `../emperor-ai/` rather than guessing.** Every real bug in the iOS client was found
that way.

**Grep for an importer before treating any platform component as specification.** These are
verified dead code and will mislead you: `ChatWindow.jsx`, `ChatWindow_original.jsx`,
`Canvas.jsx`, `clerkConfig.js` (its `supportedRoles` is *not* the wire contract),
`models_registry.json`, `convertTemplateTags()`, `src/pages/Library.jsx`, `POST /draft`. The
live chat surface is `src/tools/ToolWorkspace.jsx`.

**Cite `file:line` when you assert something about the backend.** If you are inferring rather
than citing, say so.

**`sync-server.js` is 13,665 lines in a single if/else chain — grep it, never read it whole.**

## Architecture

Mirror the split that made the iOS client testable without a device:

```
Jithro_Android/          ← you are here
  core/     ← pure Kotlin/JVM. No Android imports. Plain JUnit tests.
  app/      ← Jetpack Compose UI and Android APIs only.
```

`core` holds the stream parser, wire models, HTTP layer, services, and view-model logic.
Anything that could live in `core` should.

Suggested stack, but use your judgement: Kotlin, Coroutines + Flow, OkHttp or Ktor,
kotlinx.serialization, Jetpack Compose, CameraX + ML Kit document scanner,
EncryptedSharedPreferences or the Android Keystore for the token.

## Backend contracts that fail silently

Each cost the iOS client a real bug. Verify each against `../emperor-ai/` as you implement it.

1. **The chat stream is not SSE.** `POST /chat` returns chunked `text/plain` with pseudo-XML
   control tags interleaved into the prose. No framing, no `data:` prefixes, **no terminator**
   — end-of-body is the only completion signal. Do not reach for an SSE client.

2. **A clean end-of-stream does not mean the answer finished.** An aborted run ends with no
   error bytes, so a truncated answer looks exactly like a complete one. `GET /stream-status`
   is the only authoritative signal — and it returns **HTTP 200 for errors too**, so branch on
   the `error` key, never the status code.

3. **`<truncate:N/>` retroactively shortens the answer** — a round is being rolled back and
   retried. `N` is a **UTF-16 offset**, because the server computes it with JavaScript's
   `.length`. *Kotlin's `String` is UTF-16, so `substring(0, n)` matches the server exactly.
   This is one of two places Android is easier than iOS, where it caused a bug.*

4. **`POST /chat` is destructive to history.** The server stores exactly the messages the
   request carried plus the answer, deleting everything else on that chat. Always send the
   full conversation. Do **not** call `POST /sync` after a turn.

5. **Filenames are sanitised per UTF-16 code unit** — `[^A-Za-z0-9._-]` → `_`, applied as a
   JavaScript regex would. Status polls must use the sanitised name or they address a path
   that never resolves and the upload appears to hang forever. *Kotlin's regex over a UTF-16
   string matches natively — the second place this is easier than Swift.*

6. **`role` must be omitted, never sent empty.** The server splices it into the system prompt
   unvalidated, and its JS default fires only on `undefined` — `null` or `""` lands in the
   prompt verbatim. It is a prompt-injection surface; keep it an enum.

7. **`model` is a fallthrough, not a whitelist** — an unrecognised alias is forwarded upstream
   rather than rejected. Keep it an enum.

8. **Timestamps arrive in three encodings** on different fields: SQLite `"yyyy-MM-dd HH:mm:ss"`
   (UTC, no zone marker), ISO-8601 with milliseconds, and epoch milliseconds on the ingest
   progress object.

9. **A 200 on the final upload chunk means "bytes received", not "file ready".** Assembly, OCR
   and indexing run after the response closes, so a failure there produces no HTTP error, only
   an `ERROR:` string from `/upload-status`. Polling is mandatory. Only the exact lowercase
   `"ready"` — and `"scanned"`, which is usable — are terminal.

10. **Reasoning arrives under six wrappers**, not just `<think>`: also `<thinking>`,
    `<scratchpad>`, `<reasoning>`, `<internal>`, `<reflection>`.

11. **Citations travel inline in three forms** — `<@file.ext:MARK>`, `<@file.ext:MARK:7>`,
    `<@file.ext:MARK:4-9>`. Handle all three: the server strips only well-formed tokens, so one
    you fail to match renders verbatim in the middle of a pleading. Cited pages are 1-based.

12. **Artifact wrappers are a claim, not a fact.** A pleading has arrived as HTML paragraphs
    inside `<table_content>`. Sniff the body; do not trust the tag.

13. **Attachments must be sent twice** — in the top-level array *and* on the last user message,
    because the scanned-document refusal check reads them from the message.

14. **Six routes are bare-path only** (`/deep-research`, `/ocr-*`) and 404 behind production
    nginx. Check before relying on them.

## Authentication — read before calling the live API

The backend issues a bearer token but **does not enforce it**. Roughly 40 routes take the
caller's identity from a client-supplied `?userId=` parameter, and the dev host is publicly
reachable with no access policy. It holds **real client legal matters**.

So:

- Send **both** the token and `userId` on every request, as the iOS client does, so this
  client keeps working unchanged once the backend is hardened.
- When testing against the live host, use **only an account you own**. Do not enumerate user
  ids, and do not read data belonging to anyone else — it is trivially possible and it is
  privileged material.
- Prefer fixtures and a fake server for tests. The iOS client tests entirely offline; do the
  same.

## Scope for v1

Match the iOS v1 so the two clients stay comparable:

- Sign in, token in encrypted storage
- Chat with documents: streaming, in-flight recovery after backgrounding, completeness
  confirmation, model and persona pickers
- Document capture: camera scan → single PDF → resumable chunked upload → ingestion polling
- Document library: browse grouped by matter, search, attach to a turn
- Citations: parsed, tappable, opening the source document at the cited page
- Artifacts: drafts and tables in a full-screen viewer, format sniffed from the body
- Reasoning panel: plan progress and agentic work log

Out of scope: draft editing, filing assembly, court search, projects, teams, compliance
calendar, admin, billing.

**Include no pricing or upgrade surface.** Google Play's billing rules apply to digital
subscriptions, and the product currently takes no in-app money — keep it that way.

## Definition of done

1. `./gradlew test` passes, with the core covering the fourteen contracts above. The iOS
   client has 95 tests; treat that as the bar, not a ceiling.
2. `./gradlew assembleDebug` produces an installable APK.
3. A `CLAUDE.md` here mirroring `../Jithro_iOS/CLAUDE.md`: where the reference is, what is
   dead code, the contracts, and any Android-specific traps you hit.
4. A README covering the module split and how to build.
5. Git history with meaningful commits, in a repository of its own.

## How to work

Build the parser first and test it hard before writing any UI. That ordering is why the iOS
client found nine bugs before a user ever saw one.

Tell me anything you find that contradicts this prompt — it was written from the iOS work in
August 2026, and the platform may have moved since.
