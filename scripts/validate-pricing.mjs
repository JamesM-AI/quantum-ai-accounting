#!/usr/bin/env node
// Validates data/competitors.json and data/pricing.json.
// Usage: node scripts/validate-pricing.mjs [dataDir]
// Exits non-zero with a list of problems if anything is wrong.

import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dataDir = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..', 'data');
const errors = [];
const fail = (where, msg) => errors.push(`${where}: ${msg}`);

function load(name) {
    try {
        return JSON.parse(readFileSync(join(dataDir, name), 'utf8'));
    } catch (err) {
        fail(name, `cannot read or parse (${err.message})`);
        return null;
    }
}

const ENUMS = {
    market: ['UK', 'KE'],
    service_line: ['ai_implementation', 'managed_support'],
    segment: ['micro', 'mid'],
    fee_type: ['setup', 'maintenance'],
    currency: ['GBP', 'KES', 'USD', 'EUR'],
    period: ['one-off', 'monthly', 'annual', 'hourly', 'daily'],
    vat_basis: ['ex_vat', 'inc_vat', 'unknown'],
    evidence: ['published', 'third_party', 'estimate'],
    unit: ['per_company', 'per_user'],
    verified_via: ['page', 'search_extract']
};

const isDate = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(v));
const isHttps = v => typeof v === 'string' && /^https:\/\/[^\s]+$/.test(v);
const isText = v => typeof v === 'string' && v.trim().length > 0;

function checkEnum(where, obj, field, { optional = false } = {}) {
    if (optional && obj[field] === undefined) return;
    if (!ENUMS[field].includes(obj[field])) fail(where, `${field} "${obj[field]}" must be one of ${ENUMS[field].join(', ')}`);
}

const competitorsFile = load('competitors.json');
const pricingFile = load('pricing.json');

const competitors = new Map();
if (competitorsFile) {
    if (!Array.isArray(competitorsFile.competitors)) fail('competitors.json', 'missing "competitors" array');
    (competitorsFile.competitors || []).forEach((c, i) => {
        const where = `competitors[${i}] (${c.id || 'no id'})`;
        if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(c.id || '')) fail(where, 'id must be kebab-case');
        if (competitors.has(c.id)) fail(where, 'duplicate id');
        if (!isText(c.name)) fail(where, 'name is required');
        checkEnum(where, c, 'market');
        if (!isHttps(c.url)) fail(where, 'url must be https');
        if (!Array.isArray(c.service_lines) || !c.service_lines.length || c.service_lines.some(s => !ENUMS.service_line.includes(s))) fail(where, 'service_lines must be a non-empty list of known services');
        if (!Array.isArray(c.segments) || !c.segments.length || c.segments.some(s => !ENUMS.segment.includes(s))) fail(where, 'segments must be a non-empty list of known segments');
        if (!isText(c.why_comparable)) fail(where, 'why_comparable is required');
        if (typeof c.active !== 'boolean') fail(where, 'active must be true or false');
        if (c.pending_review !== undefined && typeof c.pending_review !== 'boolean') fail(where, 'pending_review must be true or false');
        if (c.pending_review && c.active) fail(where, 'a firm pending review must have active: false');
        if (!isDate(c.added)) fail(where, 'added must be YYYY-MM-DD');
        competitors.set(c.id, c);
    });
}

