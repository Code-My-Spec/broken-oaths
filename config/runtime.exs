import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/broken_oaths start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :broken_oaths, BrokenOathsWeb.Endpoint, server: true
end

config :broken_oaths, BrokenOathsWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4050"))]

# === Secret loading ==========================================================
#
# Deployed containers (UAT + prod, both MIX_ENV=prod) carry only AWS
# bootstrap creds + APP_ENV; every app secret is fetched from SSM
# Parameter Store (/broken_oaths/<APP_ENV>/*) into System env here,
# BEFORE any config below reads it. Local dev/test never set APP_ENV.
if config_env() == :prod do
  case System.get_env("APP_ENV") do
    nil -> :ok
    app_env -> BrokenOaths.Secrets.load!(app_env)
  end
end

# Local dev convenience: load .env into System env so optional
# integrations (CodeMySpec feedback widget, Google OAuth) work without
# exporting vars by hand. Existing env vars win; test never loads it.
if config_env() == :dev and File.exists?(".env") do
  ".env"
  |> File.read!()
  |> String.split("\n")
  |> Enum.each(fn line ->
    with [key, value] <- String.split(String.trim(line), "=", parts: 2),
         false <- String.starts_with?(key, "#"),
         nil <- System.get_env(key) do
      System.put_env(key, String.trim(value, "\""))
    else
      _ -> :ok
    end
  end)
end

# CodeMySpec credentials. The deploy key comes from the project page at
# codemyspec.com and self-identifies the project — it authenticates the
# support widget socket (chat + report a problem) and the registered-users
# endpoint CodeMySpec pulls from. Deployed envs read it from SSM (loaded
# above), dev reads it from .env.
config :broken_oaths,
  codemyspec_url: System.get_env("CODEMYSPEC_URL") || "https://codemyspec.com",
  codemyspec_widget_url:
    System.get_env("CODEMYSPEC_WIDGET_URL") || "wss://codemyspec.com/widget",
  deploy_key: System.get_env("CODEMYSPEC_DEPLOY_KEY"),
  codemyspec_client_id: System.get_env("CODEMYSPEC_CLIENT_ID"),
  codemyspec_client_secret: System.get_env("CODEMYSPEC_CLIENT_SECRET")

# Google OAuth (cms_gen.integration_provider Google google)
config :broken_oaths,
  google_client_id: System.get_env("GOOGLE_CLIENT_ID"),
  google_client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

if config_env() == :prod do
  # Cloak vault key for encrypted OAuth token storage. The compile-time
  # dev/test key in config.exs must never reach production.
  config :broken_oaths, BrokenOaths.Vault,
    ciphers: [
      default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1",
         key:
           Base.decode64!(
             System.get_env("CLOAK_KEY") ||
               raise("environment variable CLOAK_KEY is missing (base64 32-byte key)")
           )}
    ]

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :broken_oaths, BrokenOaths.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :broken_oaths, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :broken_oaths, BrokenOathsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Resend for real email delivery (fleet ADR). Only when the key is
  # present — a UAT/prod box without it keeps the Local adapter and
  # boots fine, emails just stay undelivered.
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :broken_oaths, BrokenOaths.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key

    config :broken_oaths,
           :mailer_from,
           {System.get_env("MAILER_FROM_NAME") || "Broken Oaths",
            System.get_env("MAILER_FROM_EMAIL") || "no-reply@#{host}"}
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :broken_oaths, BrokenOathsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :broken_oaths, BrokenOathsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :broken_oaths, BrokenOaths.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
