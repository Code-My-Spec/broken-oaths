# Follow-on Reddit post (no links — value-first)

> Draft. Voice = practitioner, not marketer. No links (the thread already burned you
> once on "looks like an ad" — let the value pull DMs instead). It's also deliberately
> structured for GEO: stat-backed, question subheads, self-contained answer blocks,
> a table — so the post itself becomes a citable source. Edit [brackets] to your truth.

---

**What actually moved the needle for getting cited by ChatGPT (follow-up to my plugin post)**

A bunch of you DM'd after my last post asking "how." Here's the no-tool, no-link version of what
actually worked, so you can do it by hand even if the plugin/MCP setup is too much friction.

First, why this is worth your time at all: AI referral traffic is up ~357% year over year,
ChatGPT is ~78% of it, and AI-referred visitors convert dramatically higher than Google organic
because they arrive pre-qualified by the model. And here's the part people miss — **traditional
SEO does not automatically get you cited.** The overlap between top Google results and AI-cited
sources has fallen from ~70% to under 20%. Ranking on Google ≠ getting quoted by ChatGPT. They're
different games now.

**Why isn't my site cited even though it ranks on Google?**
Usually one of three boring, fixable reasons:
1. The AI crawler can't read you. If your robots.txt blocks GPTBot / ClaudeBot / PerplexityBot, or
   your content is rendered client-side, you're invisible no matter how good you are. Check this first.
2. Your content isn't extractable. AI models pull self-contained answer blocks. A 150-ish word
   chunk that fully answers one question, under a heading phrased as that question, gets quoted.
   A wall of prose does not.
3. No structured data. Schema.org markup (FAQ, Article, Product) tells the model what your content
   *is* so it can attribute it to you.

**What concretely increased my citations**
The research backs this up (Princeton studied it) and it matched my experience — each of these
lifted AI visibility meaningfully:
- **Add statistics.** "Cut churn 30%" beats "reduces churn." Models quote numbers.
- **Cite your sources.** Counterintuitively, citing others makes YOU more citable.
- **Add expert quotes / named attribution.** Models prefer attributable claims.
- **Put comparisons in tables, never prose.** Models extract HTML tables almost verbatim:

| If you write it as | Gets cited? |
|---|---|
| A paragraph comparing your pricing tiers | Rarely |
| A clean table of tiers, prices, features | Often |

**Where do the citations actually come from?**
This surprised me: a big share of Perplexity/ChatGPT citations trace back to community Q&A —
Reddit and Quora — because those contain exact-match answers to the conversational questions people
type into AI. Which means a genuinely useful post like this one can itself become a source the
models quote. (Meta, I know.)

**The honest timeline:** this is not a quick fix. I submitted my first sitemap maybe two months
back and the daily referrals built gradually as the models recognized the domain as a reliable
source for [your topic]. Expect 6–12 weeks before it compounds, not days.

That's the whole playbook, no tooling required — crawler access, answer-block structure, schema,
stats/sources/tables, and showing up in the Q&A communities the models read. Happy to answer
specific questions in the comments.
