# UAT Deploy — story 880

- **Version deployed**: 62534c32cc7ec866d120f6e6266e9d3039af718d (main tip — city loop complete: reorder feature, head-cancel UI, parse_id button fixes, 9 re-anchored specs; 69/69 spex, 439 unit tests)
- **Deployed at**: 2026-07-16T15:45:07Z via kamal deploy -d uat (GHA build succeeded on main)
- **Migrations**: run post-deploy via kamal app exec "bin/migrate" — 20260716150000 (production item position column) applied.
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS at 2026-07-16T15:45:07Z, after deploy + migrate ("Finished all in 23.0 seconds", lock released cleanly).
- **QA basis**: story 880 passed its browser QA session on 2026-07-16. Prod promotion deferred to the cycle-end release process.
