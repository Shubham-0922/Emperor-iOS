#!/usr/bin/env node
// Regenerates Tests/EmperorCoreTests/Resources/parity/13-F/filing.json from the platform's own
// Filing Assembly code.
//
//   node scripts/generate-filing-fixtures.mjs <path-to-emperor-ai> [--check]
//
// `parseMark`, `compareMark`, `errorList` and `FORUM_OPTIONS` live inside
// `src/pages/FilingAssembly.jsx`, and `normalizeForum` in `lib/filing/checklist.js`, whose imports
// need the server's database. So each is cut out of its file by name, brace-matched, and
// evaluated on its own; a renamed declaration fails this script loudly. Nothing is retyped: the
// app's `FilingMarks`, `FilingForum` and `FilingAssemblyResult.errorList` are held to the answers.
// For filing from a conversation's draft, the page's `deriveCover` and its seed filter, and the
// register's `stripMentions`, are cut out the same way and held to `FilingChatScope`.
//
// `--check` writes nothing and exits 1 if the fixture differs.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const pageFile = platform && path.join(platform, 'src/pages/FilingAssembly.jsx')
const checklistFile = platform && path.join(platform, 'lib/filing/checklist.js')
if (!pageFile || !fs.existsSync(pageFile) || !fs.existsSync(checklistFile)) {
  console.error('usage: generate-filing-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/13-F/filing.json')

// Cuts the declaration of `name` — `const name = …` or `[export ]function name(…)` — from the
// first `{` or `[` that opens its body to the bracket that closes it. Quoted strings are skipped
// so a bracket inside one does not count.
function cut(source, name, file) {
  const decl = new RegExp(`(?:^|\\n)\\s*(?:export\\s+)?(?:const\\s+${name}\\s*=|function\\s+${name}\\s*\\()`)
  const m = decl.exec(source)
  if (!m) throw new Error(`could not find "${name}" in ${file}`)
  const start = m.index + (m[0].startsWith('\n') ? 1 : 0)
  let i = m.index + m[0].length
  // For an arrow function the body is after `=>`; for a function, after the parameter list.
  const arrow = source.indexOf('=>', i)
  const brace = source.indexOf('{', i)
  const bracket = source.indexOf('[', i)
  let open
  if (/const/.test(m[0]) && bracket !== -1 && (brace === -1 || bracket < brace) &&
      (arrow === -1 || bracket < arrow)) open = bracket
  else if (/const/.test(m[0])) open = source.indexOf('{', arrow)
  else open = brace
  const openChar = source[open]
  const closeChar = openChar === '{' ? '}' : ']'
  let depth = 0
  let quote = null
  for (i = open; i < source.length; i++) {
    const c = source[i]
    if (quote) {
      if (c === '\\') { i++; continue }
      if (c === quote) quote = null
      continue
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; continue }
    if (c === openChar) depth++
    else if (c === closeChar) {
      depth--
      if (depth === 0) return source.slice(start, i + 1).replace(/^\s*export\s+/, '')
    }
  }
  throw new Error(`unbalanced "${name}" in ${file}`)
}

const page = fs.readFileSync(pageFile, 'utf8')
const checklist = fs.readFileSync(checklistFile, 'utf8')
const lifted = [
  cut(page, 'FORUM_OPTIONS', 'FilingAssembly.jsx'),
  cut(page, 'parseMark', 'FilingAssembly.jsx'),
  cut(page, 'compareMark', 'FilingAssembly.jsx'),
  cut(page, 'errorList', 'FilingAssembly.jsx'),
  cut(checklist, 'normalizeForum', 'checklist.js'),
].join('\n')
const { FORUM_OPTIONS, parseMark, compareMark, errorList, normalizeForum } = new Function(
  `${lifted}\nreturn { FORUM_OPTIONS, parseMark, compareMark, errorList, normalizeForum }`)()

// The page's own order check (`orderMatchesMarks`), run on the page's own comparator.
const inMarkOrder = (marks) => {
  const sorted = [...marks].sort(compareMark)
  return marks.every((m, i) => m === sorted[i])
}

const parseInputs = ['P-1', 'p-12', 'R-3', 'A-10', 'P1', '', null, 'PX-2', 'P-01', 'Annexure',
  'P-1a', ' P-1', 'AB-3', 'R-0', 'P--1', 'P-1-2']
const parse = parseInputs.map((input) => {
  const [side, number] = parseMark(input)
  return { input, side, number }
})

const comparePairs = [['P-1', 'P-2'], ['P-2', 'P-1'], ['P-10', 'P-2'], ['R-1', 'P-5'],
  ['P-5', 'R-1'], ['P-3', 'P-3'], ['p-1', 'P-1'], ['X', 'P-1'], ['P-1', 'X'], ['A-1', 'a-2'],
  ['Annexure', 'Annexure'], ['P-01', 'P-1'], ['', 'P-1']]
const compare = comparePairs.map(([a, b]) => ({ a, b, sign: Math.sign(compareMark(a, b)) }))

const sortInputs = [['P-1', 'P-2', 'P-3'], ['P-2', 'P-1'], ['P-10', 'P-9', 'P-1'],
  ['R-2', 'P-1', 'R-1', 'P-2'], ['P-1', 'p-1', 'P-1'], ['p-1', 'P-1'], ['X-1', 'Annexure', 'P-2'],
  ['P-1', 'R-1', 'P-2'], ['P-3', 'P-01', 'P-2'], [], ['P-1']]
const sort = sortInputs.map((input) => ({
  input, sorted: [...input].sort(compareMark), inOrder: inMarkOrder(input),
}))

const forumInputs = [...FORUM_OPTIONS, 'nclt', 'NCLAT', ' hc ', 'SC', 'sc ', 'Hc', 's.c.',
  'National Company Law Tribunal', 'National Company Law Tribunal, Mumbai Bench',
  'National Company Law Tribunal Mumbai', 'National Company Law Appellate Tribunal',
  'High Court of Delhi', 'IN THE HIGH COURT OF JUDICATURE AT BOMBAY', 'Supreme Court of India',
  'supreme', 'Debts Recovery Appellate Tribunal', 'Company Law Tribunal ', '', '   ', null, 'DRT']
const forums = forumInputs.map((input) => ({ input, normalized: normalizeForum(input) }))

const results = [
  { success: false, errors: ['cover.forum is required'], warnings: [] },
  { success: false, errors: ['P-1: source file missing', 'P-2: append treatment needs a PDF source'] },
  { success: false, error: 'internal error: boom' },
  { success: false, errors: null, error: 'nothing to assemble' },
  { success: false },
  { success: false, errors: [] },
  { success: false, errors: ['a', { message: 'b' }, { error: 'c' }, { code: 'X' }, ''] },
  { success: false, errors: [{ message: '' }, { code: 'E1', detail: 'd' }, null, false, 5] },
  { success: false, error: { message: 'object error' } },
  { success: false, errors: 'single string' },
  { success: false, errors: [{ message: 'path a/b' }, { mark: 'P-1', reason: 'missing' }] },
]
const errorLists = results.map((input) => ({ input, output: errorList(input) }))

// ── Filing from a conversation's draft ─────────────────────────────────────────────────────
// `deriveCover` is a top-level function of the page; it holds regular expressions with quotes in
// them, so it is cut from its declaration to the first closing brace at the start of a line
// rather than bracket-matched. The seed filter lives inside the component as two `useMemo`
// statements; they are cut whole and run as a function of `(attachedFiles, annexures)` with a
// `useMemo` that just calls its function. `MENTION_RE` and `stripMentions` come from
// `lib/filing/registry.js`.
const registryFile = path.join(platform, 'lib/filing/registry.js')

function cutToClosingLine(source, start, file, what) {
  const at = source.indexOf(start)
  if (at === -1) throw new Error(`could not find "${what}" in ${file}`)
  const end = source.indexOf('\n}\n', at)
  if (end === -1) throw new Error(`unterminated "${what}" in ${file}`)
  return source.slice(at, end + 2).replace(/^export\s+/, '')
}

function cutLine(source, start, file) {
  const at = source.indexOf(start)
  if (at === -1) throw new Error(`could not find "${start}" in ${file}`)
  const end = source.indexOf('\n', at)
  return source.slice(at, end).replace(/^export\s+/, '')
}

// `const name = useMemo(…)`, the parentheses matched with quoted text skipped.
function cutMemo(source, name, file) {
  const start = source.indexOf(`const ${name} = useMemo(`)
  if (start === -1) throw new Error(`could not find "${name}" in ${file}`)
  let i = source.indexOf('(', start)
  let depth = 0
  let quote = null
  for (; i < source.length; i++) {
    const c = source[i]
    if (quote) {
      if (c === '\\') { i++; continue }
      if (c === quote) quote = null
      continue
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; continue }
    if (c === '(') depth++
    else if (c === ')') {
      depth--
      if (depth === 0) return source.slice(start, i + 1)
    }
  }
  throw new Error(`unbalanced "${name}" in ${file}`)
}

const registry = fs.readFileSync(registryFile, 'utf8')

const deriveCover = new Function(
  `${cutToClosingLine(page, 'function deriveCover(', 'FilingAssembly.jsx', 'deriveCover')}\nreturn deriveCover`)()
const seedFilter = new Function('attachedFiles', 'annexures', [
  'const useMemo = (fn) => fn()',
  cutLine(page, 'const baseName =', 'FilingAssembly.jsx'),
  cutMemo(page, 'annexPaths', 'FilingAssembly.jsx'),
  cutMemo(page, 'seedFiles', 'FilingAssembly.jsx'),
  'return seedFiles',
].join('\n'))
const stripMentions = new Function([
  cutLine(registry, 'export const MENTION_RE', 'registry.js'),
  cutToClosingLine(registry, 'export function stripMentions(', 'registry.js', 'stripMentions'),
  'return stripMentions',
].join('\n'))()
const causeTitles = [
  '<p style="text-align:center"><strong>IN THE NATIONAL COMPANY LAW TRIBUNAL</strong></p><p>MUMBAI BENCH</p><p>C.P. (IB) No. 123 of 2026</p><p>IN THE MATTER OF:</p><p>ABC Steel Pvt. Ltd. …Petitioner</p><p>versus</p><p>XYZ Traders Ltd. …Respondent</p>',
  '<h2>BEFORE THE NATIONAL COMPANY LAW APPELLATE TRIBUNAL, NEW DELHI</h2><p>IN THE NATIONAL COMPANY LAW APPELLATE TRIBUNAL</p><p>Company Appeal (AT) (Insolvency) No. 45 of 2025</p><p>Rajesh Kumar vs. State Bank of India</p>',
  '<p>IN THE HIGH COURT OF DELHI AT NEW DELHI</p><p>W.P.(C) 1234/2024</p><p>Anil Kumar Goel v. Union of India</p>',
  '<p>IN THE HIGH COURT OF DELHI AT NEW DELHI</p><p>W.P.(C) No. 1234/2024</p><p>Anil Kumar Goel v. Union of India</p>',
  '<p>IN THE SUPREME COURT OF INDIA</p><p>CIVIL APPELLATE JURISDICTION</p><p>SLP (C) No. 9876 of 2025</p><p>Union of India versus M/s Popular Construction Co.</p>',
  '<p>IN THE Data Protection Board of India</p><p>Complaint No. 12 of 2026</p><p>Priya Sharma versus Acme Fintech Pvt. Ltd.</p>',
  '<p>in the high court of judicature at bombay</p><p>Writ Petition No. 55 of 2023</p>',
  '<p>IN THE DEBTS RECOVERY TRIBUNAL-I, CHENNAI</p><p>O.A. No. 77 of 2022</p><p>Canara Bank v. Ravi Enterprises</p>',
  '<p>IN THE COURT OF THE DISTRICT JUDGE, SAKET</p><p>CS No. 301/2021</p><p>Mehta &amp; Sons versus Kapoor Textiles</p>',
  '<p>IN THE STATE CONSUMER DISPUTES REDRESSAL COMMISSION</p><p>Consumer Complaint No. 14 of 2024</p><p>Ramesh Gupta Vs Builder Ltd</p>',
  '<p>IN THE NATIONAL COMPANY LAW TRIBUNAL, NEW DELHI BENCH</p><p>I.A. No. 3 of 2026 in C.P. (IB) No. 123 of 2026</p>',
  '<div>IN&nbsp;THE&nbsp;HIGH&nbsp;COURT&nbsp;OF&nbsp;KARNATAKA</div><div>Criminal Petition No. 5512 of 2025</div><div>State of Karnataka &lt;Complainant&gt; versus Suresh</div>',
  '<p>MEMORANDUM OF APPEAL</p><p>Appeal No. XII of 2019</p><p>Before the Appellate Authority</p>',
  '<p>IN THE ARBITRAL TRIBUNAL</p><p>Application No. : 4 / 2026</p>',
  '<p>Synopsis and list of dates for the petitioner.</p>',
  '',
  '<p>IN THE HIGH COURT OF PUNJAB AND HARYANA AT CHANDIGARH</p><p>CWP-1234-2024</p><p>Harjit Singh   versus   State of Punjab and others</p>',
  '<p>IN THE COMPANY LAW TRIBUNAL</p><p>Petition No. 9 of 2020</p>',
  '<p>IN THE SECURITIES APPELLATE TRIBUNAL, MUMBAI</p><p>Appeal No. 201 of 2025</p><p>Karvy Ltd. v. SEBI</p>',
  '<p>IN THE SUPREME COURT OF INDIA</p><p>' + 'Lorem ipsum dolor sit amet. '.repeat(100) + '</p><p>Civil Appeal No. 1 of 2026</p>',
]
const covers = causeTitles.map((html) => ({ html, cover: deriveCover(html) }))

const seedCases = [
  { attachedFiles: [{ name: 'Plaint.pdf', folderName: 'Bakshi' }, { name: 'Reply.pdf', folderName: 'Bakshi' }],
    annexures: [{ source_file_path: '/storage/1/Bakshi/Plaint.pdf' }] },
  { attachedFiles: [{ name: 'EVIDENCE_LIST.pdf', folderName: 'Vijay Kumar Goel' }, { name: 'EVIDENCE_LIST.pdf', folderName: 'Anil Kumar Goel' }],
    annexures: [{ source_file_path: '/storage/1/Vijay Kumar Goel/EVIDENCE_LIST.pdf' }] },
  { attachedFiles: [{ name: 'Order.pdf' }, { name: 'Notice.pdf', folderName: '' }],
    annexures: [{ source_file_path: '/storage/1/Some Folder/Order.pdf' }] },
  { attachedFiles: [{ name: 'Order.pdf', folderName: 'Orders/2026' }],
    annexures: [{ source_file_path: 'Orders/2026/Order.pdf' }] },
  { attachedFiles: [{ name: 'Order.pdf', folderName: 'Orders' }],
    annexures: [{ source_file_path: '/storage/1/OldOrders/Order.pdf' }] },
  { attachedFiles: [{ name: '', folderName: 'X' }, { name: 'A.pdf', folderName: 'X' }], annexures: [] },
  { attachedFiles: [], annexures: [{ source_file_path: '/a/b.pdf' }] },
  { attachedFiles: [{ name: 'Plaint.pdf', folderName: 'Bakshi' }], annexures: [{ source_file_path: null }] },
]
const seeds = seedCases.map((c) => ({ ...c, seed: seedFilter(c.attachedFiles, c.annexures) }))

const mentionInputs = [
  'Annexure P-2: True copy of the order <@Final_Appeal.pdf:P-2:41-45> is filed.',
  'See <@Board Resolution.pdf:P-1> and <@Notice.pdf:R-3:7>.',
  'No mention here.',
  '<@bad:P2> stays, <@x.pdf:P-1:> stays, <@:P-1> stays',
  '<@a.pdf:AB-12:1-2><@b.pdf:p-3>',
  '',
]
const mentions = mentionInputs.map((input) => ({ input, output: stripMentions(input) }))

const fixture = {
  forumOptions: FORUM_OPTIONS,
  marks: { parse, compare, sort },
  forums,
  errorLists,
  covers,
  seeds,
  mentions,
}
const text = JSON.stringify(fixture, null, 1) + '\n'
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
const summary = `${parse.length} marks, ${compare.length} pairs, ${sort.length} orders, ${forums.length} forums, ${errorLists.length} error lists, ${covers.length} covers, ${seeds.length} seeds, ${mentions.length} mentions`
if (before === text) { console.log(`${summary}, unchanged`); process.exit(0) }
if (checkOnly) { console.log('filing.json differs from the platform'); process.exit(1) }
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text)
console.log(`${summary} written`)
