# Emperor — Where We Are, and What's Left

**A plain-English report**
Date: 25 August 2026

---

## What Emperor is

**Emperor** is the iPhone and iPad app we are building for your platform.

**Emperor** is also the platform itself — the website, the servers, the AI. The platform used to
be called Juristar; app and platform now share one name. This app is the part that sits in a
lawyer's pocket and talks to the rest.

The app uses the same logo as your landing page.

**The idea in one sentence:** your platform today is something a lawyer sits down at. Emperor is
something a lawyer carries — it answers *"what do I have tomorrow?"*, *"what happened on my
cases?"*, *"what does this document say?"* — from a car, a corridor, or a courtroom.

---

# Part 1 — What we have built

## The short version

We have built the hardest and most fragile part of the app, and proved it works. About a
third of the finished product exists. **95 automated tests** check it, and all 95 pass.

Think of it like building a car: the engine, gearbox and wiring are done and tested on the
bench. The bodywork and the dashboard are partly done. It has not yet been driven, because
that needs a Mac.

## What actually works today

**Signing in.** A lawyer can log in. Their login is stored in the iPhone's secure vault — the
same protected area Apple uses for passwords and payment cards — not in ordinary app storage.
It stays signed in between uses.

**Asking questions about documents.** The core feature. A lawyer types or dictates a question,
and the answer streams back word by word, exactly as it does on the website. If they close the
app halfway through, the answer keeps being written on your server, and the app picks it back
up when they return. Nothing is lost.

**Scanning paperbooks with the camera.** Point the phone at a paper order or pleading,
photograph the pages, and the app turns them into a single PDF, uploads it to the document
library, and waits until your server has finished reading it. Then it can be asked about. This
is the feature that most justifies having a phone app at all — a scanner in your pocket.

**Uploading large files safely.** Documents are sent in 10 MB pieces rather than all at once,
so a dropped signal outside a courthouse does not mean starting over.

**The document library.** Browse everything already uploaded, grouped by matter, with search.
Files still being processed are shown as unavailable rather than pretending to be ready.

**Citations you can tap.** This is the one worth dwelling on, because it is your product's
whole promise. When the AI says *"the sale completed on 4 March 2019"*, it attaches an
invisible marker naming the document and the page. Emperor reads those markers and turns them
into little tappable chips under the answer. Tap one and the actual PDF opens **at that exact
page**. The claim "every line names a page you can open" becomes literally true, in the hand.

**Reading drafts.** When the AI produces a full document — a writ petition, a chronology — the
app shows it as a proper formatted document, not raw code. Centred headings, underlined court
names, bordered tables: what a lawyer expects to see.

**Choosing how it thinks.** A Quick/Thinking switch and a persona picker (Litigator, Corporate
Counsel, Arbitrator or Judge), matching the website exactly.

**Showing its work.** A collapsible panel showing what the AI actually did — which documents it
opened, which pages it read, in what order. Closed by default, because the answer is the point.
But when an answer looks wrong, the first question is always *"which documents did it actually
read?"*, and now that is answerable.

## Nine bugs we caught before they reached anyone

Every one of these was caught by an automated test or by reading your platform's own code —
not by a user hitting it. Two would have been genuinely nasty:

**Hindi and regional filenames would have hung forever.** Your server renames uploaded files,
replacing anything that isn't a plain English letter or number with an underscore. It does
this letter by letter in a very specific way. Our first version counted Devanagari characters
differently, so a file named `देखिए.pdf` got three underscores where the server made five. The
app would then keep asking the server about a file that, from its point of view, did not
exist — forever. The upload would spin and never finish and never fail. We confirmed the
correct behaviour by running your server's own code, and matched it.

**Some citations would have appeared as gibberish inside pleadings.** Your AI writes citations
in three formats — no page, one page, or a page range. We handled two of the three. The
missing one is the single-page form. And because your server only cleans up citations it
recognises, an unrecognised one is left in place — meaning raw text like `<@order.pdf:P-5:7>`
would have appeared in the middle of a draft petition. Found by reading the specification your
own AI is given.

The other seven: a crash on any answer containing an Indian-language character or a rupee
symbol; corrupted text when the AI revised itself mid-answer; the AI's private "thinking"
leaking into view under five different labels; the phrase "damages < 50,000" silently losing
its ending; and drafts rendering as raw code when the AI put them in the wrong wrapper.

## Why so much testing on something not yet running

