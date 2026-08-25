# Prompt: build the Android client

Run this from `/home/dennis/Documents/Jithro_iOS/`, where `jithro-ios/` and `emperor-ai/`
are siblings. Paste everything between the rules.

---

Build **Jithro for Android** — a native Kotlin client for the Juristar platform. Work in a new
sibling directory `jithro-android/`, with its own git repository. Do not modify `jithro-ios/`
or `emperor-ai/`.

## What is already here

- `emperor-ai/` — the **platform source**, read-only reference. This is the backend the app
  talks to. It does not run here; it is there to be read.
- `jithro-ios/` — a **finished, tested iOS client** for the same backend. Its 95 passing tests
  encode the backend's real behaviour, including a dozen edge cases that cost real effort to
  find. Treat it as a reference implementation, not as something to translate line by line.

Read `jithro-ios/CLAUDE.md` and `jithro-ios/README.md` first. They list which platform files
are worth reading and which are dead code that reads like specification.

## Ground rules

**Read the platform source rather than guessing.** Every real bug in the iOS client was found
by reading `emperor-ai/`, not by inference. The backend's wire format is hand-rolled and
largely undocumented.

**Grep for an importer before treating any platform component as specification.** These are
verified dead code: `ChatWindow.jsx`, `ChatWindow_original.jsx`, `Canvas.jsx`, `clerkConfig.js`
(its `supportedRoles` is *not* the wire contract), `models_registry.json`,
`convertTemplateTags()`, `src/pages/Library.jsx`, `POST /draft`. The live chat surface is
`src/tools/ToolWorkspace.jsx`.

**Cite `file:line` when you assert something about the backend.** If you cannot cite it, say
you are inferring it.

## Architecture

Mirror the split that made the iOS client testable, because it is what let 95 tests run
without a device:

```
jithro-android/
  core/     ← pure Kotlin/JVM. No Android imports. Unit-testable with plain JUnit.
  app/      ← Jetpack Compose UI, Android-only.
```

`core` holds: the stream parser, wire models, HTTP layer, services, and view-model logic.
`app` holds only Compose screens and Android APIs. Anything that could live in `core` should.

Unlike iOS, **everything here builds on Linux** — `./gradlew test` for the core,
`./gradlew assembleDebug` for the APK, and an emulator for the UI. There is no
build-on-another-machine step. Take advantage of that: verify continuously.

Suggested stack, but use your judgement: Kotlin, Coroutines + Flow, OkHttp or Ktor for
streaming, kotlinx.serialization, Jetpack Compose, CameraX + ML Kit document scanner,
EncryptedSharedPreferences or the Android Keystore for the token.

## Backend contracts that fail silently

Each of these cost the iOS client a real bug. Verify each against `emperor-ai/` as you go.

1. **The chat stream is not SSE.** `POST /chat` returns chunked `text/plain` with pseudo-XML
   control tags interleaved into the prose. No framing, no `data:` prefixes, **no terminator**
   — end-of-body is the only completion signal. Do not reach for an SSE client.

2. **A clean end-of-stream does not mean the answer finished.** An aborted run ends its
   response with no error bytes, so a truncated answer is indistinguishable from a complete
   one at the transport layer. `GET /stream-status` is the only authoritative signal, and it
   returns **HTTP 200 for errors too** — branch on the `error` key, never the status code.

3. **`<truncate:N/>` retroactively shortens the answer.** It means a generation round is being
   rolled back and retried. `N` is a **UTF-16 offset**, because the server computes it with
   JavaScript's `.length`. *Kotlin's `String` is UTF-16, so `substring(0, n)` matches the
   server exactly — this is the one place Android is easier than iOS, where it caused a bug.*

4. **`POST /chat` is destructive to history.** The server stores exactly the messages the
   request carried plus the answer, deleting everything else on that chat. Always send the
   full conversation. Do **not** call `POST /sync` after a turn.

5. **Filenames are sanitised per UTF-16 code unit** — `[^A-Za-z0-9._-]` → `_`, applied the way
   a JavaScript regex applies it. Status polls must use the sanitised name or they address a
   path that never resolves and the upload appears to hang forever. *Again, Kotlin's regex over
   a UTF-16 string matches natively.*

