# Jithro — working notes

**Jithro** is this iOS app. **Juristar** (a.k.a. Emperor AI) is the backend platform it talks
to. Only the app was renamed; the platform and website keep their names.

## Where the platform reference lives

This app is a client for a backend whose wire format is hand-rolled and largely undocumented.
**Read the platform source rather than guessing** — that is how every real bug in this client
was found.

Expected local layout:

```
<your projects dir>/
  jithro-ios/     ← this repo
  emperor-ai/     ← platform source, reference only. Never edit.
```

If `emperor-ai/` sits elsewhere, adjust the paths below. On the origin server it lives at
`/var/www/emperor-ai`, which is what the citations in `README.md` and `ROADMAP.md` refer to.

The reference copy is **source only** — no `node_modules`, no `Data/`, no `chroma_db/`, no
`venv/`. It does not run. It is there to be read.

### The files worth reading

| Path | Why |
|---|---|
| `sync-server.js` | Every backend route. One 13,665-line `if/else` chain — **grep it, never read it whole** |
| `src/lib/clerk_identity.js` | The only live system prompt. Defines citation tokens and artifact wrappers |
| `src/lib/output.js` | How the web client strips control tags — the spec our `StreamContent` mirrors |
| `src/lib/streamManager.js` | Plan cursor + agentic work log — the spec our `ReasoningTracker` ports |
| `src/lib/canvasShape.js` | Why artifact format must be sniffed, not trusted |
| `src/lib/api.js` | The transport layer: `<status>` extraction, chunk holdback |
| `src/providers/OpenRouterProvider.js` | Model aliases, retries, `<truncate:N/>` |
| `src/roles/roleConfig.js` | The real role contract (7 UI roles → 3 wire values) |
| `lib/filing/index.js` | The one module that authenticates properly — copy this pattern |
| `AGENTS.md` | Corrected 2026-08-25; every claim carries a `file:line` |

### Do not trust these — verified dead code

`ChatWindow.jsx`, `ChatWindow_original.jsx`, `Canvas.jsx`, `clerkConfig.js` (its
`supportedRoles` is **not** the wire contract), `models_registry.json`,
`convertTemplateTags()`, `src/pages/Library.jsx`, `FeedbackWidget.jsx`, `POST /draft`,
`/library-books/*`, `/bare-acts/*`.

**Always `grep` for an importer before treating a component as specification.** The live chat
surface is `src/tools/ToolWorkspace.jsx`, rendering through `src/tools/renderers/Markdown.jsx`.

## Repository

Jithro is its own repository, independent of the platform. Origin is a bare repo on the
server at `/srv/git/Jithro.git`, matching the convention `EmperorAI.git` uses.

```bash
git clone root@<server>:/srv/git/Jithro.git jithro-ios
```

Push back with `git push`. The platform lives in a separate repo and must never be committed
here — the `emperor-ai/` copy beside this one is read-only reference.

## Working on Linux (the normal case)

Development happens on Linux; a Mac is used only for what genuinely cannot be done without
one — compiling the SwiftUI layer, the simulator, signing, and submission. So **push as much
as possible into `Sources/JithroCore/`**, which builds and tests here.

```bash
sudo apt install swiftlang     # Swift 6.1.3 on Ubuntu; no iOS SDK, but the core builds
cd jithro-ios && swift test    # 95 tests
```

View models live in the core for this reason — turn state, recovery and error handling are
where the real bugs are, and they are all verifiable without a device.

### Two Linux toolchain traps, both already worked around

**1. `@Observable` compiles but does not link on Linux.** The apt toolchain ships a
`libswiftObservation.so` with an undefined `swift::threading::fatal`, so the macro builds and
then fails at link time — taking the whole test suite with it. The workaround is to apply the
attribute only on Apple platforms:

```swift
#if canImport(Darwin)
import Observation
#endif

#if canImport(Darwin)
@Observable
#endif
@MainActor
final class SomeViewModel { … }
```

On Linux it is then a plain class, which is exactly what tests need. Note `swift file.swift`
runs *interpreted* and never links, so a quick one-off script will wrongly suggest it works.

**2. Linux XCTest cannot invoke a `@MainActor` test method.** It aborts the run with
`Could not cast value of type '(Tests) -> @MainActor () -> ()'`. Keep test classes
un-isolated and hop through a **free function** helper — not a method, because an
`XCTestCase` is not `Sendable` and Swift 6 rejects capturing `self` in a `@MainActor`
closure. See `ChatViewModelTests.swift` for the working shape.

**3. A stale `.build` can produce a phantom linker error.** If you hit an undefined symbol
that makes no sense against the current source, `rm -rf .build` before investigating further.

## How to work on this repo

- **Put logic in `Sources/JithroCore/`.** It is Foundation-only — no UIKit, no SwiftUI — so it
  compiles and tests anywhere, including Linux and CI. `swift test` runs 95 tests in under a
  second. Anything that could plausibly live there should.
- **The SwiftUI layer in `Jithro/` needs Xcode.** It was authored on a Linux box with no iOS
  SDK, so parts of it have never been compiled.
- **The Xcode project is generated**, not committed: `xcodegen generate`. Add files by editing
  `project.yml`.
- The app target compiles `Sources/JithroCore` directly, so the tested code and the shipped
  code are the same bytes.

## Backend gotchas that bite silently

Full detail in `README.md`. The short list:

1. **`POST /chat` is destructive to history** — the server stores exactly the messages you sent
   plus the answer, deleting the rest. Always send the full conversation.
2. **A clean end-of-stream does not mean the answer finished.** Confirm with `/stream-status`.
3. **`<truncate:N/>` offsets are UTF-16**, because the server computes them in JavaScript.
4. **Filenames are sanitised per UTF-16 code unit** — mapping over Swift `Character`s breaks
   every Devanagari filename.
5. **`role` must be omitted, never sent empty** — an empty string lands in the system prompt.
6. **Timestamps arrive in three encodings** on different fields. Use `WireDate`.
7. **Status codes are unreliable** — `/stream-status` returns 200 for errors. Branch on `error`.
8. **A 200 on the last upload chunk means "bytes received", not "file ready".** Poll.

## Runtime connectivity

The app talks to `https://dev.emperorailabs.com/api` (`APIConfig.production`). That host is
public — it needs no VPN and no tunnel of your own — so a build running on your Mac or a device
reaches the live platform straight away.

**It is also unauthenticated.** Anyone who knows a user id can read that user's matters. The
client already sends both a bearer token and `userId` so it will keep working unchanged once
the backend is hardened. See `ROADMAP.md` §0.3.

## The two reports

- `ROADMAP.md` — technical status and v1 plan, with citations.
- `REPORT.md` — the same ground in plain English.
