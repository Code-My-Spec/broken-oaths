defmodule BrokenOaths do
  @moduledoc """
  BrokenOaths keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  # BrokenOathsWeb.Endpoint.url() builds absolute links for outbound
  # invitation emails — the standard phx.gen.auth-style exception.
  use Boundary, deps: [], exports: :all, dirty_xrefs: [BrokenOathsWeb.Endpoint]
end
