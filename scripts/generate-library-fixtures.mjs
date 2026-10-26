#!/usr/bin/env node
// Regenerates Tests/EmperorCoreTests/Resources/parity/library/display.json from the platform's own
// Library helpers.
//
//   node scripts/generate-library-fixtures.mjs <path-to-emperor-ai> [--check]
//
// The Library's words — a tidied title, what a cover prints, the facts under a card, a case name,
// an Act's title, kicker and counts, a series name, a decade shelf, a citation line, the plain-text
// fallback's paragraphs and the find-in-judgment count — are the web's to decide. They live in
// `src/components/library/coverTheme.js`, `caselaw/courts.js`, `caselaw/readerModel.js`,
// `acts/actText.js`, `books/bookFormat.js` and `src/lib/judgmentDoc.js`. Those modules are imported
// for real, under Node, and run over the sample rows below; `LibraryDisplay` is held to the result.
//
// `lucide-react` resolves to a stand-in exporting each icon name as a string (the pattern of
// `generate-tile-fixtures.mjs`), and `@/` and extension-less relative imports resolve to files.
//
// `--check` writes nothing and exits 1 if the fixture differs.

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const lib = platform && path.join(platform, 'src/components/library')
if (!lib || !fs.existsSync(path.join(lib, 'coverTheme.js'))) {
  console.error('usage: generate-library-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const src = path.resolve(platform, 'src')
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/library/display.json')

const iconNames = new Set()
for (const file of walk(lib)) {
  const text = fs.readFileSync(file, 'utf8')
  for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*['"]lucide-react['"]/g)) {
    for (const part of m[1].split(',')) {
      const name = part.trim().split(/\s+as\s+/)[0].trim()
      if (/^[A-Za-z_$][\w$]*$/.test(name)) iconNames.add(name)
    }
  }
}
const lucideStub = [...iconNames].map(n => `export const ${n} = '${n}';`).join('\n')

registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'lucide-react') return { url: 'emperor-stub:lucide', shortCircuit: true }
    let target = null
    if (specifier.startsWith('@/')) target = path.join(src, specifier.slice(2))
    else if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      target = path.resolve(path.dirname(fileURLToPath(context.parentURL)), specifier)
    }
    if (target) {
      for (const candidate of [target, `${target}.js`, path.join(target, 'index.js')]) {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
          return { url: pathToFileURL(candidate).href, shortCircuit: true }
        }
      }
    }
    return next(specifier, context)
  },
  load(url, context, next) {
    if (url === 'emperor-stub:lucide') return { format: 'module', source: lucideStub, shortCircuit: true }
    if (url.startsWith('file:') && url.startsWith(pathToFileURL(src).href)) {
      return { format: 'module', source: fs.readFileSync(fileURLToPath(url), 'utf8'), shortCircuit: true }
    }
    return next(url, context)
  },
})

const mod = (p) => import(pathToFileURL(path.join(src, p)).href)
const cover = await mod('components/library/coverTheme.js')
const courts = await mod('components/library/caselaw/courts.js')
const acts = await mod('components/library/acts/actText.js')
const books = await mod('components/library/books/bookFormat.js')
const reader = await mod('components/library/caselaw/readerModel.js')
const judgmentDoc = await mod('lib/judgmentDoc.js')

