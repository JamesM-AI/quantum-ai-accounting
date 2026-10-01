# Weekly competitor pricing update

This is the runbook for the scheduled Saturday run that refreshes the Market Pricing tab. It runs at 07:45 UK time so the update lands at about 8am. Edit this file to change what the run does. The schedule itself only says "follow docs/weekly-pricing-update.md".

## What the dashboard tracks

- Setup fees (one-off implementation or onboarding) and maintenance fees (monthly or annual support, retainers, managed service)
- Two service lines: `ai_implementation` and `managed_support`
- Two markets, kept separate: UK (`UK`) and Kenya (`KE`)
- Two client sizes: `micro` (1–49 staff) and `mid` (50–249 staff)

Data files:

- `data/competitors.json`: the firms tracked
- `data/pricing.json`: one entry in `runs` per Saturday, and every price observation ever recorded in `observations`

## Steps

1. **Start from main.** Run `git checkout main && git pull origin main`.

2. **Set today's run date** as `YYYY-MM-DD`. If a run for today already exists in `data/pricing.json`, stop. The job has already run.

3. **Re-check every active firm** (`active: true`). For each one, look for its current setup and maintenance prices for each service line and segment it covers.
   - Try the firm's own pricing pages first, then third-party sources: Clutch, GoodFirms, DesignRush, G-Cloud / Digital Marketplace listings (UK), and Kenyan agency directories.
   - If you can open the page, set `"verified_via": "page"`. If you can only see the price quoted in a search result, set `"verified_via": "search_extract"`.
   - Add a **new observation with today's `run_date`** for every price you confirmed this week, even when it hasn't changed. That is how the dashboard knows a price is still current.
   - If you could not confirm a price this week, do **not** copy last week's observation forward. Leave it. The dashboard flags it as "not re-verified", and after four weeks as stale.
   - Never edit or delete past observations. History drives the trend charts.

4. **Look for new comparable firms.** Find 1–3 per market that sell AI implementation or managed IT/AI support to small or mid-sized businesses, and preferably publish prices.
   - Skip any firm already in `competitors.json`, whether active or not.
   - Add each one with `"active": false, "pending_review": true`, a one-sentence `why_comparable`, and `added` set to today.
   - You may record observations for pending firms. They are shown in the "proposed" list but never counted until James approves them by setting `active: true` and `pending_review: false`.

5. **Exchange rates.** Find today's GBP→KES and GBP→USD mid-market rates. Add GBP→EUR only if a EUR price was recorded. Put them in the run's `fx` object with an https `source_url` and the rate `date`. The Central Bank of Kenya rates page is the preferred source for KES.

6. **Add the run entry** to `runs`:

   ```json
   {
     "run_date": "YYYY-MM-DD",
     "fx": { "GBP_KES": 0, "GBP_USD": 0, "source_url": "https://...", "date": "YYYY-MM-DD" },
     "summary": "One or two plain sentences: what changed, how many prices were confirmed, anything odd."
   }
   ```

7. **Validate.** Run `node scripts/validate-pricing.mjs`. Fix every error it reports and re-run it until it passes. Never commit data that fails.

8. **Commit and push to main.**

   ```
   git add data/
   git commit -m "Weekly pricing update YYYY-MM-DD"
   git push origin main
   ```

   Retry the push up to four times on network errors. Vercel redeploys automatically from main.

9. **Finish with a 2–3 line summary.** It is sent to James's phone, so lead with what matters. Cover any price moves of 10% or more, new proposed firms, and prices that could not be re-verified. If nothing changed, say so in one line.

## Observation format

```json
{
  "competitor_id": "kebab-case-id",
  "run_date": "YYYY-MM-DD",
  "service_line": "ai_implementation | managed_support",
  "segment": "micro | mid",
  "fee_type": "setup | maintenance",
  "low": 0,
  "high": 0,
  "currency": "GBP | KES | USD | EUR",
  "period": "one-off | monthly | annual | hourly | daily",
  "unit": "per_company | per_user",
  "vat_basis": "ex_vat | inc_vat | unknown",
  "evidence": "published | third_party | estimate",
  "verified_via": "page | search_extract",
  "source_url": "https://...",
  "notes": "Short. What the price covers, and any caveat."
}
```

## Rules

- **Never invent a number.**
  - `published` means the firm states the price itself.
  - `third_party` means another site states it, for example a Clutch minimum project size.
  - `estimate` is your own reasoned figure, and `notes` must explain its basis. Use it sparingly.
- **Ranges and floors.**
  - A single price uses the same value for `low` and `high`.
  - For a "from £X" price, set both to X and say "floor" in the notes.
  - A firm that states it charges no setup fee can be recorded with `low` and `high` at 0.
- **Per-user prices.** Use `unit: "per_user"` with the per-user figure. Do not pre-multiply. The dashboard scales per-user prices by the headcounts in `pricing.json` → `assumptions.users_per_segment`.
- **Rates.** Record hourly and day rates with `period: "hourly"` or `"daily"`. They are listed but kept out of the medians.
- **Kenya.** Record prices in KES where the firm quotes KES. Kenyan VAT is 16% and UK VAT is 20%. Set `vat_basis` only when the source states it.
- **Scope.** Do not change the dashboard code, the competitor approval flags, or the assumptions. Only James changes those.
