// Market Pricing tab: competitor setup and maintenance fees, UK and Kenya.
// Data lives in data/competitors.json and data/pricing.json and is refreshed
// by the weekly Saturday run (see docs/weekly-pricing-update.md).

const MP_DEFAULT_VAT = { UK: 0.20, KE: 0.16 };
const MP_DEFAULT_USERS = { micro: 20, mid: 100 };
const MP_STALE_DAYS = 28;
const MP_CHANGE_THRESHOLD = 0.10;

const MP_LABELS = {
    service: { ai_implementation: 'AI implementation', managed_support: 'Managed support' },
    segment: { micro: 'Micro / small', mid: 'Mid-market' },
    fee: { setup: 'Setup', maintenance: 'Maintenance' },
    evidence: { published: 'Published', third_party: 'Third-party', estimate: 'Estimate' },
    period: { 'one-off': 'one-off', monthly: '/month', annual: '/year', hourly: '/hour', daily: '/day' },
    market: { UK: 'UK', KE: 'Kenya' }
};

const MP_EVIDENCE_ORDER = ['published', 'third_party', 'estimate'];

function mpEscape(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    })[c]);
}

function mpSafeUrl(url) {
    return typeof url === 'string' && /^https:\/\//i.test(url) ? url : null;
}

function mpMedian(values) {
    const sorted = values.filter(v => Number.isFinite(v)).sort((a, b) => a - b);
    if (!sorted.length) return null;
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function mpDaysBetween(a, b) {
    return Math.round((new Date(b) - new Date(a)) / 86400000);
}

class MarketPricing {
    constructor(root) {
        this.root = root;
        this.loaded = false;
        this.charts = {};
        this.filters = { market: 'UK', service: 'all', segment: 'all', excludeEstimates: false };
        this.bindFilters();
    }

    bindFilters() {
        if (!this.root) return;
        const bind = (id, key, read) => {
            const el = this.root.querySelector(id);
            if (!el) return;
            el.addEventListener('change', () => {
                this.filters[key] = read(el);
                if (this.loaded) this.render();
            });
        };
        bind('#mp-market', 'market', el => el.value);
        bind('#mp-service', 'service', el => el.value);
        bind('#mp-segment', 'segment', el => el.value);
        bind('#mp-exclude-estimates', 'excludeEstimates', el => el.checked);
    }

    async show() {
        if (this.loaded || this.loading) return;
        this.loading = true;
        const status = this.root.querySelector('#mp-status');
        try {
            const [competitors, pricing] = await Promise.all([
                fetch('data/competitors.json', { cache: 'no-cache' }).then(r => r.json()),
                fetch('data/pricing.json', { cache: 'no-cache' }).then(r => r.json())
            ]);
            this.competitors = competitors.competitors || [];
            this.byId = Object.fromEntries(this.competitors.map(c => [c.id, c]));
            this.runs = [...(pricing.runs || [])].sort((a, b) => a.run_date.localeCompare(b.run_date));
            this.observations = pricing.observations || [];
            const assumptions = pricing.assumptions || {};
            this.vat = assumptions.vat_rates || MP_DEFAULT_VAT;
            this.users = assumptions.users_per_segment || MP_DEFAULT_USERS;
            this.loaded = true;
            status.hidden = true;
            this.render();
        } catch (err) {
            status.textContent = 'Could not load pricing data. If you opened index.html directly from disk, serve the folder instead (python3 -m http.server).';
            console.error(err);
        } finally {
            this.loading = false;
        }
    }

    // ---- data shaping ---------------------------------------------------

    runFor(date) {
        let match = this.runs[0];
        for (const run of this.runs) {
            if (run.run_date <= date) match = run;
        }
        return match;
    }

    get latestRun() {
        return this.runs[this.runs.length - 1];
    }

    toGBP(amount, currency, fx) {
        if (currency === 'GBP') return amount;
        const rate = fx && fx['GBP_' + currency];
        return rate ? amount / rate : null;
    }

    // Returns ex-VAT GBP figures for the whole client firm, with maintenance
    // expressed per month. Per-user prices are multiplied by the assumed
    // headcount for the segment. Hourly and day rates are kept for the table
    // but are not comparable.
    normalise(obs) {
        const competitor = this.byId[obs.competitor_id];
        const market = competitor ? competitor.market : 'UK';
        const fx = this.runFor(obs.run_date).fx;
        const vat = obs.vat_basis === 'inc_vat' ? 1 / (1 + this.vat[market]) : 1;
        let factor = null;
        if (obs.fee_type === 'setup' && obs.period === 'one-off') factor = 1;
        if (obs.fee_type === 'maintenance' && obs.period === 'monthly') factor = 1;
        if (obs.fee_type === 'maintenance' && obs.period === 'annual') factor = 1 / 12;
        if (factor !== null && obs.unit === 'per_user') factor *= this.users[obs.segment];
        const low = this.toGBP(obs.low, obs.currency, fx);
        const high = this.toGBP(obs.high, obs.currency, fx);
        const comparable = factor !== null && low !== null && high !== null;
        return {
            ...obs,
            market,
            competitor,
            comparable,
            lowGBP: comparable ? low * vat * factor : null,
            highGBP: comparable ? high * vat * factor : null,
            midGBP: comparable ? ((low + high) / 2) * vat * factor : null
        };
    }

    // Evidence is part of the key so a firm's own price and a third-party
    // figure for the same fee are tracked side by side.
    key(obs) {
        return [obs.competitor_id, obs.service_line, obs.segment, obs.fee_type, obs.evidence].join('|');
    }

    // Latest observation for each firm/service/segment/fee as of a run date.
    snapshot(asOf) {
        const latest = new Map();
        for (const obs of this.observations) {
            if (obs.run_date > asOf) continue;
            const k = this.key(obs);
            const prev = latest.get(k);
            if (!prev || obs.run_date > prev.run_date) latest.set(k, obs);
        }
        return [...latest.values()].map(o => this.normalise(o));
    }

    applyFilters(rows) {
        const f = this.filters;
        return rows.filter(r =>
            r.competitor && r.competitor.active && !r.competitor.pending_review &&
            r.market === f.market &&
            (f.service === 'all' || r.service_line === f.service) &&
            (f.segment === 'all' || r.segment === f.segment)
        );
    }

    forMedian(rows, feeType) {
        return rows.filter(r =>
            r.fee_type === feeType && r.comparable &&
            !(this.filters.excludeEstimates && r.evidence === 'estimate')
        );
    }

    // ---- formatting -----------------------------------------------------

    formatGBP(gbp, { compact = false } = {}) {
        if (gbp === null || gbp === undefined) return '–';
        const opts = { style: 'currency', currency: 'GBP', maximumFractionDigits: 0 };
        if (compact) Object.assign(opts, { notation: 'compact', maximumFractionDigits: 1 });
        return new Intl.NumberFormat('en-GB', opts).format(gbp);
    }

    formatKES(kes, { compact = false } = {}) {
        const opts = { maximumFractionDigits: 0 };
        if (compact) Object.assign(opts, { notation: 'compact', maximumFractionDigits: 1 });
        return 'KES ' + new Intl.NumberFormat('en-GB', opts).format(kes);
    }

    // Kenya figures lead with shillings and show the GBP conversion beside them.
    formatMarket(gbp, market, opts = {}) {
        if (gbp === null || gbp === undefined) return '–';
        if (market !== 'KE') return this.formatGBP(gbp, opts);
        const rate = this.latestRun.fx.GBP_KES;
        return `${this.formatKES(gbp * rate, opts)} (≈ ${this.formatGBP(gbp, opts)})`;
    }

    chartValue(gbp) {
        return this.filters.market === 'KE' ? gbp * this.latestRun.fx.GBP_KES : gbp;
    }

    axisLabel(value) {
        return this.filters.market === 'KE'
            ? this.formatKES(value, { compact: true })
            : this.formatGBP(value, { compact: true });
    }

    formatQuoted(obs) {
        const fmt = new Intl.NumberFormat('en-GB', { maximumFractionDigits: 2 });
        const amount = obs.low === obs.high
            ? fmt.format(obs.low)
            : `${fmt.format(obs.low)}–${fmt.format(obs.high)}`;
        const vat = obs.vat_basis === 'inc_vat' ? ' inc VAT' : obs.vat_basis === 'ex_vat' ? ' ex VAT' : '';
        const unit = obs.unit === 'per_user' ? ' per user' : '';
        return `${obs.currency} ${amount}${unit} ${MP_LABELS.period[obs.period] || obs.period}${vat}`;
    }

    rowLabel(row) {
        const parts = [row.competitor.name];
        if (this.filters.segment === 'all') parts.push(MP_LABELS.segment[row.segment]);
        if (this.filters.service === 'all') parts.push(row.service_line === 'ai_implementation' ? 'AI impl.' : 'Support');
        return parts.join(' · ');
    }

    // ---- rendering ------------------------------------------------------

    render() {
        const latest = this.latestRun;
        if (!latest) return;
        const rows = this.applyFilters(this.snapshot(latest.run_date));
        this.renderKpis(rows, latest);
        this.renderRangeChart('setup', rows.filter(r => r.fee_type === 'setup' && r.comparable));
        this.renderRangeChart('maint', rows.filter(r => r.fee_type === 'maintenance' && r.comparable));
        this.renderTrend('setup');
        this.renderTrend('maintenance');
        this.renderChanges(latest);
        this.renderProposed();
        this.renderTable(rows, latest);
        this.renderFootnote(latest);
    }

    renderKpis(rows, latest) {
        const market = this.filters.market;
        const setup = this.forMedian(rows, 'setup');
        const maint = this.forMedian(rows, 'maintenance');
        const publishedFirms = new Set(rows.filter(r => r.evidence === 'published').map(r => r.competitor_id));
        const allFirms = new Set(rows.map(r => r.competitor_id));
        const tiles = [
            ['Median setup fee', this.formatMarket(mpMedian(setup.map(r => r.midGBP)), market), `${setup.length} price points`],
            ['Median monthly maintenance', this.formatMarket(mpMedian(maint.map(r => r.midGBP)), market), `${maint.length} price points`],
            ['Firms publishing prices', `${publishedFirms.size} of ${allFirms.size}`, 'The rest come from third-party sources or estimates'],
            ['Last updated', new Date(latest.run_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }), 'Refreshed every Saturday at 8am UK time']
        ];
        this.root.querySelector('#mp-kpis').innerHTML = tiles.map(([title, value, sub]) => `
            <div class="metric-card">
                <h3>${mpEscape(title)}</h3>
                <div class="metric-value mp-kpi-value">${mpEscape(value)}</div>
                <div class="mp-kpi-sub">${mpEscape(sub)}</div>
            </div>`).join('');
    }

    cssVar(name) {
        return getComputedStyle(this.root).getPropertyValue(name).trim();
    }

    evidenceColour(evidence) {
        return this.cssVar('--mp-ev-' + evidence.replace('_', '-'));
    }

    renderLegends() {
        const html = MP_EVIDENCE_ORDER.map(ev => `
            <span class="mp-legend-item"><span class="mp-swatch mp-swatch-${ev.replace('_', '-')}"></span>${MP_LABELS.evidence[ev]}</span>`).join('');
        this.root.querySelectorAll('.mp-legend').forEach(el => { el.innerHTML = html; });
    }

    destroyChart(id) {
        if (this.charts[id]) {
            this.charts[id].destroy();
            delete this.charts[id];
        }
    }

    baseChartOptions() {
        const ink = this.cssVar('--mp-ink-muted');
        const grid = this.cssVar('--mp-grid');
        Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
        Chart.defaults.color = ink;
        return {
            responsive: true,
            maintainAspectRatio: false,
            animation: false,
            plugins: { legend: { display: false } },
            scales: {
                x: { grid: { color: grid }, border: { display: false }, ticks: { color: ink } },
                y: { grid: { display: false }, border: { color: grid }, ticks: { color: ink } }
            }
        };
    }

    renderRangeChart(kind, rows) {
        const canvasId = kind === 'setup' ? 'mp-setup-chart' : 'mp-maint-chart';
        const wrap = this.root.querySelector(kind === 'setup' ? '#mp-setup-wrap' : '#mp-maint-wrap');
        this.renderLegends();
        this.destroyChart(canvasId);
        wrap.querySelector('.mp-empty')?.remove();
        const canvas = wrap.querySelector('canvas');

        if (typeof Chart === 'undefined' || !rows.length) {
            canvas.hidden = true;
            wrap.style.height = 'auto';
            wrap.insertAdjacentHTML('beforeend', `<p class="mp-empty">${rows.length ? 'Charts could not load. The table below has every figure.' : 'No comparable price points for this filter yet.'}</p>`);
            return;
        }
        canvas.hidden = false;

        const sorted = [...rows].sort((a, b) => a.midGBP - b.midGBP);
        wrap.style.height = Math.max(160, sorted.length * 30 + 50) + 'px';
        const colours = sorted.map(r => this.evidenceColour(r.evidence));
        const options = this.baseChartOptions();
        options.indexAxis = 'y';
        options.scales.x.ticks.callback = v => this.axisLabel(v);
        options.scales.x.ticks.maxRotation = 0;
        options.scales.x.ticks.maxTicksLimit = 6;
        // Keep labels to roughly 40% of the chart width so bars stay readable.
        const maxChars = Math.max(14, Math.min(34, Math.floor(wrap.clientWidth * 0.4 / 6.5)));
        options.scales.y.ticks.callback = (v, i) => {
            const label = this.rowLabel(sorted[i]);
            return label.length > maxChars ? label.slice(0, maxChars - 1) + '…' : label;
        };
        options.plugins.tooltip = {
            callbacks: {
                title: items => this.rowLabel(sorted[items[0].dataIndex]),
                label: item => {
                    const r = sorted[item.dataIndex];
                    const basis = r.unit === 'per_user' ? ` (${this.users[r.segment]} users assumed)` : '';
                    const range = r.lowGBP === r.highGBP
                        ? this.formatMarket(r.lowGBP, r.market)
                        : `${this.formatMarket(r.lowGBP, r.market)} to ${this.formatMarket(r.highGBP, r.market)}`;
                    return [range + basis, `${MP_LABELS.evidence[r.evidence]} · ${MP_LABELS.segment[r.segment]} · ${MP_LABELS.service[r.service_line]}`];
                }
            }
        };

        this.charts[canvasId] = new Chart(canvas, {
            type: 'bar',
            data: {
                labels: sorted.map(r => this.rowLabel(r)),
                datasets: [{
                    data: sorted.map(r => [this.chartValue(r.lowGBP), this.chartValue(r.highGBP)]),
                    // A single price still needs a visible mark.
                    minBarLength: 6,
                    backgroundColor: sorted.map((r, i) => r.evidence === 'estimate' ? 'transparent' : colours[i]),
                    borderColor: colours,
                    borderWidth: sorted.map(r => r.evidence === 'estimate' ? 2 : 0),
                    borderRadius: 4,
                    borderSkipped: false,
                    barThickness: 12
                }]
            },
            options
        });
    }

    renderTrend(feeType) {
        const canvasId = feeType === 'setup' ? 'mp-trend-setup' : 'mp-trend-maint';
        const canvas = this.root.querySelector('#' + canvasId);
        this.destroyChart(canvasId);
        if (typeof Chart === 'undefined') return;

        const points = this.runs.map(run => {
            const rows = this.forMedian(this.applyFilters(this.snapshot(run.run_date)), feeType);
            const median = mpMedian(rows.map(r => r.midGBP));
            return { date: run.run_date, value: median === null ? null : this.chartValue(median), n: rows.length };
        });
        const line = this.cssVar('--mp-ev-published');
        const surface = this.cssVar('--color-surface');
        const options = this.baseChartOptions();
        options.scales.y.grid = { color: this.cssVar('--mp-grid') };
        options.scales.y.beginAtZero = true;
        options.scales.y.ticks.callback = v => this.axisLabel(v);
        options.scales.x.grid = { display: false };
        options.scales.x.ticks.maxRotation = 0;
        options.interaction = { mode: 'index', intersect: false };
        options.plugins.tooltip = {
            callbacks: {
                label: item => {
                    const p = points[item.dataIndex];
                    const gbp = this.filters.market === 'KE' ? p.value / this.latestRun.fx.GBP_KES : p.value;
                    return `${this.formatMarket(gbp, this.filters.market)} (${p.n} price points)`;
                }
            }
        };

        this.charts[canvasId] = new Chart(canvas, {
            type: 'line',
            data: {
                labels: points.map(p => new Date(p.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })),
                datasets: [{
                    data: points.map(p => p.value),
                    borderColor: line,
                    backgroundColor: line,
                    borderWidth: 2,
                    pointRadius: 4,
                    pointBorderColor: surface,
                    pointBorderWidth: 2,
                    pointHoverRadius: 6,
                    tension: 0,
                    spanGaps: true
                }]
            },
            options
        });
    }

    renderChanges(latest) {
        const list = this.root.querySelector('#mp-changes');
        const idx = this.runs.indexOf(latest);
        const previous = this.runs[idx - 1];
        const market = this.filters.market;
        const items = [];

        if (latest.summary) items.push(`<li class="mp-summary">${mpEscape(latest.summary)}</li>`);

        if (!previous) {
            items.push('<li>This is the first run, so there is nothing to compare against yet. Week-on-week changes appear from the next Saturday update.</li>');
            list.innerHTML = items.join('');
            return;
        }

        const now = new Map(this.applyFilters(this.snapshot(latest.run_date)).map(r => [this.key(r), r]));
        const before = new Map(this.applyFilters(this.snapshot(previous.run_date)).map(r => [this.key(r), r]));
        const name = r => mpEscape(r.competitor.name);
        const what = r => `${MP_LABELS.fee[r.fee_type].toLowerCase()} (${MP_LABELS.segment[r.segment].toLowerCase()}, ${MP_LABELS.service[r.service_line].toLowerCase()})`;

        this.competitors
            .filter(c => c.market === market && c.active && !c.pending_review && c.added > previous.run_date)
            .forEach(c => items.push(`<li><span class="mp-tag">New firm</span> ${mpEscape(c.name)}</li>`));

        for (const [k, r] of now) {
            const old = before.get(k);
            if (!old || !r.comparable || !old.comparable || r.run_date !== latest.run_date) continue;
            const change = (r.midGBP - old.midGBP) / old.midGBP;
            if (Math.abs(change) >= MP_CHANGE_THRESHOLD) {
                const dir = change > 0 ? 'up' : 'down';
                items.push(`<li><span class="mp-tag mp-tag-${dir}">${dir === 'up' ? '▲' : '▼'} ${Math.abs(change * 100).toFixed(0)}%</span> ${name(r)} ${what(r)}: ${mpEscape(this.formatMarket(old.midGBP, market))} → ${mpEscape(this.formatMarket(r.midGBP, market))}</li>`);
            }
        }

        for (const [k, r] of now) {
            if (r.run_date !== latest.run_date && before.get(k)?.run_date === previous.run_date) {
                items.push(`<li><span class="mp-tag mp-tag-warn">Not re-verified</span> ${name(r)} ${what(r)}. Price could not be confirmed this week.</li>`);
            }
        }

        if (items.length === (latest.summary ? 1 : 0)) items.push('<li>No price moves of 10% or more this week.</li>');
        list.innerHTML = items.join('');
    }

    renderProposed() {
        const list = this.root.querySelector('#mp-proposed');
        const pending = this.competitors.filter(c => c.pending_review && c.market === this.filters.market);
        list.innerHTML = pending.length
            ? pending.map(c => {
                const url = mpSafeUrl(c.url);
                const name = url ? `<a href="${mpEscape(url)}" target="_blank" rel="noopener noreferrer">${mpEscape(c.name)}</a>` : mpEscape(c.name);
                return `<li>${name}<span class="mp-muted"> · added ${mpEscape(c.added)}</span><br><span class="mp-muted">${mpEscape(c.why_comparable)}</span></li>`;
            }).join('')
            : '<li class="mp-muted">None awaiting review for this market.</li>';
    }

    renderTable(rows, latest) {
        const body = this.root.querySelector('#mp-table-body');
        const sorted = [...rows].sort((a, b) =>
            a.competitor.name.localeCompare(b.competitor.name) ||
            a.service_line.localeCompare(b.service_line) ||
            a.segment.localeCompare(b.segment) ||
            b.fee_type.localeCompare(a.fee_type));
        if (!sorted.length) {
            body.innerHTML = '<tr><td colspan="8" class="mp-muted">No price points for this filter.</td></tr>';
            return;
        }
        body.innerHTML = sorted.map(r => {
            const url = mpSafeUrl(r.source_url);
            const comparable = r.comparable
                ? (r.lowGBP === r.highGBP
                    ? this.formatMarket(r.lowGBP, r.market)
                    : `${this.formatMarket(r.lowGBP, r.market)} – ${this.formatMarket(r.highGBP, r.market)}`) + (r.fee_type === 'maintenance' ? ' /month' : '') +
                  (r.unit === 'per_user' ? ` at ${this.users[r.segment]} users (assumed)` : '')
                : 'Rate only, not in medians';
            const age = mpDaysBetween(r.run_date, latest.run_date);
            const stale = age > MP_STALE_DAYS;
            const evidence = `<span class="mp-badge mp-badge-${r.evidence.replace('_', '-')}">${MP_LABELS.evidence[r.evidence]}</span>`;
            const source = url ? ` <a href="${mpEscape(url)}" target="_blank" rel="noopener noreferrer">source</a>` : '';
            return `<tr>
                <td>${mpEscape(r.competitor.name)}</td>
                <td>${MP_LABELS.service[r.service_line]}</td>
                <td>${MP_LABELS.segment[r.segment]}</td>
                <td>${MP_LABELS.fee[r.fee_type]}</td>
                <td class="mp-num">${mpEscape(this.formatQuoted(r))}${r.notes ? `<div class="mp-muted mp-small">${mpEscape(r.notes)}</div>` : ''}</td>
                <td class="mp-num">${mpEscape(comparable)}</td>
                <td>${evidence}${source}</td>
                <td><span class="mp-nowrap">${mpEscape(r.run_date)}</span>${r.verified_via === 'search_extract' ? '<div class="mp-muted mp-small">via search excerpt</div>' : ''}${stale ? ' <span class="mp-tag mp-tag-warn">Stale</span>' : ''}</td>
            </tr>`;
        }).join('');
    }

    renderFootnote(latest) {
        const fx = latest.fx || {};
        const rates = ['KES', 'USD', 'EUR']
            .filter(c => fx['GBP_' + c])
            .map(c => `£1 = ${c} ${fx['GBP_' + c]}`)
            .join(', ');
        const src = mpSafeUrl(fx.source_url);
        this.root.querySelector('#mp-footnote').innerHTML =
            `All comparable figures are ex-VAT (UK ${this.vat.UK * 100}%, Kenya ${this.vat.KE * 100}% removed where a price includes it). Ranges use their midpoint for medians. ` +
            `Per-user prices are scaled to ${this.users.micro} users for micro/small and ${this.users.mid} for mid-market. ` +
            `Hourly and day rates are listed but left out of the medians. "Via search excerpt" means the price was read from a search result quoting the page, not from the page itself. Exchange rates for ${mpEscape(latest.run_date)}: ${mpEscape(rates || 'not recorded')}` +
            (src ? ` (<a href="${mpEscape(src)}" target="_blank" rel="noopener noreferrer">source</a>)` : '') + '.';
    }
}