// ── Sample rows: scraped junk, shouting titles, display titles, case parties, Acts ──
const docs = [
  { id: 1, category: 'bare-acts', title: 'INDIAN BARE ACTS Indian Evidence Act,1872 (Single Document)', year: 1872, jurisdiction: 'Central', docType: 'act' },
  { id: 2, category: 'bare-acts', title: 'THE INDIAN PENAL CODE, 1860', year: 1860, jurisdiction: 'Central', docType: 'act', aliases: ['IPC'] },
  { id: 3, category: 'bare-acts', title: 'CHHATTISGARH APPROPRIATION (No. 2) ACT, 2006', year: 2006, jurisdiction: 'Chhattisgarh' },
  { id: 4, category: 'bare-acts', title: 'Bengal Regulation (Rep., Act 12 of 1951)', year: 1818, jurisdiction: 'West Bengal' },
  { id: 5, category: 'bare-acts', title: 'motor vehicles act, 1988', year: 1988, jurisdiction: 'Central', hasChildren: 14 },
  { id: 6, category: 'bare-acts', title: 'Consumer Protection Act, 1986 No 68 of 1986', jurisdiction: 'none', docType: 'act' },
  { id: 7, category: 'bare-acts', title: 'The Assam Rules 1960', docType: 'rules', jurisdiction: 'Assam', year: 1960 },
  { id: 8, category: 'bare-acts', title: 'Constitution Of India', jurisdiction: 'Central', kind: 'act' },
  { id: 9, category: 'bare-acts', title: 'Bharatiya Nyaya Sanhita, 2023', year: 2023, jurisdiction: 'Central', repealed: true },
  { id: 10, category: 'bare-acts', title: 'Amending Acts', kind: 'amendments', jurisdiction: 'Jammu and Kashmir' },
  { id: 11, category: 'bare-acts', title: 'Some Act omitted by Act 5 of 2001', jurisdiction: 'Central', year: 1950 },
  { id: 12, category: 'bare-acts', title: 'The Code of Civil Procedure 1908', jurisdiction: 'Central', year: 1908 },
  { id: 20, category: 'case-law', title: 'Seethamma vs State Of Karnataka on 31 October, 2012', court: 'supremecourt', courtLabel: 'Supreme Court of India', decidedOn: '2012-10-31', year: 2012, neutralCitation: '2012 INSC 410' },
  { id: 21, category: 'case-law', title: 'x', petitioner: 'MS Anand Stores', respondent: 'STATE OF KARNATAKA', court: 'karnataka', courtLabel: 'Karnataka High Court', decidedOn: '2019-03-04', caseType: 'W.P.', caseNumber: '1234 of 2019' },
  { id: 22, category: 'case-law', title: 'VKasi v. SMKarthikeyan', court: 'chennai', year: 2001, caseType: 'Arising out of S.L.P. (C)', caseNumber: '4629 of 2008' },
  { id: 23, category: 'case-law', title: 'Kamalakar SO Keshav versus The State Of Maharashtra Through The', court: 'bombay', courtLabel: 'Bombay High Court', caseNumber: 'No. 77 of 2020' },
  { id: 24, category: 'case-law', title: 'DrPercy Mistry vs Union of India &', court: 'delhi', decidedOn: '2001-01-05', caseType: 'Pune Cyber Police Station Pune City with FIR No.', caseNumber: '12' },
  { id: 25, category: 'case-law', title: 'In Re: Some Reference', court: 'orissa', courtLabel: 'Orissa High Court', year: 1999 },
  { id: 26, category: 'case-law', title: 'A. K. Gopalan v. The State of Madras', court: 'scorders', courtLabel: 'Supreme Court of India', decidedOn: '1950-05-19' },
  { id: 30, category: 'books-and-law-reports', title: '# The **Laws** of _India_', series: 'THE LAWS OF ENGLAND', volume: '12', volumeNo: 12, year: 1987, fileSize: 6500000 },
  { id: 31, category: 'books-and-law-reports', title: 'View', series: 'Calcutta Law Journal', volume: 'Vol-02', year: 1904, fileSize: 120000000 },
  { id: 32, category: 'books-and-law-reports', title: 'PDF (6.19 MB)', year: 1950 },
  { id: 33, category: 'books-and-law-reports', title: '', reference: 'AIR 1950 SC 27' },
  { id: 34, category: 'books-and-law-reports', title: 'Calcutta Law Journal, Vol-01, Issue no.-615', series: 'Calcutta Law Journal', volume: '01', issue: '615', year: 1905, fileSize: 2048 },
  { id: 35, category: 'books-and-law-reports', title: 'Accessible_(PDF 1.47MB)', series: 'All India Reporter', volume: 'xxxiv', year: 1947 },
  { id: 36, category: 'books-and-law-reports', title: 'a3f9b2-1c2d-4e5f', year: 1960, dateFromTitle: '1960-04-02' },
  { id: 40, category: 'law-commission-reports', title: 'Accessible_(PDF 0.97MB)', displayTitle: 'Law Commission of India — Report No. 277 (2018)', reportNo: 277, year: 2018, subject: 'Wrongful Prosecution' },
  { id: 41, category: 'law-commission-reports', title: '', year: 2010 },
  { id: 42, category: 'regulator-orders', title: '( 4) Do PT, Rules for the conduct', publisher: 'SEBI', kind: 'adjudication', reference: 'WTM/AB/123', decidedOn: '2025-11-04', year: 2025 },
  { id: 43, category: 'regulator-orders', title: '"Master Circular on KYC', publisher: 'RBI', displayRef: 'RBI/DOR/2025-26/232', year: 2025, jurisdiction: 'Central' },
  { id: 44, category: 'tribunals', title: 'Bharti Airtel Ltd. vs. Union of India', publisher: 'TDSAT', decidedOn: '2024-07-15', courtLabel: 'TDSAT' },
  { id: 45, category: 'tribunals', title: 'Annual Report', publisher: 'NHRC', year: 2021 },
  { id: 46, category: 'professional-institutes', title: 'standards on auditing', publisher: 'ICAI', year: 2016 },
  { id: 47, category: 'parliament-prs', title: 'THE DIGITAL PERSONAL DATA PROTECTION BILL, 2023', kind: 'act', year: 2023, genericTitle: true },
  { id: 48, category: 'legal-aid-nalsa', title: 'NALSA (Legal Services to the Mentally Ill) Scheme, 2015', year: 2015 },
  { id: 49, category: 'unknown-category', title: '', year: 2000 },
  { id: 50, category: 'case-law', title: 'Text judgment', render: 'text', ext: '.txt' },
  { id: 51, category: 'case-law', title: 'Html judgment', render: 'html', ext: '.html' },
  { id: 52, category: 'books-and-law-reports', title: 'A pdf', render: 'pdf', ext: '.pdf', cover: 'none' },
]

