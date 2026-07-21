# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :broken_oaths, :scopes,
  user: [
    default: true,
    module: BrokenOaths.Users.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: BrokenOaths.UsersFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :broken_oaths,
  ecto_repos: [BrokenOaths.Repo],
  generators: [timestamp_type: :utc_datetime]

# WorldServer's 60s self-scheduled turn tick. Disabled in test so the
# deterministic `Game.advance_turn/1` (see BrokenOathsSpex.Fixtures) is
# the only tick source specs ever see.
config :broken_oaths, :game_auto_tick, true

# The in-progress feudal PvP batch (Siege player-city capture — story
# 906, Vassalization — story 907, Tribute — story 908) is built and
# wired into WorldServer, but still missing its Bank/Stewardship/
# first-class panels/QA/balance pass — this keeps it dormant anywhere
# this default isn't explicitly overridden. `config/dev.exs` and
# `config/test.exs` flip it on (full local play + the whole feudal
# test/spex suite); `config/prod.exs` leaves it `false`. Read via
# `BrokenOaths.Game.feudal_enabled?/0` — see that function's own doc
# for every entry point this single flag gates.
config :broken_oaths, :feudal_enabled, false

# Weather cloud shells on the globe (game board, world builder, and the
# airspace preview texture). Off by default — players found the drifting
# clouds confusing (they read as terrain/fog). Flip to `true` to bring them
# back. Read via `BrokenOaths.Worlds.Weather.enabled?/0`, which gates
# `Weather.map/3` to return no cloud levels when off.
config :broken_oaths, :weather_enabled, false

# Configure the endpoint
config :broken_oaths, BrokenOathsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BrokenOathsWeb.ErrorHTML, json: BrokenOathsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: BrokenOaths.PubSub,
  live_view: [signing_salt: "8WTTKExD"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :broken_oaths, BrokenOaths.Mailer, adapter: Swoosh.Adapters.Local

# OAuth integrations (cms_gen.integrations). Providers register here as
# they are generated.
config :broken_oaths, :integration_providers, [:codemyspec, :google]

config :broken_oaths, :codemyspec_url, "https://codemyspec.com"

# CodeMySpec is deliberately absent: feedback goes through the deploy
# key (BrokenOaths.Codemyspec.Client), never a per-user connection.
# It stays in :integration_providers above only so any historical
# integration rows still load.
config :broken_oaths, :oauth_providers, %{
  google: BrokenOaths.Integrations.Providers.Google
}

# Cloak vault for encrypted OAuth token storage.
# Dev/test key only — production must override via CLOAK_KEY in runtime.exs.
config :broken_oaths, BrokenOaths.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM,
       tag: "AES.GCM.V1", key: Base.decode64!("IakiNeC1WvqOVV4WKHRCCraKWKXip4iDyFI/Xs3Q1go=")}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  broken_oaths: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  broken_oaths: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
