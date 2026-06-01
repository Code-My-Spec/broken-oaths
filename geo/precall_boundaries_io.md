# Pre-call brief — boundaries.io (GEO prospect)

*Recon: HTTP headers, robots.txt, sitemap, HTML inspection. June 2026. Verify live on call.*

## What they are
Geographic boundary-data API — ZIP/postal/neighborhood polygons in GeoJSON/TopoJSON
(USA/UK/Canada). 6+ yrs in production, 200+ teams, "multi-billion-dollar customers"
(Aptive, WebFX, PGI). Industries: home services, real estate, healthcare, logistics.
→ **Not a bootstrapper. They can pay. Price with confidence (high end: ~$1–1.5k/mo, not a $300 pilot).**

## Technographics (for scoping the integration)
- **Platform: Squarespace** (server header + squarespace-cdn assets). This is THE key fact.
- Content is **server-rendered HTML** (good — crawlable, not JS-walled).
- **Squarespace = constraint to flag:** limited control over schema injection, robots,
  page structure, and NO clean "colocated content / S3→R2 / Claude-plugin editorial
  workflow" play — that's for code-based sites. On Squarespace your value is on-page GEO
  (schema, answer blocks, content), not your full deploy pipeline. **Don't oversell the
  plumbing here; it doesn't fit their stack.** (If they have a separate docs site on a
  real framework, the workflow play lives there — ask.)
- No separate docs/developer subdomain detected — ask where their API docs live (likely
  the real GEO battleground for a dev-tools company).

## GEO readiness scorecard (what you'd actually fix — your pitch)
| Signal | State | Opportunity |
|---|---|---|
| AI crawler access (robots.txt) | ✅ Allowed (Squarespace default UA list has no Disallow) | Verify the privacy toggle live; confirm GPTBot/ClaudeBot not blocked |
| Sitemap | ✅ Present (200) | Fine |
| **Schema.org / JSON-LD** | ❌ **None detected** | **Biggest win.** Add Product/SoftwareApplication/FAQ schema → citability |
| **FAQ structured content** | ❌ Only a pricing-page link | Build real Q&A answer blocks for dev queries |
| Title tag | ✅ "Top GeoJson/TopoJson Postal Boundaries API" | Decent, keyword-aware |
| llms.txt | ❌ 404 | Minor / debated lever — don't lead with it (the "snake oil" comment) |

## The angle that closes (dev-tools GEO)
Their buyers ask LLMs developer questions — **"best API for ZIP code boundary GeoJSON,"
"postal code polygon API," "service area mapping data API," "how do I get neighborhood
boundaries."** Those queries now go to ChatGPT/Perplexity/Claude instead of Google. They
want to BE the cited answer. High-intent, high-conversion.

Dev-tools GEO levers (slightly different from content-marketing GEO):
- Structured API docs + comparison tables vs. alternatives (models extract tables verbatim)
- Schema markup (they have none — concrete, demonstrable gap)
- Real FAQ/answer blocks targeting the dev queries above
- Presence in dev Q&A sources LLMs cite (Stack Overflow, Reddit, GitHub)

## Call open (concrete, shows you looked)
> "I pulled up your site — you're on Squarespace, server-rendered, sitemap's fine, and
> AI crawlers can reach you, so the foundation's there. The biggest gap: you've got zero
> structured data, so when someone asks ChatGPT 'best API for ZIP code boundary GeoJSON,'
> nothing tells the model you're the answer. That plus real FAQ answer-blocks for your
> dev queries is where I'd start. Where do your API docs live — same site or separate?"

## Honest cautions
- Squarespace caps how deep the technical work can go — scope to on-page GEO + content,
  not your full editorial pipeline (unless docs are on a real framework).
- They're sophisticated (6+ yrs, big customers) — don't pitch "snake oil." Lead with the
  concrete schema gap you can SHOW, not buzzwords.
- Verify robots live: Squarespace has a one-click "block AI crawlers" toggle that would
  flip those UAs to Disallow. If it's on, fixing it is an instant visible win.
