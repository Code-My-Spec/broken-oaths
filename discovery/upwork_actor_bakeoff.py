#!/usr/bin/env python3
import argparse, json, os, sys, urllib.error, urllib.request
from dataclasses import dataclass, field
from typing import Any, Callable, Optional
APIFY_BASE = "https://api.apify.com/v2"

@dataclass
class NormalizedRecord:
    source: str; external_id: str; url: str; raw_text: str
    posted_date: Optional[str] = None
    money_attached: bool = False
    budget_raw: Optional[str] = None
    client_hires: Optional[int] = None
    client_total_spent: Optional[str] = None
    client_verified: Optional[bool] = None
    skills: list = field(default_factory=list)
    proposal_count: Optional[int] = None
    theme_tags: list = field(default_factory=list)

MEASURED_FIELDS = ["url","raw_text","posted_date","money_attached","budget_raw",
    "client_hires","client_total_spent","client_verified","skills","proposal_count"]

def first(d, *keys, default=None):
    for k in keys:
        cur=d; ok=True
        for part in k.split("."):
            if isinstance(cur,dict) and part in cur and cur[part] is not None: cur=cur[part]
            else: ok=False; break
        if ok and cur not in (None,"",[],{}): return cur
    return default
def to_int(v):
    if v is None: return None
    try: return int(float(str(v).replace(",","").strip()))
    except (ValueError,TypeError): return None
def join_text(*p): return "\n\n".join(str(x).strip() for x in p if x)

def map_devcake(row):
    budget=first(row,"budget","budgetRange","hourlyRate")
    return NormalizedRecord(source="apify:devcake",
        external_id=str(first(row,"id","jobId","url",default="")),
        url=first(row,"url","jobUrl",default=""),
        raw_text=join_text(first(row,"title"),first(row,"description")),
        posted_date=first(row,"publishTime","postedDate","createdAt"),
        money_attached=bool(budget), budget_raw=budget,
        client_hires=to_int(first(row,"client.totalHires","clientHires","client.hires")),
        client_total_spent=first(row,"client.totalSpent","clientTotalSpent","client.spent"),
        client_verified=first(row,"client.verified","clientVerified","client.paymentVerified"),
        skills=first(row,"skills",default=[]) or [],
        proposal_count=to_int(first(row,"proposals","proposalCount","totalApplicants")))

def map_upwork_vibe(row):
    fixed=first(row,"budget.fixedBudget"); hr_min=first(row,"budget.hourlyRate.min"); hr_max=first(row,"budget.hourlyRate.max")
    if hr_min or hr_max: budget=f"${hr_min or '?'}-${hr_max or '?'}/hr"
    elif fixed: budget=f"${fixed} fixed"
    else: budget=None
    return NormalizedRecord(source="apify:upwork-vibe",
        external_id=str(first(row,"uid","ciphertext",default="")),
        url=first(row,"externalLink",default=""),
        raw_text=join_text(first(row,"title"),first(row,"description")),
        posted_date=first(row,"createdAt"),
        money_attached=bool(budget), budget_raw=budget,
        client_hires=to_int(first(row,"client.stats.totalHires")),
        client_total_spent=first(row,"client.stats.totalSpent"),
        client_verified=first(row,"client.paymentMethodVerified"),
        skills=first(row,"skills",default=[]) or [],
        proposal_count=to_int(first(row,"activity.totalApplicants")))

def map_generic(source):
    def _m(row):
        budget=first(row,"budget","budgetRange","hourlyRate","amount","price","rate")
        return NormalizedRecord(source=source,
            external_id=str(first(row,"id","jobId","uid","url",default="")),
            url=first(row,"url","jobUrl","link",default=""),
            raw_text=join_text(first(row,"title","name","jobTitle"),first(row,"description","desc","snippet","jobDescription")),
            posted_date=first(row,"publishTime","postedDate","createdAt","publishedDate","datePosted"),
            money_attached=bool(budget), budget_raw=budget,
            client_hires=to_int(first(row,"client.totalHires","clientHires","client.hires","client.pastHires","buyer.totalHires","totalHires")),
            client_total_spent=first(row,"client.totalSpent","clientTotalSpent","client.spent","buyer.totalSpent","totalSpent"),
            client_verified=first(row,"client.verified","clientVerified","client.paymentVerified","buyer.paymentVerified","paymentVerified"),
            skills=first(row,"skills","tags","categories",default=[]) or [],
            proposal_count=to_int(first(row,"proposals","proposalCount","totalApplicants","applicants")))
    return _m