if (pricingFile) {
    const a = pricingFile.assumptions || {};
    const users = a.users_per_segment || {};
    if (!(users.micro > 0) || !(users.mid > 0)) fail('assumptions', 'users_per_segment.micro and .mid must be positive numbers');
    const vat = a.vat_rates || {};
    if (!(vat.UK >= 0 && vat.UK < 1) || !(vat.KE >= 0 && vat.KE < 1)) fail('assumptions', 'vat_rates.UK and .KE must be fractions such as 0.2');

    const runs = pricingFile.runs;
    const runDates = new Set();
    if (!Array.isArray(runs) || !runs.length) fail('pricing.json', 'needs at least one run');
    (runs || []).forEach((r, i) => {
        const where = `runs[${i}] (${r.run_date || 'no date'})`;
        if (!isDate(r.run_date)) fail(where, 'run_date must be YYYY-MM-DD');
        if (runDates.has(r.run_date)) fail(where, 'duplicate run_date');
        runDates.add(r.run_date);
        const fx = r.fx || {};
        if (!(fx.GBP_KES > 0)) fail(where, 'fx.GBP_KES must be a positive number');
        if (fx.GBP_KES > 0 && (fx.GBP_KES < 50 || fx.GBP_KES > 500)) fail(where, `fx.GBP_KES ${fx.GBP_KES} looks wrong`);
        if (fx.GBP_USD !== undefined && !(fx.GBP_USD > 0.5 && fx.GBP_USD < 3)) fail(where, `fx.GBP_USD ${fx.GBP_USD} looks wrong`);
        if (fx.GBP_EUR !== undefined && !(fx.GBP_EUR > 0.5 && fx.GBP_EUR < 3)) fail(where, `fx.GBP_EUR ${fx.GBP_EUR} looks wrong`);
        if (!isHttps(fx.source_url)) fail(where, 'fx.source_url must be https');
        if (!isText(r.summary)) fail(where, 'summary is required');
    });

    const seen = new Set();
    (pricingFile.observations || []).forEach((o, i) => {
        const where = `observations[${i}] (${o.competitor_id} ${o.fee_type} ${o.segment})`;
        const c = competitors.get(o.competitor_id);
        if (!c) fail(where, `unknown competitor_id "${o.competitor_id}"`);
        if (!runDates.has(o.run_date)) fail(where, `run_date ${o.run_date} has no matching run`);
        ['service_line', 'segment', 'fee_type', 'currency', 'period', 'vat_basis', 'evidence', 'unit'].forEach(f => checkEnum(where, o, f));
        checkEnum(where, o, 'verified_via', { optional: true });
        if (!(typeof o.low === 'number' && o.low >= 0)) fail(where, 'low must be a number >= 0');
        if (!(typeof o.high === 'number' && o.high >= 0)) fail(where, 'high must be a number >= 0');
        if (o.low > o.high) fail(where, 'low is greater than high');
        if (!isHttps(o.source_url)) fail(where, 'source_url must be https');
        if (o.evidence === 'estimate' && !isText(o.notes)) fail(where, 'an estimate must explain its basis in notes');
        if (o.fee_type === 'setup' && ['monthly', 'annual'].includes(o.period)) fail(where, 'a setup fee cannot be monthly or annual');
        if (o.fee_type === 'maintenance' && o.period === 'one-off') fail(where, 'a maintenance fee cannot be one-off');
        if (o.unit === 'per_user' && o.fee_type === 'setup' && o.period === 'one-off') {
            // Allowed, but unusual enough to flag for a human.
            console.warn(`warning ${where}: per-user one-off setup fee`);
        }
        if (o.currency === 'KES' && c && c.market === 'UK') fail(where, 'KES price on a UK firm');
        if (o.currency !== 'GBP' && o.currency !== 'KES' && runs) {
            const run = runs.find(r => r.run_date === o.run_date);
            if (run && !(run.fx && run.fx['GBP_' + o.currency] > 0)) fail(where, `run ${o.run_date} has no fx.GBP_${o.currency} to convert this price`);
        }
        if (c && !c.service_lines.includes(o.service_line)) fail(where, `${c.id} is not listed for ${o.service_line}`);
        const key = [o.competitor_id, o.service_line, o.segment, o.fee_type, o.evidence, o.run_date].join('|');
        if (seen.has(key)) fail(where, 'duplicate observation for the same firm, service, segment, fee, evidence and run');
        seen.add(key);
    });
}

if (errors.length) {
    console.error(`Pricing data FAILED validation (${errors.length} problem${errors.length === 1 ? '' : 's'}):`);
    errors.forEach(e => console.error('  - ' + e));
    process.exit(1);
}

const nObs = pricingFile.observations.length;
console.log(`Pricing data OK: ${competitors.size} competitors, ${pricingFile.runs.length} run(s), ${nObs} observations.`);
