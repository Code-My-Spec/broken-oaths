#!/usr/bin/env python3
"""
Discovery scorer  —  the fixed validation engine.

Takes Gather output (upwork-vibe raw JSON) and produces a KEEP / KILL / WATCH
board. Two axes, deliberately separated:

  1. MONEY  — the gate. NOT the job budget (garbage on Upwork). It's the client's
              demonstrated spend, GATED by hire rate so tire-kickers don't pass:
              high spend + low hire rate = posts widely, hires rarely = noise.
  2. RELEVANCE — is the posting actually about the problem?
                 --relevance keyword : token-overlap heuristic (no API key needed).
                 --relevance llm     : Anthropic judgment on intent + adjacency.

A row is KEEP only if it clears BOTH. This is what stops the pipeline lying to you:
the highest-spend row in this dataset is off-topic, and the engine must knock it down.

Run (token-free, keyword relevance):
    python3 discover_score.py bakeoff_v3_raw.json --query "erp reporting"

Run (LLM relevance — needs ANTHROPIC_API_KEY in env):
    python3 discover_score.py bakeoff_v3_raw.json --query "erp reporting" --relevance llm
"""

import argparse
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# --------------------------------------------------------------------------- #
# Tunable thresholds. These ARE the human judgment calls — set per run.
# --------------------------------------------------------------------------- #
HIRE_RATE_GATE = 40      # below this %, a client is a tire-kicker regardless of spend
SPEND_STRONG = 5000      # USD lifetime spend to count as a proven, paying client
RELEVANCE_KEEP = 0.75    # at/above: on-topic
RELEVANCE_FLOOR = 0.25   # below: off-topic -> KILL on relevance alone

# LLM relevance config
ANTHROPIC_MODEL = "claude-sonnet-4-6"   # quality on the deciding axis; haiku for $ at volume
ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
CACHE_PATH = "relevance_cache.json"     # avoid re-paying for the same (id, query, model)

RELEVANCE_SYSTEM = (
    "You judge whether an Upwork job posting describes a client who is actually "
    "suffering from — or seeking help with — a specific PROBLEM. Judge intent and "
    "ADJACENCY, not keyword overlap. Examples: 'EAM (enterprise asset management) "
    "consulting' is adjacent to 'ERP reporting' and should score moderately-high; a "
    "posting that merely name-drops a term but is really about something else scores "
    "low. Respond with ONLY a JSON object, no prose: "
    '{"score": <float 0..1>, "reason": "<=12 words"}. '
    "score>=0.75 = clearly on-topic; <0.25 = off-topic."
)


# --------------------------------------------------------------------------- #
# Normalize the adopted adapter's (upwork-vibe) raw rows to what Score needs.
# Mirrors map_upwork_vibe from the bake-off harness.
# --------------------------------------------------------------------------- #
def normalize_vibe(row: dict) -> dict:
    b = row.get("budget") or {}
    hr = b.get("hourlyRate") or {}
    fixed = b.get("fixedBudget")
    if hr.get("min") or hr.get("max"):
        budget_raw = f"${hr.get('min','?')}-${hr.get('max','?')}/hr"
    elif fixed:
        budget_raw = f"${fixed} fixed"
    else:
        budget_raw = None
    client = row.get("client") or {}
    stats = client.get("stats") or {}
    return {
        "external_id": str(row.get("uid") or row.get("ciphertext") or ""),
        "title": row.get("title", ""),
        "url": row.get("externalLink", ""),
        "text": " ".join(filter(None, [row.get("title", ""), row.get("description", "")])),
        "skills": row.get("skills") or [],
        "budget_raw": budget_raw,
        "total_spent": stats.get("totalSpent"),
        "total_hires": stats.get("totalHires"),
        "hire_rate": stats.get("hireRate"),
        "verified": client.get("paymentMethodVerified"),
    }


# --------------------------------------------------------------------------- #
# Axis 1: money. Returns (tier, human note). tier in strong|thin|noise|unknown.
# --------------------------------------------------------------------------- #
def money_signal(rec: dict):
    spent, hire = rec["total_spent"], rec["hire_rate"]
    if spent is None or hire is None:
        return "unknown", "no client signal in record — cannot gate on money"
    if hire < HIRE_RATE_GATE:
        return "noise", f"${spent:,.0f} spent but only {hire}% hire rate — posts widely, hires rarely"
    if spent >= SPEND_STRONG:
        return "strong", f"${spent:,.0f} spent at {hire}% hire rate — demonstrated, converting spend"
    return "thin", f"serious client ({hire}% hire) but only ${spent:,.0f} spent — willingness-to-pay unproven"


# --------------------------------------------------------------------------- #
# Axis 2a: relevance — keyword heuristic (no token).
# --------------------------------------------------------------------------- #
def relevance_keyword(rec: dict, terms: list):
    haystack = (rec["text"] + " " + " ".join(rec["skills"])).lower()
    hits = [t for t in terms if t.lower() in haystack]
    score = len(hits) / len(terms) if terms else 0.0
    missing = [t for t in terms if t not in hits]
    note = "matches all query terms" if not missing else f"missing term(s): {', '.join(missing)}"
    return score, note