This computer can compile the app's *logic* but cannot build an actual iPhone app — that needs
a Mac. So we deliberately split the app in two:

- **The logic half** — reading your server's replies, handling errors, understanding
  citations, and now the screen *behaviour* too. Fully testable on Linux. This is where bugs
  hide, and it is now covered by 151 tests.
- **The screens half** — buttons, layouts, colours. Written but not yet compiled.

Bugs in the screens half are obvious the moment you run it. Bugs in the logic half are the
kind that show up three weeks later in front of a client. We front-loaded the risk.

---

# Part 2 — What we found in your platform

To build the app properly we read the platform in detail and checked the live server and
database. Some of what follows is uncomfortable, and all of it is verifiable.

## The good news

**The valuable parts are genuinely used.** Cases (199 of them, with about 14,600 attached
items), chat, document processing, and the annexure register are all in real daily use. The
AI has cost about $36 over 18 days — modest and healthy.

**The auction database is a real asset.** 8,706 IBBI liquidation notices covering 1,392
companies. Nobody else has assembled that conveniently.

**The court-tracking design is genuinely good.** When it runs, it checks your cases every 30
minutes and can tell the difference between a real new order and a portal glitch.

## The uncomfortable news

### 1. Three background services are switched off

Your platform is designed to run seven services. Three are not running, including the one that
checks the courts.

**The consequence:** your platform has not generated a single notification since **1 August** —
three and a half weeks ago. Cases are not updating. The auction list has not refreshed since
31 July, but still presents itself as "live auctions" with no indication it is a month old. A
user deciding whether to bid is being misled by a stale screen.

This is a configuration issue, not a code issue. Restarting them is a few minutes' work.

### 2. Anyone on the internet can read anyone's files

This is the serious one.

Your system issues each user a secure login token. But no part of your server ever *checks* it.
Instead, roughly 40 different functions simply trust whatever user number the request claims to
be. Change the number in the web address, get someone else's data.

We verified this from the command line with no password:

> asking for user #1's notification count returned **109** — no login required.

Because your development site is publicly reachable with no access restriction, and because it
holds real client matters, **anyone who knows the address can read any user's documents,
cases and calendar by changing a number in a link.**

Three related holes: anyone can overwrite any user's profile; and three support endpoints
return every user's name, email, complaints and uploaded screenshots to anyone who asks.

For a product handling privileged legal material, this is the thing to fix first. Apple's
reviewers will also find it, and it is a rejection.

The encouraging part: one module in your own codebase — the filing assembly — already does it
correctly. The pattern exists; it needs applying everywhere else.

### 3. Push notifications do not exist

Not "partly built" — there is no foundation at all. What looks like notifications on the
website only works while the browser tab is open.

This matters because **push is the single strongest reason to install a phone app**. A lawyer
learning about a new order while in transit is the whole pitch. Right now that pipe does not
exist and must be built from scratch.

There is a silver lining: everything that creates a notification passes through one function,
so we only need to add the phone-alerting step in one place.

### 4. "Remind me 3 days before" does nothing

Users can set a reminder on a deadline. The setting is saved. The app displays it. **Nothing
ever reads it.** No reminder is ever sent.

For a legal calendar, this is the most dangerous half-finished thing in the product — the
software makes a promise about a deadline and silently does not keep it.

### 5. Every "Download PDF" button is broken

One line of configuration points at a folder that does not exist on your server. Every PDF
download returns an error. Confirmed live. It is a one-line fix that repairs three features at
once.

### 6. Other things that are broken right now

- The **Corporate Calendar** page freezes for 25+ seconds and never loads. The identical
  mistake is documented *and fixed* twenty lines further down the same file.
- The **reference library** — the "224,361 documents" headline on your website — shows
  **nothing**. The storage drive is not attached. It fails silently rather than saying so.
- **About 20 of 25 High Courts** cannot be searched. The government portal they share started
  refusing requests on 17 July.
- Every **auction alert** ever sent links to a page that does not exist.
- **Deleting a case** leaves all its attached items behind, accumulating forever.
- **Password reset** saves the new password unscrambled.

### 7. Some features are built but nobody uses them

The database tells a clear story:

| Feature | Reality |
|---|---|
| **Projects** | 1 record, 0 timeline entries — built, never used |
| **Teams** | 18 teams, every one with a single member — never used |
| **Compliance events** | 8 records |
| **Purchases** | 1 enquiry, ever |
| **Filing bundles** | Assembled once; the file is gone from disk |

