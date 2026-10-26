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

const fixture = {
  forumOptions: FORUM_OPTIONS,
  marks: { parse, compare, sort },
  forums,
  errorLists,
}
const text = JSON.stringify(fixture, null, 1) + '\n'
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
const summary = `${parse.length} marks, ${compare.length} pairs, ${sort.length} orders, ${forums.length} forums, ${errorLists.length} error lists`
if (before === text) { console.log(`${summary}, unchanged`); process.exit(0) }
if (checkOnly) { console.log('filing.json differs from the platform'); process.exit(1) }
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text)
console.log(`${summary} written`)
