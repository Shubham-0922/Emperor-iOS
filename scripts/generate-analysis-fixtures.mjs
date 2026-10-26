#!/usr/bin/env node
// Regenerates Tests/EmperorCoreTests/Resources/parity/analysis/*.json from the platform's own
// analysis pages: Devil's Advocate, Doc Index and List of Dates.
//
//   node scripts/generate-analysis-fixtures.mjs <path-to-emperor-ai> [--check]
//
// The shaping modules (`src/pages/analysis/samples/{devilsAdvocate,docIndex,listOfDates}.js`) are
// imported for real, under Node, with the same two stand-ins `generate-tool-fixtures.mjs` uses: a
// placeholder for each `lucide-react` icon and the `@/` alias. The history panel's date wording
// (`ago`, `fullDate`, `fileLine`, `runTitle`) and the report's `fmtMade` live in files that import
// React, so they are lifted by declaration instead. Inputs are the server's own sample results
// (`lib/analysis/fixtures/*.json`, also copied as `server-<tool>.json`), the pages' samples and a
// handful of deliberately messy answers. Nothing is retyped.
//
// `--check` writes nothing and exits 1 if any fixture differs.

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
const samples = platform && path.join(platform, 'src/pages/analysis/samples')
if (!samples || !fs.existsSync(path.join(samples, 'docIndex.js'))) {
  console.error('usage: generate-analysis-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
// The history wording reads the local zone; pinned so the fixture does not depend on the machine.
process.env.TZ = 'Asia/Kolkata'

const src = path.resolve(platform, 'src')
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../Tests/EmperorCoreTests/Resources/parity/analysis')

const iconNames = new Set()
for (const file of walk(path.join(src, 'pages/analysis'))) {
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
      for (const candidate of [target, `${target}.js`, `${target}.jsx`, path.join(target, 'index.js')]) {
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

const da = await import(pathToFileURL(path.join(samples, 'devilsAdvocate.js')).href)
const di = await import(pathToFileURL(path.join(samples, 'docIndex.js')).href)
const ld = await import(pathToFileURL(path.join(samples, 'listOfDates.js')).href)

const serverFixture = (tool) => JSON.parse(fs.readFileSync(path.join(platform, `lib/analysis/fixtures/${tool}.json`), 'utf8'))

// ── Lifting declarations out of files that import React ─────────────────────────────────────
const lift = (file, name) => {
  const text = fs.readFileSync(path.join(src, file), 'utf8')
  const fn = text.match(new RegExp(`^export function ${name}\\([^\\n]*\\n(?:[ \\t]+[^\\n]*\\n)*\\}\\n`, 'm'))
  if (fn) return fn[0].replace(/^export /, '')
  const m = text.match(new RegExp(`^const ${name} = [^\\n]*\\n`, 'm'))
  if (!m) throw new Error(`could not find ${name} in ${file}`)
  return m[0]
}
const historyHelpers = new Function([
  lift('pages/analysis/useAnalysisHistory.js', 'nbsp'),
  lift('pages/analysis/useAnalysisHistory.js', 'fullDate'),
  lift('pages/analysis/useAnalysisHistory.js', 'ago'),
  lift('pages/analysis/AnalysisHistory.jsx', 'fileLine'),
  lift('pages/analysis/AnalysisHistory.jsx', 'runTitle'),
  lift('pages/analysis/DevilsAdvocate.jsx', 'fmtMade'),
  'return { fullDate, ago, fileLine, runTitle, fmtMade }',
].join('\n'))()

// ── Devil's Advocate ─────────────────────────────────────────────────────────────────────────
const daInputs = [
  ['server', serverFixture('devils-advocate')],
  ['sample', da.SAMPLE_REPORT],
  ['string-ids-and-scales', {
    matter: { title: '  Arora v. Bansal ', forum: 'Delhi High Court', number: 7, client: null, date: '1 March 2026' },
    exposureScore: '61',
    oneMinute: 'Only one paragraph, as a string.',
    weakSpots: [
      { id: '#2', severity: 'High', category: 'Contract Terms', likelihood: 'high', impact: '4', title: 'Clause 9 is ambiguous', why: 'It can be read both ways.', where: 'Agreement cl. 9', say: 'The clause favours us.', fix: 'Plead the contra proferentem rule.' },
      { id: '3', severity: 'LOW', category: 'natural_justice', likelihood: 'very high', impact: 'medium-low', title: 'No hearing was given' },
      { id: 4.6, severity: 'medium', category: 'evidence', likelihood: 2.5, impact: 0, title: '' },
      { id: 'x', severity: 'catastrophic', category: '', likelihood: '', impact: true, title: 'Odd one' },
    ],
    questions: [
      { q: 'Why was the notice late?', why: 'Delay.', answer: 'Covid order.', readiness: 'Strong', spot: '#2' },
      { q: 'Where is the original?', readiness: 'missing', spot: 3 },
      { q: 'Who signed?', readiness: 'unknown', spot: '5' },
      { q: '   ', readiness: 'ready' },
      'not an object',
    ],
    docGaps: [{ doc: 'Board resolution', who: 'CS', how: 'Ask', when: 'Now', spot: '#3' }, { doc: '', who: 'x' }],
    authorities: [
      { name: 'A v. B', court: 'Supreme Court', year: 2019, holds: 'Something', distinguish: 'Facts differ', against: 2, verify: 'true', pinCite: 'para 12' },
      { name: 'C v. D', against: 99, verify: 1 },
      { name: '' },
    ],
    checklist: [{ text: 'Get the original', done: 'yes' }, { id: 'c1', text: 'File the reply', done: true }, { id: 'c1', text: 'Serve the other side' }, { text: '' }, { id: 7, text: 'Number id' }],
  }],
  ['duplicate-ids-and-refs', {
    weakSpots: [
      { id: 1, severity: 'minor', category: 'pleadings', likelihood: 1, impact: 1, title: 'First one' },
      { id: 1, severity: 'serious', category: 'pleadings', likelihood: 5, impact: 5, title: 'Second, same id' },
      { id: 2, severity: 'moderate', category: 'procedure', likelihood: 3, impact: 4, title: 'Third' },
      { severity: 'serious', category: 'Limitation', likelihood: 4, impact: 4, title: 'No id' },
    ],
    questions: [{ q: 'Q1', spot: 1 }, { q: 'Q2', spot: 2 }, { q: 'Q3', spot: '#9' }, { q: 'Q4', spot: 0 }],
    docGaps: [{ doc: 'D1', spot: '1' }],
    authorities: [{ name: 'X', against: 2, verify: false }],
    checklist: [],
  }],
  ['unknown-categories-derived-exposure', {
    weakSpots: [
      { id: 1, severity: 'serious', category: 'natural_justice', likelihood: 4, impact: 5, title: 'A' },
      { id: 2, severity: 'moderate', category: 'naïve-claim', likelihood: 2, impact: 3, title: 'B' },
      { id: 3, severity: 'minor', category: 'x', likelihood: 1, impact: 2, title: 'C' },
      { id: 4, severity: 'serious', category: 'natural justice', likelihood: 5, impact: 1, title: 'D' },
      { id: 5, severity: 'minor', category: 'Relief', likelihood: 3, impact: 3, title: 'E' },
    ],
  }],
  ['out-of-range', { exposureScore: 140.5, weakSpots: [{ id: 1, likelihood: 0, impact: 7.6, title: 'Clamped' }, { id: 2, likelihood: -3, impact: 4.5, title: 'Half' }] }],
  ['negative-score', { exposureScore: -3, weakSpots: [] }],
  ['empty-object', {}],
  ['not-an-object', 'nope'],
  ['an-array', []],
  ['null', null],
]
const daCases = daInputs.map(([id, input]) => {
  const normalised = da.normaliseReport(input)
  return {
    id, input: input === undefined ? null : input, normalised,
    derived: normalised && {
      countBySeverity: da.countBySeverity(normalised.weakSpots),
      exposureBand: da.exposureBand(normalised.exposureScore),
      categoryRows: da.categoryRows(normalised.weakSpots).map(r => ({ ...r })),
      matrixCells: da.matrixCells(normalised.weakSpots).filter(c => c.spots.length)
        .map(c => ({ likelihood: c.likelihood, impact: c.impact, score: c.score, spots: c.spots.map(s => s.id) })),
      readinessCounts: da.readinessCounts(normalised.questions),
    },
  }
})
const daGolden = {
  cases: daCases,
  exposureBands: [0, 33, 34, 66, 67, 100].map(score => ({ score, band: da.exposureBand(score) })),
  categoryLabels: ['limitation', 'contract', 'relief', 'natural-justice', 'naïve-claim', 'other', 'x', 'a--b__c', '3'].map(key => ({ key, label: da.categoryLabel(key) })),
  severities: ['serious', 'High', ' critical ', 'medium', 'low', 'trivial', 'odd', 3, null].map(v => ({ v, out: da.normaliseSeverity(v) })),
  readiness: ['ready', 'Needs Work', 'partial', 'missing', 'none', 'odd', null].map(v => ({ v, out: da.normaliseReadiness(v) })),
  scales: [1, 5, 0, 6, 2.5, 3.49, '4', ' 2 ', '', 'High', 'very low', 'medium-high', 'critical', 'odd', true, null, '1e0'].map(v => ({ v, out: da.normaliseScale(v) })),
  madeOn: ['2026-10-27T09:34:00.000Z', '2026-01-01T00:00:00.000Z', '2026-09-20T20:00:00.000Z'].map(iso => ({ iso, text: historyHelpers.fmtMade(iso) })),
}

// ── Doc Index ────────────────────────────────────────────────────────────────────────────────
const diInputs = [
  ['server', serverFixture('doc-index')],
  ['pleadings', di.DOC_INDEX_SCHEMAS.pleadings],
  ['dataroom', di.DOC_INDEX_SCHEMAS.dataroom],
  ['messy-numbers', {
    columns: [
      { key: 'n', label: 'No.', type: 'number' },
      { key: 'name', label: 'Paper', type: 'text', width: '300' },
      { key: 'amt', label: 'Amount', type: 'amount', width: 9000 },
      { key: 'pp', label: 'Pages', type: 'pages', width: 10 },
      { key: 'kind', label: 'Kind', type: 'badge', order: ['Low', 'High'] },
    ],
    rows: [
      { n: '3', name: 'Rent deed', amt: '4,82,000', pp: '12', kind: 'High' },
      { n: 1, name: '  ', amt: '₹ 1,200.50', pp: 1, kind: 'Low' },
      { n: true, name: 'Notice', amt: 'Rs. 500', pp: null, kind: 'Medium' },
      { n: '', name: 'item 10', amt: 'INR 10', pp: 0, kind: null },
      { n: 2, name: 'item 9', amt: 'abc', pp: '7 pages', kind: 'high' },
      { n: [5], name: 'Émile’s note', amt: '₹', pp: [3], kind: 'Low' },
      { n: -1, name: 'a', amt: -1234567.5, pp: 2, kind: 'Low' },
    ],
  }],
  ['messy-columns', {
    id: 'mine', label: 'Mixed bag', rationale: 42, filterLabel: 'Status',
    columns: [
      null,
      'not a column',
      { key: 'title', label: 'Title', type: 'mystery', description: 'What it is', width: null },
      { key: 'title', label: 'Dup', type: 'text' },
      { label: '  ', type: 'date' },
      { key: 'status', label: ['Sta', 'tus', null, { a: 1 }], type: 'badge', tones: { Open: 'ok', Closed: 'danger' } },
      { key: 'tags', label: 'Tags', type: 'tags', total: 1 },
      { key: 'risks', label: 'Risk notes', type: 'long' },
      { key: 'link', label: 'Where', type: 'link', pin: 1 },
    ],
    rows: [
      { title: 'Lease', col4: '2024-02-03', status: 'Open', tags: 'a; b, c,1,2\nd', risks: 'Unsigned page 4', link: '1.1/lease.pdf' },
      'junk',
      [1, 2],
      { title: 'Sale deed', col4: '2023-13-01', status: 'Closed', tags: ['x', 3, null, '  ', 'y'], risks: '', link: null },
      { title: '=SUM(A1)', col4: 'last week', status: 'Open', tags: [], risks: '"quoted"', link: '-x' },
      { title: 'Will', col4: null, status: 'Pending', tags: null, risks: null },
    ],
  }],
  ['badge-filter-chosen', {
    columns: [
      { key: 'a', label: 'A', type: 'badge' },
      { key: 'b', label: 'B', type: 'badge' },
      { key: 'c', label: 'C', type: 'badge' },
      { key: 'issue', label: 'Concern', type: 'text' },
    ],
    rows: [{ a: 'x', b: 'p', c: 'only', issue: 'gap' }, { a: 'y', b: 'q', c: 'only' }, { a: 'z', b: 'p', c: 'only', issue: '' }],
  }],
  ['flag-in', {
    flag: { key: 'risk', in: ['Red', 'Amber'], label: 'with a risk flag' },
    filterKey: 'nope',
    columns: [{ key: 'sr', label: 'Sr.', type: 'number' }, { key: 'doc', label: 'Doc', type: 'text', strong: true }, { key: 'risk', label: 'Risk', type: 'badge' }],
    rows: [{ sr: 1, doc: 'a', risk: 'Red' }, { sr: 2, doc: 'b', risk: 'Green' }, { sr: 3, doc: 'c', risk: 'Amber' }],
  }],
  ['no-text-column', { columns: [{ key: 'v', type: 'amount' }, { key: 'w', type: 'pages' }], rows: [{ v: 1, w: 2 }] }],
  ['no-columns', { columns: [], rows: [] }],
  ['rows-not-a-list', { columns: [{ key: 'a' }], rows: {} }],
  ['not-an-object', 'nope'],
  ['null', null],
]
const diCases = diInputs.map(([id, input]) => {
  const n = di.normalizeIndex(input)
  if (!n) return { id, input, normalised: null }
  const ids = (rows) => rows.map(r => r.__id)
  const sorts = {}
  for (const c of n.columns) {
    sorts[c.key] = {
      asc: ids([...n.rows].sort((a, b) => di.compareCells(c, a, b, 'asc'))),
      desc: ids([...n.rows].sort((a, b) => di.compareCells(c, a, b, 'desc'))),
    }
  }
  const filterCounts = []
  if (n.filterKey) {
    const m = new Map()
    n.rows.forEach(r => { const v = r[n.filterKey]; if (v != null) m.set(v, (m.get(v) || 0) + 1) })
    for (const [value, count] of m) filterCounts.push({ value, count })
  }
  const haystack = new Map(n.rows.map(r => [r, n.columns.map(c => di.cellText(c, r)).join('\n').toLowerCase()]))
  const search = ['notice', 'NOTICE ', '2024', '₹', 'zzz', ''].map(q => {
    const t = q.trim().toLowerCase()
    return { q, ids: ids(n.rows.filter(r => !t || haystack.get(r).includes(t))) }
  })
  const tones = []
  for (const c of n.columns.filter(c => c.type === 'badge')) {
    for (const r of n.rows) {
      const v = r[c.key]
      if (typeof v === 'string' && !tones.some(t => t.key === c.key && t.value === v)) {
        const given = c.tones?.[v]
        const low = v.toLowerCase()
        tones.push({ key: c.key, value: v, tone: given || (/^(high|critical|urgent)/.test(low) ? 'danger' : /^medium/.test(low) ? 'warn' : 'neutral') })
      }
    }
  }
  return {
    id, input,
    normalised: {
      id: n.id, label: n.label, filterKey: n.filterKey, filterLabel: n.filterLabel, flag: n.flag, pagesKey: n.pagesKey, rationale: n.rationale,
      columns: n.columns.map(c => ({
        key: c.key, label: c.label, type: c.type, width: c.width, description: c.description,
        pin: !!c.pin, strong: !!c.strong, total: c.total,
        tones: c.tones ? Object.fromEntries(Object.entries(c.tones).filter(([, v]) => typeof v === 'string')) : null,
        order: c.order ? c.order.map(o => (typeof o === 'string' ? o : null)) : null,
      })),
      rows: n.rows,
    },
    cellText: n.rows.map(r => n.columns.map(c => di.cellText(c, r))),
    sorts,
    csv: di.toCsv(n.columns, n.rows),
    flagged: n.flag ? n.rows.filter(r => di.isFlagged(n, r)).length : null,
    filterCounts,
    totals: n.columns.filter(c => c.total && ['number', 'amount', 'pages'].includes(c.type))
      .map(c => ({ key: c.key, sum: n.rows.reduce((s, r) => s + (r[c.key] || 0), 0) })),
    search,
    tones,
  }
})
const diGolden = {
  cases: diCases,
  fmtInr: [0, 5, 999, 1000, 48200000, 1480000000, 1234.5, 1234.49, -1234567.5, -12, null].map(n => ({ n, text: di.fmtInr(n) })),
  fmtDate: ['2024-02-03', '2024-13-01', '2024-00-10', '2024-02-45', '2024-02-03T10:00:00Z', 'last week', '24-02-03', '', null].map(iso => ({ iso, text: di.fmtDate(iso) })),
  fmtPages: [0, 1, 2, 2.5, null].map(n => ({ n, text: di.fmtPages(n) })),
}

// ── List of Dates ────────────────────────────────────────────────────────────────────────────
const ldInputs = [
  ['server', serverFixture('list-of-dates')],
  ['sample', ld.SAMPLE_RESULT],
  ['dates-in-many-forms', {
    matter: { title: 'Arora v. Bansal', number: 'CS(OS) 77/2024 — Delhi', forum: '  Delhi High Court ' },
    parties: { ours: 'Arora', other: 'Bansal' },
    entries: [
      { id: 'a', day: '12 March 2023', cat: 'ours', text: 'Arora writes to **Bansal** (Annexure **P-1**).' },
      { id: 'b', day: 'March 12, 2023', cat: 'adverse', text: 'Bansal replies.' },
      { id: 'c', day: '12.03.2023', cat: 'others', text: 'Bank confirms.' },
      { id: 'd', day: 'Mar 2023', cat: 'rules', text: '**Rule 5** applies.', label: 'Mar 2023 (rules)' },
      { id: 'e', day: '2023-02-30', cat: 'ours', text: 'A day that does not exist.' },
      { id: 'f', day: '2023-13-01', cat: 'ours', text: 'A month that does not exist.' },
      { id: 'g', day: '0999', cat: 'ours', text: 'Too early.' },
      { id: 'h', day: '2023-06-15T10:00:00Z', cat: 'ours', text: 'With a time.' },
      { id: 'i', day: '', cat: 'ours', text: 'No day.' },
      { id: 'j', day: 'sometime', cat: 'ours', text: 'Unreadable day.' },
      { id: 'k', day: 2023, cat: 'ours', text: 'A number for a day.' },
      { id: 'l', day: '1st Jan, 2020', cat: 'ours', text: 'Ordinal.' },
      { id: 'm', day: 'Sept 5 2021', cat: 'ours', text: 'Month first.' },
      { id: 'n', date: '2024-2-9', cat: 'ours', text: 'Uses the date key.' },
      { id: 'o', day: '29 Feb 2023', cat: 'ours', text: 'Not a leap year.' },
      { id: 'p', day: '29/02/2024', cat: 'ours', text: 'A leap year.' },
      { id: 'q', day: '5 Foo 2021', cat: 'ours', text: 'Unknown month.' },
      { id: 'r', day: '2027-01-10', cat: 'others', upcoming: true, text: '**Next hearing:** before the Registrar.' },
      { id: 's', day: '', cat: 'others', upcoming: true, text: 'Upcoming with no day.' },
    ],
    inSum: 'Arora paid on **time**; Bansal did not.',
    limitation: { headline: 'Three years from 12.03.2023', note: 'Check with your advocate.' },
  }],
  ['ids-cats-and-text', {
    labels: { ours: { chip: 'Us', label: '' }, adverse: { who: 'Them' }, rules: 'nope' },
    chartTitle: 'MY OWN TITLE',
    matter: 'not an object',
    limitation: { note: 'No headline.' },
    entries: [
      { id: 1, day: '2020-01-01', cat: 'ours', text: 'Numeric id.' },
      { id: 1, day: '2020-01-02', cat: 'ours', text: 'Duplicate id.' },
      { day: '2020-01-03', cat: 'claimant', text: 'Unknown cat, no id.' },
      { id: '', day: '2020-01-04', cat: 'Ours', short: 'Only a short line' },
      { id: 'long', day: '2020-01-05', cat: 'adverse', text: 'This is a long line of text with **bold words** in it that runs well past ninety characters so that the short line is cut.' },
      { id: 'stars', day: '2020-01-06', cat: 'rules', text: '**** stray ** marks *** and **a** and **unclosed' },
      { id: 'empty', day: '2020-01-07', cat: 'ours', text: '   ', short: '' },
      'junk',
      null,
      { id: 'x#7', day: '2020-01-08', cat: 'others', text: 'Looks like a repaired id.' },
      { id: 'x', day: '2020-01-09', cat: 'others', text: 'x' },
      { id: 'x', day: '2020-01-10', cat: 'others', text: 'x again' },
      { id: true, day: '2019', cat: 'others', text: 'Boolean id, year only.' },
      { id: 'sameday-1', day: '2019-05', cat: 'adverse', text: 'Month only.' },
    ],
  }],
  ['no-entries', { matter: { title: 'Only a title' }, entries: [] }],
  ['not-an-object', 'x'],
  ['null', null],
  ['an-array', []],
]
const projectChart = (c) => ({
  entries: c.entries.map(e => ({ id: e.id, day: e.day, cat: e.cat, text: e.text, short: e.short, label: e.label, upcoming: e.upcoming, hay: e.hay })),
  matter: { title: c.matter.title ?? '', number: c.matter.number ?? '', forum: c.matter.forum ?? '' },
  inSum: c.inSum, limitation: c.limitation, chartTitleOverride: c.chartTitleOverride,
  cats: Object.fromEntries(ld.CAT_ORDER.map(k => [k, { label: c.cats[k].label, chip: c.cats[k].chip, who: c.cats[k].who }])),
})
// The page's Timeline items (ListOfDatesPage.jsx, `Timeline`'s useMemo), restated here because
// the page is a React component; checked against the source text below so it cannot drift.
const timelineSource = fs.readFileSync(path.join(src, 'pages/analysis/ListOfDatesPage.jsx'), 'utf8')
for (const needle of [
  'entries.filter(e => e.upcoming).forEach(e => out.push({ e, next: true, key: e.id }))',
  'const order = [...rest.filter(e => e.day).reverse(), ...rest.filter(e => !e.day)]',
  "const y = yearOf(e.day) || 'Undated'",
]) {
  if (!timelineSource.includes(needle)) throw new Error(`ListOfDatesPage.jsx Timeline changed: ${needle}`)
}
const timeline = (entries) => {
  const items = []
  entries.filter(e => e.upcoming).forEach(e => items.push({ entry: e.id, next: true }))
  const rest = entries.filter(e => !e.upcoming)
  const order = [...rest.filter(e => e.day).reverse(), ...rest.filter(e => !e.day)]
  let year = null
  order.forEach(e => {
    const y = ld.yearOf(e.day) || 'Undated'
    if (y !== year) { items.push({ year: y }); year = y }
    items.push({ entry: e.id, next: false })
  })
  return items
}
const ldCases = ldInputs.map(([id, input]) => {
  const c = ld.normalizeResult(input)
  const shownAdverse = c.entries.filter(e => e.cat === 'adverse')
  return {
    id, input,
    normalised: projectChart(c),
    sum: c.sum,
    title: c.title,
    byYear: ld.byYear(c.entries).map(r => ({ year: r.year, rules: r.rules.map(e => e.id), events: r.events.map(e => e.id) })),
    plainText: ld.asPlainText(c),
    plainTextAdverse: ld.asPlainText(c, shownAdverse),
    wordHtml: ld.asWordHtml(c),
    fileStem: ld.fileStem(c),
    matterLine: ld.matterLine(c),
    eventsHead: ld.eventsHead(c),
    timeline: timeline(c.entries),
    matches: ['bank', ' BANSAL ', 'march 2023', 'undated', '12.03.2023', 'zzz'].map(q => ({ q, ids: c.entries.filter(e => ld.matches(e, q)).map(e => e.id) })),
  }
})
const days = ['2023-03-12', '2023-03', '2023', '', '2023-12-01', '1963-12-05']
const ldGolden = {
  cases: ldCases,
  normDay: ['2023-03-12', '2023-3-5', '2023', '12/03/2023', '12-3-2023', '3.12.2023', '31.04.2023', '12 March 2023', '12th march, 2023', '12-Mar-2023',
    'March 12, 2023', 'Mar. 12th 2023', 'March 2023', 'Sep 2023', 'Sept. 2023', 'Foo 2023', '2023-02-29', '2024-02-29', '2023-00-10',
    '3000-01-01', '999', '2023-06-15 10:00', '2023-06-15T10:00:00Z', '  2023-06-15  ', 'yesterday', '', null, 2023, 20230615].map(v => ({ v, out: ld.normDay(v) })),
  parseRich: ['plain', '**bold**', 'a **b** c **d**', '**', '****', '** x **', 'a ** b', '**a**b**c**', '***a***', 'line\n**two\nlines**', '', null, 7]
    .map(v => ({ v, out: ld.parseRich(v).map(p => ({ t: p.t, b: p.b })) })),
  days: days.map(day => ({ day, dmy: ld.dmy(day), shortDate: ld.shortDate(day), fullDate: ld.fullDate(day), yearOf: ld.yearOf(day) })),
}

// ── History wording ──────────────────────────────────────────────────────────────────────────
const NOW = Date.parse('2026-10-27T10:00:00.000Z')
const historyGolden = {
  timeZone: process.env.TZ,
  now: new Date(NOW).toISOString(),
  ago: [0, 30, 59, 60, 89, 90, 3599, 3600, 5400, 86399, 86400, 13 * 86400, 13.5 * 86400, 14 * 86400, 400 * 86400, -100]
    .map(s => { const iso = new Date(NOW - s * 1000).toISOString(); return { iso, text: historyHelpers.ago(iso, NOW) } })
    .concat([{ iso: 'not a date', text: historyHelpers.ago('not a date', NOW) }]),
  fullDate: ['2026-10-27T09:34:00.000Z', '2026-10-27T18:30:00.000Z', '2026-09-20T06:45:00.000Z', '2026-01-01T00:00:00.000Z', '2026-06-30T12:05:00.000Z', 'nope']
    .map(iso => ({ iso, text: historyHelpers.fullDate(iso) })),
  fileLine: [[], ['a.pdf'], ['a.pdf', 'b.pdf'], ['a.pdf', 'b.pdf', 'c.pdf'], ['a', 'b', 'c', 'd', 'e']].map(names => ({ names, text: historyHelpers.fileLine(names) })),
  runTitle: [{ title: 'T', fileNames: ['a'] }, { title: '', fileNames: ['a', 'b'] }, { title: '', fileNames: [] }, {}].map(run => ({ run, text: historyHelpers.runTitle(run) })),
}

// ── Writing ──────────────────────────────────────────────────────────────────────────────────
const files = {
  'da-golden.json': daGolden,
  'doc-index-golden.json': diGolden,
  'list-of-dates-golden.json': ldGolden,
  'history-golden.json': historyGolden,
  'server-devils-advocate.json': serverFixture('devils-advocate'),
  'server-doc-index.json': serverFixture('doc-index'),
  'server-list-of-dates.json': serverFixture('list-of-dates'),
}
let differs = 0
for (const [name, value] of Object.entries(files)) {
  const file = path.join(out, name)
  const text = JSON.stringify(value, null, 1) + '\n'
  const before = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
  if (before === text) { console.log(`${name}: unchanged`); continue }
  differs += 1
  if (checkOnly) { console.log(`${name}: differs from the platform`); continue }
  fs.mkdirSync(out, { recursive: true })
  fs.writeFileSync(file, text)
  console.log(`${name}: written`)
}
if (checkOnly && differs) process.exit(1)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else if (/\.(js|jsx|mjs)$/.test(entry.name)) yield p
  }
}
