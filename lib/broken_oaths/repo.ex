defmodule BrokenOaths.Repo do
  use Ecto.Repo,
    otp_app: :broken_oaths,
    adapter: Ecto.Adapters.Postgres
end
