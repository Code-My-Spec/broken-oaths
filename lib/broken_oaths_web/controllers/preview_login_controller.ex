defmodule BrokenOathsWeb.PreviewLoginController do
  @moduledoc """
  Mints a one-time token for a visitor sitting inside the CodeMySpec preview
  pane, so they can end up signed in without a third party ever being asked
  to render inside anything.

  Google and GitHub refuse outright to render their own sign-in pages inside
  any iframe — that refusal is theirs, sent as their own response headers,
  and no policy this application or CodeMySpec sets can change it. A
  previewed app's real "Sign in with Google" link will always fail inside
  the pane. This is the other way in: CodeMySpec's own backend, holding the
  project's deploy key, asks this application for a token here; the pane's
  frame then navigates to whatever route redeems it and establishes a
  session.

  ## What this does not do

  It does not establish a session. Turning this token into an actual
  signed-in one is a separate concern — this application has its own
  `UserSessionController`, and the redemption route belongs there, wired to
  this token's own verification, not duplicated here.

  ## Why the deploy key alone is not enough

  The deploy key is a server secret. It authenticates CodeMySpec's backend to
  this application; it can never be handed to the visitor's browser, which is
  exactly what needs to end up holding a session. This exists as the bridge:
  a deploy-key-authenticated request in exchange for a token that is safe to
  put in a URL the browser will actually navigate to — short-lived, and
  meaningless to anyone without this application's own secret key base.

  ## Preview-gated, not just deploy-key-gated

  The deploy key is already a strong secret, but minting this token widens
  what a holder of it can do — the same asymmetry `ClientUtils.PreviewFraming`
  reasons about for framing. Same discipline here: refuse unless this
  application is currently configured for a preview (`config :broken_oaths,
  :preview`, the identical signal that plug already reads), so the login
  bridge exists only for as long as an actual preview does.
  """

  use BrokenOathsWeb, :controller

  plug :authenticate
  plug :require_preview

  @salt "cms_preview_login"

  @doc """
  A token proving CodeMySpec's backend vouches for the browser about to
  arrive, redeemable by whatever route later exchanges it for a real
  session.

  Signed rather than stored: a signed token needs no storage on either side,
  and there is no separate revocation to check — a short `max_age` at
  verification time (`Phoenix.Token.verify(endpoint, "cms_preview_login",
  token, max_age: 60)`) is the whole lifetime.
  """
  def create(conn, _params) do
    token = Phoenix.Token.sign(conn, @salt, :preview_login)

    conn
    |> put_status(:created)
    |> json(%{token: token})
  end

  # Identical to `VerifyController`'s: the project's deploy key, compared in
  # constant time. Copied rather than shared because the two controllers
  # answer different questions, and a shared plug module would suggest they
  # are the same concern.
  defp authenticate(conn, _opts) do
    with expected when is_binary(expected) and expected != "" <- configured_key(),
         ["Bearer " <> presented] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(presented, expected) do
      conn
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{status: "unauthorized"})
        |> halt()
    end
  end

  defp configured_key, do: Application.get_env(:broken_oaths, :deploy_key)

  # The same signal `ClientUtils.PreviewFraming` reads to decide whether to
  # widen `frame-ancestors` at all — empty until onboarding records a
  # preview, so a token cannot be minted for an application no preview pane
  # could even be looking at. A 404 rather than a 401: the deploy key already
  # settled who is asking, and this says there is nothing here to ask for,
  # not that the answer was wrong.
  defp require_preview(conn, _opts) do
    if preview_configured?() do
      conn
    else
      conn
      |> put_status(:not_found)
      |> json(%{status: "not_found"})
      |> halt()
    end
  end

  defp preview_configured?, do: Application.get_env(:broken_oaths, :preview, []) != []
end
