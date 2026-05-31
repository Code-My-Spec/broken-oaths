# Discovery pipeline

`discover(problem) -> Board`. A fuzzy problem in, one ranked KEEP/KILL/WATCH board
out. Every row is built to be killed by one click: the money cell is verifiable, and
the LLM is never the source of truth. Validation is FIXED; the data strategy is
VARIABLE (currently Upwork job postings).

Stages: Frame → Gather → Cluster → Score → Red-team. Each emits a typed record.

## Files

- `upwork_actor_bakeoff.py` — Gather harness. `NormalizedRecord` is the contract;
  `map_*` are the adapters. Adopted adapter: `upwork-vibe~upwork-job-scraper`
  (pay-per-result, client stats in base output; addons OFF — they returned nothing).
- `discover_score.py` — the fixed validation engine. Money + relevance → board.
- `bakeoff_v3_raw.json` — sample Gather output (3 upwork-vibe rows + 15 devcake).

## Money gate (axis 1)

NOT the job budget (garbage on Upwork: fixed=0 or $5–30/hr). It's the client's
demonstrated `totalSpent` GATED by `hireRate` — high spend + low hire rate =
posts widely, hires rarely = noise. Tune `HIRE_RATE_GATE`, `SPEND_STRONG` per run.

## Relevance (axis 2)

- `--relevance keyword` — token-overlap heuristic, no API key. Scores everything ~1.0;
  does no discriminating (money carries the decision).
- `--relevance llm` — Anthropic judgment on intent + adjacency (e.g. knows "EAM
  consulting" is ERP-adjacent but not ERP reporting). **Needs `ANTHROPIC_API_KEY`.**
  Batched, cached in `relevance_cache.json` so reruns don't re-pay.

## Run

```bash
# token-free baseline
python3 discover_score.py bakeoff_v3_raw.json --query "erp reporting"

# LLM relevance (export ANTHROPIC_API_KEY first)
python3 discover_score.py bakeoff_v3_raw.json --query "erp reporting" --relevance llm

# re-pull at volume (export a FRESH APIFY_TOKEN first; never inline)
python3 upwork_actor_bakeoff.py "erp reporting" --limit 100
```

## Credentials

Both are environment variables, never inline:
- `APIFY_TOKEN` — Gather (re-pull). Rotate if ever exposed.
- `ANTHROPIC_API_KEY` — `--relevance llm`.

## Open / next

- Loosen keyword match + `limit 100` for a real corpus (recall first, gate second).
- Red-team stage: per KEEP, LLM argues against it from the same evidence.
- Dedupe across runs on `external_id`; `--query` sweep over several framings.