# --------------------------------------------------------------------------- #
# Axis 2b: relevance — LLM (intent + adjacency). stdlib-only Anthropic call.
# --------------------------------------------------------------------------- #
def _anthropic(user: str, model: str, max_tokens: int = 200) -> str:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise SystemExit("ANTHROPIC_API_KEY not set — required for --relevance llm.")
    body = json.dumps({
        "model": model, "max_tokens": max_tokens, "system": RELEVANCE_SYSTEM,
        "messages": [{"role": "user", "content": user}],
    }).encode()
    req = urllib.request.Request(
        ANTHROPIC_URL, data=body, method="POST",
        headers={"content-type": "application/json", "x-api-key": key,
                 "anthropic-version": "2023-06-01"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read())
    return "".join(blk.get("text", "") for blk in payload.get("content", []))


def _parse_relevance(text: str):
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return 0.0, f"unparseable LLM reply: {text[:60]}"
    try:
        obj = json.loads(m.group(0))
        score = float(obj.get("score", 0.0))
        return max(0.0, min(1.0, score)), str(obj.get("reason", "")).strip()
    except (ValueError, TypeError):
        return 0.0, f"bad JSON from LLM: {text[:60]}"


def relevance_llm(rec: dict, query: str, model: str, cache: dict):
    ckey = f"{rec['external_id']}|{query}|{model}"
    if ckey in cache:
        c = cache[ckey]
        return c["score"], c["reason"]
    user = (
        f"PROBLEM: {query}\n\n"
        f"JOB TITLE: {rec['title']}\n"
        f"SKILLS: {', '.join(map(str, rec['skills']))}\n"
        f"DESCRIPTION:\n{rec['text'][:1800]}\n\n"
        "Return ONLY the JSON object."
    )
    score, reason = _parse_relevance(_anthropic(user, model))
    cache[ckey] = {"score": score, "reason": reason}
    return score, reason


# --------------------------------------------------------------------------- #
# Combine the two axes into a verdict + the strongest kill-argument.
# --------------------------------------------------------------------------- #
def verdict(money_tier: str, rel_score: float, money_note: str, rel_note: str):
    off_topic = rel_score < RELEVANCE_FLOOR
    on_topic = rel_score >= RELEVANCE_KEEP

    if off_topic:
        return "KILL", f"off-topic ({rel_note}) — even at strong money it's the wrong problem"
    if money_tier == "noise":
        return "KILL", money_note
    if money_tier == "unknown":
        return "WATCH", money_note
    if money_tier == "strong" and on_topic:
        return "KEEP", "single posting — could be one-off, not recurring demand; confirm with >1 source"
    if money_tier == "thin":
        return "WATCH", money_note
    return "WATCH", f"borderline relevance ({rel_note}) despite {money_note}"


ORDER = {"KEEP": 0, "WATCH": 1, "KILL": 2}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", help="bake-off raw JSON")
    ap.add_argument("--query", default="erp reporting", help="problem terms, space-separated")
    ap.add_argument("--actor-key", default="upwork-vibe~upwork-job-scraper")
    ap.add_argument("--relevance", choices=["keyword", "llm"], default="keyword",
                    help="relevance axis: keyword heuristic (no key) or LLM (needs ANTHROPIC_API_KEY)")
    ap.add_argument("--model", default=ANTHROPIC_MODEL, help="Anthropic model for --relevance llm")
    ap.add_argument("--workers", type=int, default=8, help="concurrent LLM calls")
    ap.add_argument("--out", default="scored_board.json")
    args = ap.parse_args()

    terms = args.query.split()
    data = json.load(open(args.path))
    rows = data.get(args.actor_key)
    if not rows:
        sys.exit(f"no rows under key {args.actor_key!r}. keys present: {list(data)}")

    recs = [normalize_vibe(row) for row in rows]

    # Relevance pass (batched for the LLM path).
    if args.relevance == "llm":
        cache = json.load(open(CACHE_PATH)) if os.path.exists(CACHE_PATH) else {}
        def score_one(rec):
            return relevance_llm(rec, args.query, args.model, cache)
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            rels = list(ex.map(score_one, recs))
        json.dump(cache, open(CACHE_PATH, "w"), indent=2)
    else:
        rels = [relevance_keyword(rec, terms) for rec in recs]

    scored = []
    for rec, (r_score, r_note) in zip(recs, rels):
        m_tier, m_note = money_signal(rec)
        v, kill = verdict(m_tier, r_score, m_note, r_note)
        scored.append({
            "verdict": v, "title": rec["title"], "url": rec["url"],
            "money_tier": m_tier, "money_note": m_note,
            "relevance": round(r_score, 2), "relevance_note": r_note,
            "kill_argument": kill,
            "spent": rec["total_spent"], "hire_rate": rec["hire_rate"],
        })

    scored.sort(key=lambda s: (ORDER[s["verdict"]], -(s["spent"] or 0)))

    print(f"\nQuery: {args.query!r}  |  relevance: {args.relevance}"
          f"{' (' + args.model + ')' if args.relevance == 'llm' else ''}")
    print(f"gate: hire>={HIRE_RATE_GATE}%, spend>=${SPEND_STRONG:,}, "
          f"relevance keep>={RELEVANCE_KEEP}/floor<{RELEVANCE_FLOOR}\n")
    print(f"{'VERDICT':<7} {'MONEY':<7} {'REL':<5} TITLE")
    print("-" * 78)
    for s in scored:
        print(f"{s['verdict']:<7} {s['money_tier']:<7} {s['relevance']:<5} {s['title'][:54]}")
        print(f"        └─ {s['kill_argument']}")
        if s["relevance_note"]:
            print(f"        └─ relevance: {s['relevance_note']}")
    print("-" * 78)
    tally = {v: sum(1 for s in scored if s["verdict"] == v) for v in ("KEEP", "WATCH", "KILL")}
    print(f"{tally['KEEP']} KEEP · {tally['WATCH']} WATCH · {tally['KILL']} KILL")

    json.dump(scored, open(args.out, "w"), indent=2)
    print(f"\nFull board -> {args.out}")


if __name__ == "__main__":
    main()
