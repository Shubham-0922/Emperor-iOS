#!/usr/bin/env node
// Regenerates Tests/EmperorCoreTests/Resources/parity/p7/cited-source.json from the platform's own
// cited-source module.
//
//   node scripts/generate-cited-source-fixtures.mjs <path-to-emperor-ai> [--check]
//
// `src/lib/citedSource.js` imports nothing, so it is run as it is, under Node, over the cases below
// (its own self-test's cases in `src/lib/citations.selftest.mjs` among them). `CitedSourceGoldenTests`
// holds `CitedSource` to every answer it gives: parsing a reference line, listing an answer's cited
// documents, normalising characters, finding a quote among a page's words, and the line rectangles
// a found quote is drawn as. Nothing here is retyped from the module; regenerate on a platform
// change, never edit the fixture.
//
// `--check` writes nothing and exits 1 if the fixture would change.

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const moduleFile = platform && path.join(platform, 'src/lib/citedSource.js')
if (!moduleFile || !fs.existsSync(moduleFile)) {
  console.error('usage: generate-cited-source-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const src = path.resolve(platform, 'src')
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/p7/cited-source.json')

// The platform's package.json may not declare "type": "module"; its sources are ESM regardless.
registerHooks({
  load(url, context, next) {
    if (url.startsWith('file:') && url.startsWith(pathToFileURL(src).href)) {
      return { format: 'module', source: fs.readFileSync(fileURLToPath(url), 'utf8'), shortCircuit: true }
    }
    return next(url, context)
  },
})

const { parseDocumentReference, citedDocs, normChars, findQuoteRange, lineRects } =
  await import(pathToFileURL(moduleFile).href)

// ── Reference lines ──────────────────────────────────────────────────────────────────────────
const parseInputs = [
  'Lease_Agreement.pdf, p. 12 — "the lessee shall pay the monthly rent"',
  'Vishaka vs. State of Rajasthan, (1997) 6 SCC 241.',
  '**Order_dated_24.04.2026.pdf**, page 3',
  'Notes.pdf — "no page given here at all"',
  'Lease_Agreement.pdf, p. 2 — “the lessee shall pay the monthly rent on the fifth day”',
  "Deed.pdf, p. 4 — ‘the vendor hereby conveys the property’",
  "Deed.pdf, p. 4 — 'the vendor hereby conveys'",
  'Affidavit.pdf, pp. 4-5 — "deponent states on solemn affirmation"',
  'Affidavit.pdf, pg 7',
  'Affidavit.pdf, Page 12',
  'Affidavit.PDF, P. 9 — "short"',
  'Plaint.docx, p.3',
  'Photo_of_site.JPEG',
  'Scan.tiff, p 2 — "a scanned page with words"',
  'Ledger.txt',
  'p. 4 of the Order.pdf — "the order was passed"',
  'Order.pdf, app. 5',
  'Order.pdf (p.12)',
  '<b>Order.pdf</b>, <i>p. 6</i> — "the court directed the parties"',
  '`Exhibit_P-3.pdf`, p. 10',
  'आदेश_दिनांक.pdf, p. ३ — "न्यायालय ने आदेश दिया कि"',
  'आदेश_दिनांक.pdf, p. 3 — "न्यायालय ने आदेश दिया कि"',
  'Two.pdf and Three.pdf, p. 8',
  'Lease.pdfx, p. 1',
  'Lease_Agreement.pdf, p. 00012',
  'Lease_Agreement.pdf, p. 0',
  'Lease_Agreement.pdf, p. 123456',
  'No file named here, p. 3 — "just a quote somewhere"',
  '',
]
const parse = parseInputs.map((text) => ({ text, ref: parseDocumentReference(text) }))

// ── An answer's cited documents ──────────────────────────────────────────────────────────────
const docsInputs = [
  'Rent is due [1].\n\n[1] Lease_Agreement.pdf, p. 12 — "the lessee shall pay"',
  [
    'The lease [1] and the deed [2] agree [3].',
    '',
    '## References',
    '',
    '[1] Lease_Agreement.pdf, p. 2 — “the lessee shall pay the monthly rent on the fifth day”',
    '- [2]: Sale_Deed.pdf, page 4 — "the vendor hereby conveys"',
    '* [3] - Vishaka v. State of Rajasthan, (1997) 6 SCC 241',
    '1. [4] Lease Agreement.pdf, p. 2 — “the lessee shall pay the monthly rent on the fifth day”',
    '• [5] Lease_Agreement.pdf, p. 3 — "another passage entirely"',
    '[6]Lease_Agreement.pdf',
    '[7] Order.pdf, p. 1\r',
    '   [8]   Notes.txt',
    '[9]',
    'Text [10] Inline.pdf, p. 2',
  ].join('\n'),
  '',
]
const docs = docsInputs.map((content) => ({ content, docs: citedDocs(content) }))

// ── Character normalisation ──────────────────────────────────────────────────────────────────
const normInputs = [
  'अन्‍य १९५०', 'अन्य 1950', '“State Information, SIC”', 'ÅNGSTRÖM', 'İstanbul',
  'Ⅻ ½ ٣', 'don’t — stop!', 'tab\tand nbsp', 'emoji 😀 ok', '',
]
const norm = normInputs.map((text) => ({ text, norm: normChars(text) }))

// ── Finding a quote among positioned words ───────────────────────────────────────────────────
const sic = ['40.', 'The', 'State', 'Information', 'Commission', '(SIC)', 'is', 'an', 'autonomous', 'body,', 'that', 'is']
const hindi = ['16.', 'ऐसी', 'विधि', 'शब्दावली', 'की', 'कमी', 'थी', 'जो', 'इंग्लैंड', 'में', 'पनपी']
const lease = ('The lessee shall pay the monthly rent on or before the fifth day of every calendar month ' +
  'to the lessor at his registered office without any deduction whatsoever.').split(' ')
const joined = ['अन्‍य', 'विधि', '१९५०', 'में', 'पारित', 'हुई']
const findCases = [
  ['sic-exact', sic, 'State Information Commission (SIC) is an autonomous body'],
  ['sic-punctuation', sic, '“state information commission, SIC, is an autonomous body”'],
  ['sic-misspelt-middle', sic, 'The State Information Commision is an autonomous body'],
  ['sic-nothing', sic, 'nothing like this sentence appears anywhere'],
  ['hindi-exact', hindi, 'ऐसी विधि शब्दावली की कमी थी'],
  ['hindi-joiner-digits', joined, 'अन्य विधि 1950 में पारित'],
  ['lease-exact', lease, 'the monthly rent on or before the fifth day'],
  ['lease-head-and-tail', lease, 'the lessee shall pay the monthly rent on the fifth day of every calendar month'],
  ['lease-head-only', lease, 'The lessee shall pay the monthly rent in cash every single week of the year'],
  ['lease-tail-only', lease, 'a tenant must hand over money to the lessor at his registered office'],
  ['lease-densest-window', lease, 'deduction whatsoever calendar month lessor registered office rent'],
  ['lease-densest-too-thin', lease, 'rent payable quarterly through bank transfer only'],
  ['lease-short-quote', lease, 'pay rent'],
  ['lease-one-word', lease, 'lessor'],
  ['empty-quote', lease, ''],
  ['punctuation-quote', lease, '— … —'],
  ['no-words', [], 'the lessee shall pay'],
  ['blank-words', ['—', '…'], 'the lessee shall pay'],
]
const find = findCases.map(([id, words, quote]) => ({ id, words, quote, range: findQuoteRange(words, quote) }))

// ── One rectangle per line ───────────────────────────────────────────────────────────────────
const rectCases = [
  ['selftest-wrap', [[10, 10, 40, 20], [45, 10, 80, 20], [10, 30, 50, 40]], 0, 2],
  ['one-line', [[10, 10, 40, 20], [45, 11, 80, 21], [85, 10, 120, 20]], 0, 2],
  ['three-lines', [[300, 100, 340, 112], [345, 100, 400, 112], [72, 116, 120, 128], [125, 116, 180, 128], [72, 132, 99, 144]], 0, 4],
  ['two-columns', [[10, 10, 40, 20], [300, 10, 340, 20], [20, 10, 60, 20]], 0, 2],
  ['partial-range', [[10, 10, 40, 20], [45, 10, 80, 20], [10, 30, 50, 40], [55, 30, 90, 40]], 1, 2],
  ['past-the-end', [[10, 10, 40, 20], [45, 10, 80, 20]], 1, 4],
  ['jumping-back', [[100, 10, 140, 20], [80, 10, 95, 20], [10, 10, 40, 20]], 0, 2],
]
const rects = rectCases.map(([id, boxes, start, end]) => ({ id, boxes, start, end, rects: lineRects(boxes, start, end) }))

const fixture = { parse, docs, norm, find, rects }
const text = JSON.stringify(fixture, null, 1) + '\n'
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
const summary = `${parse.length} references, ${docs.length} answers, ${norm.length} normalisations, ${find.length} quotes, ${rects.length} rectangles`
if (before === text) { console.log(`${summary}, unchanged`); process.exit(0) }
if (checkOnly) { console.log('cited-source.json differs from the platform'); process.exit(1) }
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text)
console.log(`${summary} written`)