const rows = docs.map((doc) => ({
  doc,
  tidyTitle: cover.tidyTitle(doc),
  isUntitled: cover.isUntitled(doc),
  coverFields: cover.coverFields(doc),
  docMeta: cover.docMeta(doc),
  isTextDoc: cover.isTextDoc(doc),
  caseTitleText: courts.caseTitleText(doc),
  caseNumberText: courts.caseNumberText(doc),
  court: doc.court ? (({ name, short, mono }) => ({ name, short, mono }))(courts.courtInfo(doc.court, doc.courtLabel)) : null,
  actTitle: acts.actTitle(doc),
  splitTitle: acts.splitTitle(doc),
  isRepealed: acts.isRepealed(doc),
  actKicker: acts.actKicker(doc),
  actTabLabel: acts.actTabLabel(doc, doc.kind === 'amendments' ? 'amendments' : 'act'),
  jurisdiction: acts.jurisdictionOf(doc),
  copySource: acts.copySource(doc),
  actCloth: acts.actCloth(doc),
  captionMeta: books.captionMeta(doc),
  captionMetaSized: books.captionMeta(doc, { withSeries: false, withSize: true }),
  referenceLine: books.referenceLine(doc),
  volumeTitle: books.volumeTitle(doc),
  volumeLabel: books.volumeLabel(doc),
  citationLine: reader.citationLine(doc, null),
}))

const parties = [
  'MS Anand Stores', 'MSHindustan Engineering', 'M/S Bharat Traders', 'DrPercy Mistry', 'MrMohana Rao',
  'Kamalakar SO Keshav', 'VKasi', 'SMKarthikeyan', 'PSundararama Iyer', 'STATE OF KARNATAKA',
  'State Of Karnataka', 'The State Of Maharashtra Through The', 'Union of India &', 'ABC Corporation and',
  'Ram Kumar vs.', '  spaced   name  ', '', 'UNION OF INDIA AND OTHERS', 'Smt Kamla Devi', 'X Y',
]

const caseNumbers = [
  { caseType: 'W.P.(MD)', caseNumber: '1234 of 2019' },
  { caseType: 'Civil Appeal', caseNumber: 'No. 7710 of 2012' },
  { caseType: 'Arising out of S.L.P. (C)', caseNumber: '4629 of 2008' },
  { caseType: 'Pune Cyber Police Station Pune City with FIR No.', caseNumber: '12' },
  { caseType: '', caseNumber: '55' },
  { caseType: 'Crl.A.', caseNumber: '' },
  { caseType: 'Appeal in', caseNumber: '3 of 1999' },
  {},
]

const days = ['1979-05-04', '2026-12-17', '2012-10-31T00:00:00Z', 'not a date', '', '2001-13-01']
const counts = [0, 7, 1000, 271480, 12345678, -4500, 3.5]

const tabCounts = [
  { rules: 9, amendments: 25, editions: 2, related: 1, act: 1 },
  { notifications: 1, rules: 1, regulations: 3 },
  { schemes: 2, orders: 1000 },
  {},
]
const countPartCases = []
for (const t of tabCounts) {
  countPartCases.push({ tabCounts: t, first: null, withEditions: false, parts: acts.countParts(t) })
  countPartCases.push({ tabCounts: t, first: 'amendments', withEditions: true, parts: acts.countParts(t, { first: 'amendments', withEditions: true }) })
}

const sizes = [0, 500, 1024, 900 * 1024, 1024 * 1024, 5.5 * 1024 * 1024, 12 * 1024 * 1024, 150 * 1024 * 1024, 2.5 * 1024 ** 3]
const sizeCases = sizes.map((n) => ({ bytes: n, act: acts.fmtSize(n), book: books.fmtSize(n) }))

const seriesNames = ['THE LAWS OF ENGLAND', 'All India Reporter', 'SCC', 'MADRAS LAW JOURNAL', 'INDIAN LAW REPORTS OF THE ALLAHABAD SERIES']
const seriesCases = seriesNames.map((name) => ({ name, text: books.seriesName(name) }))

