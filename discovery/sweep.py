#!/usr/bin/env python3
"""
Problem-framing SWEEP over the adopted Gather adapter (upwork-vibe).

Not "is there one job?" but "are many distinct companies paying for the same
painful thing?" — that cluster is the market signal. Runs several problem
framings, WIDE recall (title|description match, matchSkills OFF), dedupes across
framings on external_id, and writes one combined corpus that discover_score.py
can rank.

COST GUARD: upwork-vibe is ~$0.0035/job. This prints the projected max spend and
(unless --yes) makes you confirm before spending a cent. addons are OFF (they
returned nothing in the bake-off) so you're not paying the +$0.006/job.

Usage:
    export APIFY_TOKEN=apify_api_...           # FRESH token, env only
    python3 sweep.py --limit 40                # default framing set
    python3 sweep.py --limit 40 --framings framings.txt
    python3 sweep.py --limit 40 --yes          # skip the confirm prompt
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

APIFY_BASE = "https://api.apify.com/v2"
ACTOR_ID = "upwork-vibe~upwork-job-scraper"
COST_PER_JOB = 0.0035   # base output, addons off

# Default problem-framings. Deliberately span the AI-tractable ERP-adjacent
# wedges (migration/cleansing, doc->entry, integration glue) plus a couple of
# controls. Edit freely or pass --framings a file (one query per line).
DEFAULT_FRAMINGS = [
    "ERP data migration",
    "ERP data cleansing",
    "NetSuite implementation",
    "invoice data entry automation",
    "accounts payable automation",
    "ERP integration",
    "Salesforce NetSuite integration",
    "manual data entry spreadsheet",
]


def input_wide(query: str, limit: int) -> dict:
    """WIDE recall: match title OR description, skills OFF (recall first, gate later)."""
    return {
        "limit": limit,
        "includeKeywords.keywords": [query],
        "includeKeywords.matchTitle": True,
        "includeKeywords.matchDescription": True,
        "includeKeywords.matchSkills": False,
    }


def run_actor(actor_input: dict, token: str, timeout: int = 240) -> list:
    url = f"{APIFY_BASE}/acts/{ACTOR_ID}/run-sync-get-dataset-items"
    req = urllib.request.Request(
        url, data=json.dumps(actor_input).encode(), method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        parsed = json.loads(resp.read().decode())
    return parsed if isinstance(parsed, list) else parsed.get("items", [])


def ext_id(row: dict) -> str:
    return str(row.get("uid") or row.get("ciphertext") or row.get("externalLink") or "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=40, help="max jobs per framing")
    ap.add_argument("--framings", help="file with one problem-framing per line")
    ap.add_argument("--out", default="sweep_corpus.json")
    ap.add_argument("--yes", action="store_true", help="skip the cost-confirm prompt")
    args = ap.parse_args()

    framings = DEFAULT_FRAMINGS
    if args.framings:
        framings = [ln.strip() for ln in open(args.framings) if ln.strip()]

    max_jobs = len(framings) * args.limit
    max_cost = max_jobs * COST_PER_JOB
    print(f"Sweep: {len(framings)} framings x limit {args.limit} = up to {max_jobs} jobs")
    print(f"Projected MAX spend: ${max_cost:.2f}  (actual usually far less — recall rarely hits the cap)")
    for f in framings:
        print(f"   - {f}")

    token = os.environ.get("APIFY_TOKEN")
    if not token:
        sys.exit("\nAPIFY_TOKEN not set. export APIFY_TOKEN=apify_api_... (FRESH token, env only)")
    if not args.yes:
        if input("\nProceed and spend? [y/N] ").strip().lower() != "y":
            sys.exit("aborted — no spend.")

    # external_id -> {row, framings:[...]}  (dedupe across framings; track overlap)
    corpus, per_framing = {}, {}
    for q in framings:
        print(f"\n-> {q!r} ...", end=" ", flush=True)
        try:
            rows = run_actor(input_wide(q, args.limit), token)
        except urllib.error.HTTPError as e:
            print(f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:120]}")
            per_framing[q] = 0
            continue
        except Exception as e:  # noqa: BLE001
            print(f"ERROR: {e}")
            per_framing[q] = 0
            continue
        per_framing[q] = len(rows)
        print(f"{len(rows)} rows")
        for row in rows:
            eid = ext_id(row)
            if not eid:
                continue
            if eid in corpus:
                corpus[eid]["framings"].append(q)
            else:
                corpus[eid] = {"row": row, "framings": [q]}

    uniq = list(corpus.values())
    actual_jobs = sum(per_framing.values())
    print("\n" + "=" * 60)
    print(f"Pulled {actual_jobs} rows -> {len(uniq)} unique jobs "
          f"(~${actual_jobs * COST_PER_JOB:.2f} spent)")
    print("Per framing:")
    for q, n in per_framing.items():
        print(f"   {n:>3}  {q}")
    multi = [u for u in uniq if len(u["framings"]) > 1]
    print(f"\n{len(multi)} jobs matched >1 framing (cross-framing overlap = stronger cluster signal)")

    # Write a corpus shaped like the bake-off raw JSON so discover_score.py reads it
    # under the ACTOR_ID key, with sweep metadata attached per row.
    out_rows = []
    for u in uniq:
        r = dict(u["row"])
        r["_sweep_framings"] = u["framings"]
        out_rows.append(r)
    json.dump({ACTOR_ID: out_rows}, open(args.out, "w"), indent=2, default=str)
    print(f"\nCorpus -> {args.out}")
    print(f"Next:  python3 discover_score.py {args.out} --query \"<problem>\" --relevance keyword")


if __name__ == "__main__":
    main()
