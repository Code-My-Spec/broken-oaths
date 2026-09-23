import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Pin the weather epoch so cloud maps (and cached airspace textures) are
# deterministic in tests regardless of wall clock.
config :broken_oaths, :weather_epoch, 0

# Clouds ship OFF (config/config.exs — players found them confusing), but the
# weather mechanic still needs coverage: keep them ON in test so the weather/
# airspace/texture tests and the story-876 cloud spex exercise real cloud maps.
config :broken_oaths, :weather_enabled, true

# Configure your database
#
# MIX_TEST_PARTITION gives built-in test partitioning in CI — run
# `mix help test` for more.
#
# A linked git worktree shares this machine's database server. Running the
# suite in one migrates the database every other checkout is using, from
# whatever branch that one happens to be on. The symptoms never name the
# cause: undefined modules first, then NOT NULL violations on columns the
# code has never heard of, as the schema shifts under successive runs.
#
# These databases are disposable and nothing sweeps them: `mix ecto.drop`
# in a worktree you are finished with.
#
# The recorded name wins over everything except the analyzer's own
# sub-partition. `mix cms.harness.onboard` writes it into
# `.claude/settings.local.json`, and that file is the answer — read here
# rather than taken from the environment, because the variable only
# reaches a process Claude Code exported it into. Anything else that runs
# the suite (an analyzer, a script, a shell you opened yourself) got a
# different database from the same checkout, and the two disagreed about
# the schema without either of them being wrong.
#
# Read as text rather than through a library: config runs before deps are
# loaded, so there is nothing to call yet.
recorded_partition =
  with {:ok, contents} <-
         File.read(Path.join(File.cwd!(), ".claude/settings.local.json")),
       [_, value] <-
         Regex.run(~r/"MIX_TEST_PARTITION"\s*:\s*"([^"]+)"/, contents) do
    value
  else
    _ -> nil
  end

requested_partition = System.get_env("MIX_TEST_PARTITION")

# The one environment value allowed to win over the recorded one. A
# harness analyzer gives its exunit and spex sweeps their own database by
# appending a letter to this copy's own recorded partition (an "a" for
# exunit, an "s" for spex), and MIX_TEST_PARTITION is the only channel it
# has to say so. Recorded-first, full stop, silently drops that suffix and
# collapses both sweeps and an interactive mix test onto one database — a
# sweep truncating under the suite still using it.
#
# Narrow on purpose: not "an environment value" but "the recorded value
# plus one suffix" — a name that can only describe *this* working copy. A
# value inherited from another worktree cannot match, and still loses.
own_sub_partition? =
  is_binary(recorded_partition) and is_binary(requested_partition) and
    requested_partition in [recorded_partition <> "a", recorded_partition <> "s"]

# In a linked worktree `.git` is a file pointing at the real git dir rather
# than a directory. The primary checkout keeps the bare name.
partition =
  cond do
    own_sub_partition? ->
      requested_partition

    recorded_partition ->
      recorded_partition

    requested_partition ->
      requested_partition

    File.regular?(Path.join(File.cwd!(), ".git")) ->
      "_" <> Path.basename(File.cwd!())

    true ->
      ""
  end

config :broken_oaths, BrokenOaths.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "broken_oaths_test#{partition}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :broken_oaths, BrokenOathsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "5KZv12OoGA3TSCAcwIqn3WaybGOuPJbow6VvDQNEHOoxsjtp1lLzYSRgma1qRpQO",
  server: false

# In test we don't send emails
config :broken_oaths, BrokenOaths.Mailer, adapter: Swoosh.Adapters.Test

# Don't pre-build the full-size globe mesh; tests use small frequencies
config :broken_oaths, :globe_warmup, false

# Specs drive turns deterministically via Game.advance_turn/1; a live
# timer would race the sandbox connection after a test's owner stops.
config :broken_oaths, :game_auto_tick, false

# Tiny impostor textures keep texture tests fast
config :broken_oaths, :texture_size, {128, 64}

# Mirrors `config/dev.exs` — mounts the same dev-only routes (including
# `BrokenOathsWeb.DevQaController`'s QA control surface) so
# `router.ex`'s `Application.compile_env(:broken_oaths, :dev_routes)`
# gate is actually exercisable by `ConnCase` tests. Still never set in
# `config/prod.exs`, so the gate keeps the routes out of a prod build.
config :broken_oaths, dev_routes: true

# Mirrors `config/dev.exs` — the whole feudal PvP batch (Siege/
# Vassalization/Tribute, stories 906-908) stays fully exercisable by
# `siege_test`/`vassalage_test`/`tribute_test`/`vassalization_test`
# and the `test/spex/906|907|908` suites. Still `false` by default
# (`config/config.exs`) and explicitly `false` in `config/prod.exs`,
# so the batch stays dormant there. See `BrokenOaths.Game.
# feudal_enabled?/0`.
config :broken_oaths, :feudal_enabled, true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
