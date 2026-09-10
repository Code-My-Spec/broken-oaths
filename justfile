# Broken Oaths — project tooling.
#
# `restart` is the seam CodeMySpec's promotion uses. `CodeMySpec.Promotion`
# gates this checkout, merges the promoting copy's branch into the checkout the
# application runs from, and then calls `just restart` here to bring the app up
# on the merged code. Without it the promotion merges and stops, correctly
# reporting that the app is still serving what it was.

# Rebuild if needed, restart the app, and report the revision it is serving.
restart port="4050":
    #!/usr/bin/env bash
    set -euo pipefail

    # Resolved rather than assumed: the app runs from the *main* checkout, and
    # a promotion is invoked by an agent standing in a worktree of it.
    # `--git-common-dir` resolves to the main checkout's `.git` from inside any
    # worktree, which is what makes this runnable from either.
    main="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
    echo "→ main checkout: $main"

    # Asking whether the build is *satisfiable*, not whether anything moved.
    # A lock that advanced without its deps being fetched turns into "Unchecked
    # dependencies" on the next mix invocation, which analyzers report as
    # findings rather than as an environment problem. `loadpaths` is the cheap
    # way to ask — it is what every mix task runs first.
    if ! ( cd "$main" && mix loadpaths >/dev/null 2>&1 ); then
        echo "→ deps do not satisfy mix.exs — fetching and recompiling"
        ( cd "$main" && mix deps.get && mix deps.compile )
    fi

    # By port, not by name: several beams run on this machine and only one of
    # them is serving {{port}}.
    pid="$(lsof -nP -iTCP:{{port}} -sTCP:LISTEN -t || true)"
    if [ -n "$pid" ]; then
        echo "→ stopping $pid on {{port}}"
        kill "$pid"
        for _ in $(seq 1 30); do
            lsof -nP -iTCP:{{port}} -sTCP:LISTEN -t >/dev/null 2>&1 || break
            sleep 1
        done
    fi

    # Migrations, after the old server is down and before the new one is up.
    # `Phoenix.Ecto.CheckRepoStatus` refuses *every request* with
    # `PendingMigrationError` while the dev database is behind, so a promotion
    # that shipped a migration and did not run it leaves the app answering 500
    # to everything — including whatever QA is about to point at it.
    #
    # After the kill, because a `mix` invocation takes the build lock and that
    # is what stalls a running server.
    echo "→ migrations"
    ( cd "$main" && mix ecto.migrate )

    # Outside the repository, deliberately.
    #
    # A log written into the tree makes it dirty, and a dirty tree is exactly
    # what `code_on_running_copy` refuses on — so a restart that logged here
    # would block the next promotion by having run.
    log="$HOME/.codemyspec/broken_oaths_{{port}}.restart.log"
    mkdir -p "$(dirname "$log")"
    mv -f "$log" "$log.1" 2>/dev/null || true

    # `</dev/null` matters as much as the output redirect. Without it the server
    # inherits the caller's stdin, and a caller that waits for every writer to
    # close — a CI step, an agent's shell tool, the promotion itself — hangs for
    # its whole timeout on a recipe that has already exited.
    ( cd "$main" && exec </dev/null >"$log" 2>&1; PORT={{port}} nohup mix phx.server & )
    echo "→ starting, logging to $log"

    # A short wait, not a long one. The server is already detached — this poll
    # only exists so the common case can say "it came up" instead of "go and
    # check". Holding longer is least useful exactly when something is wrong:
    # the answer is in the log, and the caller cannot read it while waiting.
    for _ in $(seq 1 10); do
        if curl -sS -o /dev/null --max-time 2 "http://localhost:{{port}}/" 2>/dev/null; then
            echo "✓ {{port}} is answering on $(git -C "$main" rev-parse --short HEAD)"
            up=1
            break
        fi
        sleep 2
    done

    if [ "${up:-0}" != "1" ]; then
        echo "→ still starting after 20s — it is detached and may yet come up."
        echo "  check:  curl -s -o /dev/null -w '%{http_code}' localhost:{{port}}"
        echo "  or why: tail -20 $log"
        exit 1
    fi
