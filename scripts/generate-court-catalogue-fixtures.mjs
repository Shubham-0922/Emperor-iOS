#!/usr/bin/env node
// Regenerates the court-catalogue golden fixture from the platform's own source.
//
//   node scripts/generate-court-catalogue-fixtures.mjs <path-to-emperor-ai> [--check]
//
// Writes Tests/EmperorCoreTests/Resources/parity/06-C/court-catalogue.json: src/lib/courts.js's
// static lists — the courts, the Supreme Court's case types, NCLT/NCLAT benches and case types,
// the High Court state codes — so a change there fails `CourtCatalogueGoldenTests` instead of
// drifting silently.
//
// `--check` writes nothing and exits 1 if the fixture differs.

process.env.TZ = 'UTC'

import { registerHooks } from 'node:module'
import { pathToFileURL, fileURLToPath } from 'node:url'
import fs from 'node:fs'
import path from 'node:path'

const platform = process.argv[2]
const checkOnly = process.argv.includes('--check')
if (!platform || !fs.existsSync(path.join(platform, 'src/lib/courts.js'))) {
  console.error('usage: generate-court-catalogue-fixtures.mjs <path-to-emperor-ai> [--check]')
  process.exit(2)
}
const root = path.resolve(platform)
const src = path.join(root, 'src')
const outDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../Tests/EmperorCoreTests/Resources/parity/06-C')

// `@/` is the web's alias for src/. lucide-react resolves each icon to its own name; the zustand
// store is a stand-in nothing here calls.
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'lucide-react') return { url: 'emperor-stub:lucide', shortCircuit: true }
    let target = null
    if (specifier.startsWith('@/')) target = path.join(src, specifier.slice(2))
    else if (specifier.startsWith('.') && context.parentURL?.startsWith('file:')) {
      target = path.resolve(path.dirname(fileURLToPath(context.parentURL)), specifier)
    }
    if (target === path.join(src, 'lib/store')) return { url: 'emperor-stub:store', shortCircuit: true }
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
    if (url === 'emperor-stub:lucide') {
      const names = new Set()
      for (const file of walk(src)) {
        const text = fs.readFileSync(file, 'utf8')
        for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*['"]lucide-react['"]/g)) {
          for (const part of m[1].split(',')) {
            const name = part.trim().split(/\s+as\s+/)[0].trim()
            if (/^[A-Za-z_$][\w$]*$/.test(name)) names.add(name)
          }
        }
      }
      return { format: 'module', source: [...names].map(n => `export const ${n} = '${n}';`).join('\n'), shortCircuit: true }
    }
    if (url === 'emperor-stub:store') {
      return { format: 'module', source: 'export const useStore = { getState: () => ({}) };', shortCircuit: true }
    }
    if (url.startsWith('file:') && url.startsWith(pathToFileURL(root).href) && /\.(js|jsx|mjs)$/.test(url)) {
      return { format: 'module', source: fs.readFileSync(fileURLToPath(url), 'utf8'), shortCircuit: true }
    }
    return next(url, context)
  },
})

const imp = (rel) => import(pathToFileURL(path.join(root, rel)).href)
const courts = await imp('src/lib/courts.js')

// ── The catalogue ───────────────────────────────────────────────────────────────────────────
const catalogue = {
  courts: courts.COURTS,
  scCaseTypes: courts.SC_CASE_TYPES,
  ncltBenches: courts.NCLT_BENCHES,
  ncltCaseTypes: courts.NCLT_CASE_TYPES,
  nclatBenches: courts.NCLAT_BENCHES,
  nclatCaseTypes: courts.NCLAT_CASE_TYPES,
  hcStateCode: courts.HC_STATE_CODE,
}

// ── Output ──────────────────────────────────────────────────────────────────────────────────
let stale = false
const write = (name, value) => {
  const out = path.join(outDir, name)
  const text = JSON.stringify(value, null, 1) + '\n'
  const before = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null
  if (before === text) { console.log(`${name}: up to date`); return }
  if (checkOnly) { console.error(`${name}: out of date — rerun without --check`); stale = true; return }
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(out, text)
  console.log(`${name}: written`)
}
write('court-catalogue.json', catalogue)
console.log(`${catalogue.courts.length} courts`)
if (stale) process.exit(1)

function* walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name)
    if (entry.isDirectory()) yield* walk(p)
    else if (/\.(js|jsx|mjs)$/.test(entry.name)) yield p
  }
}
