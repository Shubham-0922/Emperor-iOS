#!/usr/bin/env node
// Regenerates the live-run golden fixture from the platform's own source.
//
//   node scripts/generate-liverun-fixtures.mjs <path-to-emperor-ai> [--check]
//
// A page that opens a chat while a run is still going has to decide what to show: follow the run,
// say it failed, or do nothing; how long to wait before asking again; what the one-line status
// reads; which text, if any, is live; and how a followed run ended. The web decides all of that in
// `src/lib/liveRun.js`, which has no imports, so it is loaded here as it stands and each case is
// run through the real functions. The app's `LiveRun` is held to those answers rather than to
// anyone's reading of the file.
//
// Output: `Tests/EmperorCoreTests/LiveRunGolden.swift`, a Swift source file rather than a
// resource, so it needs no change to Package.swift or project.yml.
//
// `--check` writes nothing and exits 1 if the fixture differs.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const source = platform && path.join(platform, 'src/lib/liveRun.js')
if (!source || !fs.existsSync(source)) {
  console.error('usage: generate-liverun-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/LiveRunGolden.swift')

const lib = await import(
  'data:text/javascript;base64,' + Buffer.from(fs.readFileSync(source, 'utf8')).toString('base64'))

const user = (content = 'Draft a bail application') => ({ role: 'user', content })
const answer = (content, extra = {}) => ({ role: 'assistant', content, ...extra })

const statuses = {
  running: { active: true, running: true, phase: 'research', elapsedMs: 5000 },
  runningWriting: { active: true, running: true, phase: 'compose', writing: true, elapsedMs: 185000 },
  notRunning: { active: false, running: false, done: true },
  legacyActive: { active: true, done: false },
  legacyInactive: { active: false, done: true },
  runningFalseActiveTrue: { active: true, running: false },
  noCheckpoint: { active: false, done: true, error: 'No messages', startedAt: null, fromLiveRun: false },
  noCheckpointLive: { active: true, done: false, isTyping: true, step: 'starting', running: true,
    phase: 'starting', writing: false, startedAt: 1700000000000, elapsedMs: 800, status: '', statusAt: null,
    statusLines: [], aliveAt: null, fromLiveRun: false, content: '' },
  forbidden: { active: false, error: 'Forbidden' },
  missing: { active: false, error: 'Missing chatId' },
}

const cases = []
const add = (fn, input, expected) => cases.push({ fn, input, expected })

// isRunLive
for (const [name, st] of Object.entries(statuses)) add('isRunLive', { name, status: st }, lib.isRunLive(st))

// followDecision
const histories = {
  empty: [],
  endsOnQuestion: [user()],
  endsOnAnswer: [user(), answer('Here is the answer.')],
  endsOnTypingCheckpoint: [user(), answer('partial…', { isTyping: true })],
}
for (const [hn, messages] of Object.entries(histories)) {
  for (const [sn, st] of Object.entries(statuses)) {
    add('followDecision', { name: `${hn}/${sn}`, messages, status: st }, lib.followDecision(messages, st))
  }
}

// nextPollDelay
for (const [prev, changed] of [[0, false], [0, true], [2000, true], [2000, false], [3000, false],
  [4500, false], [6750, false], [9000, false], [10000, false], [20000, false], [null, false]]) {
  add('nextPollDelay', { prevMs: prev, changed }, lib.nextPollDelay(prev, changed))
}

// formatElapsed
for (const ms of [0, 999, 1000, 45000, 59999, 60000, 192000, 3599000, 3600000, 3720000, 7322000, -5, 1500.7]) {
  add('formatElapsed', { ms }, lib.formatElapsed(ms))
}

// liveStatusText (elapsed always given, so the clock never enters)
const textCases = [
  ['starting', { active: true, phase: 'starting', elapsedMs: 0 }, ''],
  ['friendly', { active: true, phase: 'research', elapsedMs: 45000 }, 'Reading page 3 of the petition…'],
  ['writing', { active: true, phase: 'research', writing: true, elapsedMs: 192000 }, 'ignored'],
  ['compose', { active: true, phase: 'compose', elapsedMs: 61000 }, 'ignored'],
  ['wrapup', { active: true, phase: 'wrapup', elapsedMs: 3720000 }, 'ignored'],
  ['wrapupFriendly', { active: true, phase: 'wrapup', elapsedMs: 100 }, ''],
]
for (const [name, st, friendly] of textCases) {
  add('liveStatusText', { name, status: st, friendly }, lib.liveStatusText(st, friendly))
}

// logFromStatusLines
const lineSets = {
  none: [],
  noSteps: ['Planning the work', 'Thinking'],
  oneStep: ['Reading page 4 of bail.pdf'],
  mixed: ['Planning', ' Searching the record for: bail ', 'Mapping the structure of notice.pdf',
    'Reading pages 1-3 of notice.pdf', 'Drafting'],
  caseInsensitive: ['reading PAGE 2', 'SEARCHING THE RECORD'],
  notAStep: ['Reading the room', 'Reading page'],
}
for (const [name, lines] of Object.entries(lineSets)) {
  add('logFromStatusLines', { name, lines }, lib.logFromStatusLines(lines))
}

// liveContent
const contentCases = [
  ['fromLiveTrue', { active: true, content: 'live text', fromLiveRun: true }, ['old']],
  ['fromLiveFalse', { active: true, content: 'previous answer', fromLiveRun: false }, []],
  ['fromLiveFalseUnknown', { active: true, content: 'previous answer', fromLiveRun: false }, ['previous answer']],
  ['legacyKnown', { active: true, content: ' previous answer ' }, ['previous answer']],
  ['legacyUnknown', { active: true, content: 'new text' }, ['previous answer']],
  ['legacyNoSet', { active: true, content: 'new text' }, null],
  ['blank', { active: true, content: '  \n ', fromLiveRun: true }, []],
  ['missing', { active: false }, []],
]
for (const [name, st, known] of contentCases) {
  add('liveContent', { name, status: st, known }, lib.liveContent(st, known && new Set(known)))
}

// runOutcome
const outcomes = {
  empty: [],
  endsOnQuestion: [user()],
  finished: [user(), answer('A finished answer.')],
  blank: [user(), answer('   ')],
  stopped: [user(), answer('Some text', { stoppedBy: 'user', incomplete: true })],
  flagged: [user(), answer('Partway', { incomplete: true })],
  marker: [user(), answer('Text\n\nThis response was interrupted and is incomplete.')],
  noResponse: [user(), answer('No response was produced')],
  stoppedByOther: [user(), answer('Text', { stoppedBy: 'server' })],
}
for (const [name, saved] of Object.entries(outcomes)) {
  add('runOutcome', { name, saved }, lib.runOutcome(saved))
}

// failureText
for (const reason of ['lost', 'timeout', 'no-answer', 'anything-else', null]) {
  add('failureText', { reason }, lib.failureText(reason))
}

const constants = {
  pollMinMs: lib.POLL_MIN_MS, pollMaxMs: lib.POLL_MAX_MS,
  watchMaxMs: lib.WATCH_MAX_MS, maxPollFailures: lib.MAX_POLL_FAILURES,
}

const json = JSON.stringify({ constants, cases }, null, 1)
if (json.includes('"""#')) throw new Error('fixture contains the raw-string terminator')
const swift = `// Generated by scripts/generate-liverun-fixtures.mjs from the platform's own
// src/lib/liveRun.js. Do not edit by hand — regenerate it.
//
// Each case is one call to a function of that file: \`input\` is what it was given and
// \`expected\` is what it returned.

enum LiveRunGolden {
    static let json = #"""
${json}
"""#
}
`

const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
if (before === swift) {
  console.log('live-run fixtures: up to date')
  process.exit(0)
}
if (checkOnly) {
  console.error('live-run fixtures: out of date — rerun without --check')
  process.exit(1)
}
fs.writeFileSync(out, swift)
console.log(`live-run fixtures: wrote ${cases.length} cases`)