6. **`role` must be omitted, never sent empty.** `getLeadingIdentity` splices it into the
   system prompt unvalidated, and its JS default fires only on `undefined` — `null` or `""`
   lands in the prompt verbatim. It is a prompt-injection surface; keep it an enum.

7. **`model` is a fallthrough, not a whitelist.** An unrecognised alias is forwarded upstream
   verbatim rather than rejected. Keep it an enum.

8. **Timestamps arrive in three encodings** on different fields: SQLite `"yyyy-MM-dd HH:mm:ss"`
   (UTC, no zone marker), ISO-8601 with milliseconds, and epoch milliseconds on the ingest
   progress object.

9. **A 200 on the final upload chunk means "bytes received", not "file ready".** Assembly, OCR
   and indexing happen after the response closes, so a failure there produces no HTTP error —
   only an `ERROR:` string from `/upload-status`. Polling is mandatory. Only the exact
   lowercase `"ready"` (and `"scanned"`, which is usable) are terminal.

10. **Reasoning arrives under six wrappers**, not just `<think>`: also `<thinking>`,
    `<scratchpad>`, `<reasoning>`, `<internal>`, `<reflection>`.

11. **Citations travel inline in three forms** — `<@file.ext:MARK>`, `<@file.ext:MARK:7>` and
    `<@file.ext:MARK:4-9>`. Handle all three: the server strips only well-formed tokens, so one
    you fail to match renders verbatim in the middle of a pleading. Cited pages are 1-based.

12. **Artifact wrappers are a claim, not a fact.** A pleading has arrived as HTML paragraphs
    inside `<table_content>`. Sniff the body; do not trust the tag.

13. **Attachments must be sent twice** — in the top-level array *and* on the last user message,
    because the scanned-document refusal check reads them from the message.

14. **Six routes are bare-path only** (`/deep-research`, `/ocr-*`) and 404 behind production
    nginx. Check before relying on them.

## Authentication

The backend issues a bearer token but **does not enforce it** — roughly 40 routes take the
caller's identity from a client-supplied `?userId=`. Send **both** the token and `userId` on
every request, exactly as the iOS client does, so this client keeps working unchanged once the
backend is hardened. See `jithro-ios/ROADMAP.md` §0.3.

## Scope for v1

Match the iOS v1 so the two clients stay comparable:

- Sign in, token stored in encrypted storage
- Chat with documents: streaming, in-flight recovery after backgrounding, completeness
  confirmation, model and persona pickers
- Document capture: camera scan → single PDF → resumable chunked upload → ingestion polling
- Document library: browse grouped by matter, search, attach to a turn
- Citations: parsed, tappable, opening the source document at the cited page
- Artifacts: drafts and tables in a full-screen viewer, format sniffed
- Reasoning panel: plan progress and agentic work log

Out of scope: draft editing, filing assembly, court search, projects, teams, compliance
calendar, admin, billing. **Do not include any pricing or upgrade surface** — Google Play
billing rules apply to digital subscriptions, and the product currently takes no in-app money.

## Definition of done for this task

1. `./gradlew test` passes, with the core covering the fourteen contracts above. The iOS client
   has 95 tests; treat that as the bar, not a ceiling.
2. `./gradlew assembleDebug` produces an installable APK.
3. A `CLAUDE.md` in `jithro-android/` mirroring the iOS one: where the platform reference is,
   which files are dead code, the contracts, and any Android-specific traps you hit.
4. A README explaining the module split and how to build.
5. Git history with meaningful commits, in a repository of its own.

## How to work

Start by reading — `emperor-ai/src/lib/clerk_identity.js`, `output.js`, `streamManager.js`,
`canvasShape.js`, `api.js`, and the relevant parts of `sync-server.js` (grep it; it is 13,665
lines in one if/else chain, never read it whole). Then read the iOS core in
`jithro-ios/Sources/JithroCore/` and its tests, which document the behaviour precisely.

Build the parser first and test it hard before writing any UI. That ordering is why the iOS
client found nine bugs before a user ever saw one.

Tell me what you find that contradicts this prompt. It was written from the iOS work, and the
platform may have moved.