const decadeDocs = [
  { id: 1, year: 1805, volume: '1' }, { id: 2, year: 1812, volume: '2' }, { id: 3, year: 1819, volume: '3' },
  { id: 4, year: 1951, volume: '4' }, { id: 5, year: 1952, volume: '5' }, { id: 6, year: 1953, volume: '6' },
  { id: 7, year: 1954, volume: '7' }, { id: 8, year: 1955, volume: '8' }, { id: 9, year: 1961, volume: '9' },
  { id: 10, volume: '10' }, { id: 11, year: 1962, volume: '11' }, { id: 12, year: 1963, volume: 'xii' },
]
const decades = books.groupByDecade(decadeDocs).map((g) => ({ key: g.key, label: g.label, ids: g.items.map((d) => d.id) }))

const latestCases = [
  [{ id: 1, year: 2001 }, { id: 2, year: 2019 }, { id: 3, year: 2005 }],
  [{ id: 1, year: 2019 }, { id: 2, year: 2019 }],
  [{ id: 1, year: 2019 }],
  [{ id: 1 }, { id: 2 }],
].map((list) => ({ docs: list, latest: null }))
// `latestId` lives in act/actFiles.js, which imports React hooks; its rule is lifted by declaration.
const actFiles = fs.readFileSync(path.join(lib, 'act/actFiles.js'), 'utf8')
const latestSource = actFiles.match(/export function latestId\(docs\) \{[\s\S]*?\n\}/)
if (!latestSource) { console.error('latestId not found in act/actFiles.js'); process.exit(1) }
const latestId = new Function(`${latestSource[0].replace('export ', '')}\nreturn latestId`)()
for (const c of latestCases) c.latest = latestId(c.docs)

const judgmentText = `Title: Seethamma vs State
Court: Supreme Court
==========
[Cites 3 , Cited by 12]

IN THE SUPREME COURT OF INDIA
CIVIL APPELLATE JURISDICTION

1. This appeal is by the
plaintiff against the court's order.

2. The court below held that the
Court   had no jurisdiction.

2. A second opinion restarts at two.

10. Held: the appeal is allowed by the Court.
`
const parsed = judgmentDoc.parseJudgmentText(judgmentText)
const plainBlocks = reader.blocksFromPlain(parsed.paragraphs)
const findCases = ['court', 'Court', 'c', 'the appeal', '"held"', 'nothing here', ' court '].map((q) => {
  const r = reader.computeHits(plainBlocks, q)
  return { query: q, hits: r.hits.map((h) => [h.block, h.start, h.end]) }
})
const paraCases = ['2', '3', '10', '11', 'x', ''].map((n) => ({ n, index: reader.findPara(plainBlocks, n) }))

const themes = Object.fromEntries([...cover.CATEGORY_ORDER, 'nope'].map((k) => {
  const t = cover.categoryTheme(k)
  return [k, { label: t.label, cap: t.cap, untitled: t.untitled, blurb: t.blurb, cloth: t.cloth }]
}))

const hashes = ['', '1', 2478, 'calcutta law journal', 'Assam', 'Jammu and Kashmir'].map((v) => ({ value: v, hash: cover.hashOf(v) }))

const fixture = {
  order: cover.CATEGORY_ORDER,
  coverInk: cover.COVER_INK,
  themes,
  hashes,
  rows,
  parties: parties.map((p) => ({ name: p, text: courts.tidyParty(p) })),
  caseNumbers: caseNumbers.map((h) => ({ header: h, text: courts.caseNumberText(h) })),
  days: days.map((d) => ({ iso: d, text: cover.fmtDay(d) })),
  counts: counts.map((n) => ({ n, text: cover.fmtCount(n) })),
  countParts: countPartCases,
  sizes: sizeCases,
  series: seriesCases,
  decades: { docs: decadeDocs, groups: decades },
  latest: latestCases,
  plain: { text: judgmentText, paragraphs: parsed.paragraphs, blocks: plainBlocks, find: findCases, paras: paraCases },
  hasFilters: acts.HAS_FILTERS,
  tabOrder: acts.TAB_ORDER,
  courtOrder: courts.COURT_ORDER,
}

const text = JSON.stringify(fixture, null, 1) + '\n'
const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
if (before === text) { console.log(`display.json is current — ${rows.length} rows`); process.exit(0) }
if (checkOnly) { console.log('display.json differs from the platform'); process.exit(1) }
fs.mkdirSync(path.dirname(out), { recursive: true })
fs.writeFileSync(out, text)
console.log(`display.json written — ${rows.length} rows`)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else if (/\.(js|jsx)$/.test(entry.name)) yield p
  }
}