This is not criticism — it is a map. **Do not build the phone app around the unused half.**

There is also a large amount of code that reads like documentation but is switched off and
unreachable. We verified each one before trusting anything.

---

# Part 3 — The plan for version 1

## What version 1 should be

> **A litigator's companion in transit.** Read, capture, ask, and be told.

**In:** chat with documents · camera scanning · document library · tomorrow's hearings · case
details · notifications with push alerts · calendar · document scanning and translation ·
profile.

**Out:** editing drafts, assembling filing bundles, full court search, projects, teams,
compliance calendar, admin screens, billing.

The reason for the "out" list: a 293-page court bundle where a wrong page number gets your
matter rejected at the registry counter should not be approved on a phone. That is a desk job,
and no amount of good design changes it.

---

## Stage 0 — Repairs to the platform

Mostly not app work. But much of the app is dishonest without it.

**0.1 — Fix the PDF folder path.** One line. Repairs every PDF download. *Hours.*

**0.2 — Restart the three stopped services.** Configuration only. Notifications and case
updates start flowing again. *Hours.*

**0.3 — Make the server check who is asking.** The big one. Roughly 40 places, using the
pattern that already exists in your filing module. Keep the old behaviour as a fallback at
first so nothing breaks, watch until nobody relies on it, then remove it. Also: put an access
restriction on the development site **today**, as a stopgap. *One to two weeks.*

**0.4 — Build push notifications.** A table of phone identities, a way to register one, an
Apple certificate, and a sender. Add the trigger inside the one function every notification
already passes through. Group alerts so ten orders on one case is one buzz, not ten. *One
week.*

**0.5 — Build the reminder job.** A daily check for approaching deadlines and hearings. Makes
the existing "remind me" setting real. *Two to three days, and the highest value on this list.*

**0.6 — Housekeeping.** Make seven web addresses reachable from the live site (they currently
only work in development — the app would get "not found" in production). Fix the freezing
calendar page. Fix the calendar-subscription date format. Make case deletion clean up after
itself.

**0.7 — Stop showing stale data as fresh.** Auctions need an "as of" date. Dark courts need to
say "this court's portal is down", not "no case found".

---

## Stage 1 — Get the app running (about a week)

1. Install the project generator on your Mac, open it in Xcode.
2. Fix the first round of compiler complaints — expected, since the screens have never been
   compiled.
3. Add your Apple developer account.
4. Run it on a real iPhone, not just the simulator — the camera needs real hardware.
5. Set up automatic testing so the 151 tests run on every change.
6. Separate settings for development and live, so a test build cannot talk to real client data.
7. Make the app usable with no signal: show the last-known information with a clear "as of"
   time, never silently stale.

**At the end of this stage you have a real app on a real phone** doing chat, scanning and
documents.

---

## Stage 2 — Hearings and cases (two to three weeks)

The screen that makes the app worth opening.

**Tomorrow's hearings.** A day view that jumps to the next day you actually have something,
rather than stepping through empty days. The whole range arrives in one request, so it works
offline.

> **One piece of wording is non-negotiable: "Your cases only — not the court's cause list."**
> Your own web code carries a blunt warning about this. A lawyer who reads it as the official
> list, sees nothing, and concludes their day is clear has been actively misled. We copy that
> warning word for word.

Also note: the data contains no hearing *times*. We will not invent them.

**Case list and detail.** Grouped by next hearing, searchable. Overview, hearings and orders
first. Court-supplied information clearly marked as such. Last-updated shown honestly — if a
case has never been checked, say so.

**Two things a lawyer can write from a phone:** add a note, add a task. Everything else is a
desk job.

**Optional: diary-number lookup.** One field, one year, no puzzle-image. A lawyer who gets a
diary number by WhatsApp can check its status in ten seconds.

---

## Stage 3 — Notifications and alerts (one to two weeks)

*Needs 0.2 and 0.4 finished.*

Ask permission at a sensible moment — after the first case is viewed, not on first launch,
which is when most people say no. Register the phone on sign-in, remove it on sign-out. A
notification list with an unread badge. Tapping an alert opens the relevant case.

---

## Stage 4 — Scanning and translation (one to two weeks)

*Needs 0.6 finished.*

Photograph a document, pick from 24 languages, get a Word file back. Runs on the server while
the phone is in a pocket; alerts when done.

