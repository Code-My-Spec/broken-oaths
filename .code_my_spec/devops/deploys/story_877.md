# UAT Deploy — story 877

- **Version deployed**: 387a1c27fc2884ea675fdf101798c78300ffd7fa (branch tip; includes all batch-1 story code)
- **Deployed at**: 2026-07-15T01:31:04Z via kamal deploy -d uat (image ghcr.io/code-my-spec/broken_oaths, GHA build succeeded)
- **Health check verified**: YES — https://uat.broken-oaths.com/health returned HTTP 200 over valid TLS, checked at 2026-07-15T01:31:04Z immediately after the deploy finished ("Finished all in 22.1 seconds", deploy lock released cleanly).
- **Notes**: one UAT deploy covers stories 873-877 (they ship as a single build). Prod promotion deferred to the cycle-end release process.