def input_devcake(q,l): return {"searchQueries":[q],"maxItems":l,"sort":"recency+desc"}
def input_upwork_vibe(q,l): return {"limit":l,"includeKeywords.keywords":[q],"includeKeywords.matchTitle":True,"includeKeywords.matchDescription":True,"includeKeywords.matchSkills":True,"addons.enableClientDetails":True,"addons.enableClientActivity":True}
def input_queries(q,l): return {"queries":[q],"maxItems":l}
def input_keyword(q,l): return {"keyword":q,"maxResults":l}

ACTORS=[
    {"id":"upwork-vibe~upwork-job-scraper","input":input_upwork_vibe,"map":map_upwork_vibe},
    {"id":"jupri~upwork","input":input_queries,"map":map_generic("apify:jupri")},
    {"id":"devcake~upwork-jobs-scraper","input":input_devcake,"map":map_devcake},
]

def run_actor(actor_id, actor_input, token, timeout=180):
    url=f"{APIFY_BASE}/acts/{actor_id}/run-sync-get-dataset-items"
    req=urllib.request.Request(url,data=json.dumps(actor_input).encode(),method="POST",
        headers={"Content-Type":"application/json","Authorization":f"Bearer {token}"})
    with urllib.request.urlopen(req,timeout=timeout) as resp: body=resp.read().decode()
    parsed=json.loads(body)
    return parsed if isinstance(parsed,list) else parsed.get("items",[])

def completeness(records):
    n=len(records); out={}
    for f in MEASURED_FIELDS:
        if n==0: out[f]=(0,0.0); continue
        filled=0
        for r in records:
            v=getattr(r,f)
            if f=="money_attached": filled+=1 if v else 0
            elif v not in (None,"",[],{}): filled+=1
        out[f]=(filled,100.0*filled/n)
    return out

def print_report(results, out=sys.stdout):
    actor_ids=list(results.keys()); col_w=max(22,*(len(a) for a in actor_ids))+2
    p=lambda s: print(s,file=out)
    p("\n"+"="*(22+col_w*len(actor_ids)))
    p("FIELD COMPLETENESS  (% of records with the field populated)")
    p("="*(22+col_w*len(actor_ids)))
    header=f"{'field':<22}"+"".join(f"{a:<{col_w}}" for a in actor_ids); p(header); p("-"*len(header))
    counts={a:len(results[a]["records"]) for a in actor_ids}
    p(f"{'records returned':<22}"+"".join(f"{str(counts[a]):<{col_w}}" for a in actor_ids))
    comps={a:completeness(results[a]["records"]) for a in actor_ids}
    for f in MEASURED_FIELDS:
        marker="  <-- the bet" if f=="client_hires" else ""
        cells="".join(f"{f'{comps[a][f][1]:5.0f}% ({comps[a][f][0]})':<{col_w}}" for a in actor_ids)
        p(f"{f:<22}{cells}{marker}")
    p("-"*len(header))
    for a in actor_ids:
        err=results[a].get("error")
        if err: p(f"  {a}: ERROR -> {err}")

def print_raw_keys(actor_id, raw, out=sys.stdout):
    if not raw: print(f"  [{actor_id}] returned 0 rows -- check the input builder.",file=out); return
    print(f"  [{actor_id}] first-row keys: {sorted(raw[0].keys())}",file=out)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("query"); ap.add_argument("--limit",type=int,default=15)
    ap.add_argument("--dump",default="bakeoff_raw.json")
    args=ap.parse_args()
    token=os.environ.get("APIFY_TOKEN")
    if not token: sys.exit("APIFY_TOKEN env var not set.")
    results={}; raw_dump={}
    for actor in ACTORS:
        aid=actor["id"]; print(f"\n-> running {aid}  (query={args.query!r}, limit={args.limit}) ...")
        try:
            raw=run_actor(aid,actor["input"](args.query,args.limit),token)
            raw_dump[aid]=raw; print_raw_keys(aid,raw)
            results[aid]={"records":[actor["map"](r) for r in raw]}
        except urllib.error.HTTPError as e:
            msg=f"HTTP {e.code}: {e.read().decode('utf-8','replace')[:200]}"
            results[aid]={"records":[],"error":msg}; print(f"  ! {msg}")
        except Exception as e:
            results[aid]={"records":[],"error":str(e)}; print(f"  ! {e}")
    print_report(results)
    with open(args.dump,"w") as fh: json.dump(raw_dump,fh,indent=2,default=str)
    # also dump normalized records for artifact building
    norm={a:[r.__dict__ for r in results[a]["records"]] for a in results}
    with open(args.dump.replace(".json","_normalized.json"),"w") as fh: json.dump(norm,fh,indent=2,default=str)
    print(f"\nRaw -> {args.dump}")

if __name__=="__main__": main()