The scenario: opposing counsel hands you a Marathi order outside court. You photograph it, and
read it in English before your matter is called. **This is the most phone-shaped feature in
the entire product**, and it does not exist on mobile today.

One fix needed: the current route does not record which user requested the work, so the cost
is logged against nobody. Your own code comments identify this.

---

## Stage 5 — Calendar (one week)

Month and agenda views. Create and edit deadlines. **Only offer the reminder setting once 0.5
exists** — otherwise the app repeats a promise it cannot keep. Optionally write hearings into
the iPhone's own Calendar.

We will **not** ship the calendar-subscription link until it can be revoked. Today it is a
permanent, unchangeable web address that exposes a lawyer's entire hearing schedule to anyone
who has it.

---

## Stage 6 — Polish (one to two weeks)

Larger text support (your users skew older), VoiceOver, dark mode, iPad layout, proper table
rendering, uploads that continue when the app is backgrounded, and sign-out that clears
everything.

---

## Stage 7 — App Store submission (one to two weeks)

**Five things will get the app rejected if not handled:**

1. **The security issue in 0.3.** Reviewers test for exactly this.
2. **No way to create an account.** Today accounts are made by an administrator. Either add
   sign-up, or supply a working test account with an explanation.
3. **Any "Upgrade" button or price.** Apple requires their payment system for digital
   subscriptions sold in-app, taking 15-30%. Right now you are clean, because the app takes no
   money — the website collects an enquiry and emails you. **That stays true only if the iPhone
   app contains no path to pricing.** Leave it out entirely.
4. **The "Preview build" banner** on your website. Apple rejects apps that present as beta.
5. **No legal disclaimer.** An AI drafting legal documents needs a visible one.

Also required: an App Store privacy declaration, crash reporting, and a small TestFlight round
with two or three real advocates before submitting.

---

# Part 4 — Timeline

| Stage | Work | Time |
|---|---|---|
| 0.1 + 0.2 | Repairs and restarts | 1 day |
| 1 | App running on a phone | 1 week |
| 2 | Hearings and cases | 2–3 weeks |
| 0.3 | Server security *(parallel)* | 1–2 weeks |
| 0.4 + 0.5 + 3 | Push and reminders | 2–3 weeks |
| 4 | Scanning and translation | 1–2 weeks |
| 5 | Calendar | 1 week |
| 6 | Polish | 1–2 weeks |
| 7 | App Store | 1–2 weeks |

**Roughly 10–14 weeks to a submitted app**, with the security work running alongside the app
work rather than blocking it.

**Two useful milestones along the way:**

- **After Stage 2 (~4 weeks):** a genuinely useful internal app. Chat, scanning, documents,
  tomorrow's hearings, case details. Worth putting in front of a friendly advocate.
- **After Stage 3 (~7 weeks):** an app worth *keeping* installed, because it now tells you
  things instead of waiting to be asked.

---

# Part 5 — Six questions only you can answer

**1. Cases or Projects?** Your code describes "Projects" as the eventual replacement for
"Cases". But Projects has one record and zero activity, while Cases has 199 records in real
use. We plan to build on Cases. If Projects is genuinely the future, tell us now — this
decision is expensive to reverse later.

**2. Are the 20 dark High Courts being fixed?** If not, mobile case coverage is the Supreme
Court, six High Courts, NCLT, NCLAT, ten tribunals and consumer forums. That is still
substantial, but we should describe it honestly rather than let users discover it.

**3. When does payment go live?** The moment Razorpay launches, Apple's payment rules change
what the app may contain. Decide the phone billing story before, not after.

**4. Is the reference library coming back?** "224,361 documents" is a headline claim on your
website and currently shows nothing. Either reattach the drive or soften the claim.

**5. Do teams matter?** 18 teams, every one with one member. If collaboration is not on the
roadmap, the app treats teams as invisible plumbing and saves real effort.

**6. How much backend work will you take on?** Stage 0 is the difference between an app that
tells the truth and an app that looks finished. If backend capacity is short, we should
sequence the app around what will realistically be fixed.

---

# In closing

The engine is built and tested. The platform underneath it is more capable than it currently
appears — several of its best features are switched off rather than missing, and a few one-line
faults are hiding real work that already exists.

The genuine blockers are two: **the server does not check who is asking**, and **there is no
way to alert a phone**. Neither is exotic. Both need doing before this app can be put in front
of a lawyer honestly, let alone submitted to Apple.

Everything else is ordinary work in a sensible order.
