# UAT Deploy — story 879

- **Version deployed**: 62534c32cc7ec866d120f6e6266e9d3039af718d (latest buildable main — full city loop incl. reorder feature, head-cancel UI, parse_id fixes, re-anchored specs; later main commits are docs-only and skip CI by paths filter)
- **Deployed at**: 2026-07-16T17:41:41Z via kamal deploy -d uat (GHA build succeeded)
- **Migrations**: bin/migrate run post-deploy — all up (incl. 20260716150000 production-item position).
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS at 2026-07-16T17:41:41Z; deployed version confirmed via kamal app version.
- **QA basis**: story 879 passed browser QA on 2026-07-16 (attempt recorded). Prod promotion deferred to the cycle-end release process.
