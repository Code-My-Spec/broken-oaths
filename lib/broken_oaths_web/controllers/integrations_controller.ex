defmodule BrokenOathsWeb.IntegrationsController do
  use BrokenOathsWeb, :controller

  alias BrokenOaths.Integrations
  alias BrokenOaths.Integrations.OAuthStateStore
  alias BrokenOaths.Users
  alias BrokenOaths.Users.Scope
  alias BrokenOathsWeb.UserAuth

  require Logger

  # Providers offered as SOCIAL LOGIN (identity), as opposed to
  # integrations connected from settings by an existing user.
  @login_providers [:google]

  @doc """
  Initiates OAuth for social login/registration — unauthenticated.
  The shared callback recognises the flow via the session flag.
  """
  def login(conn, %{"provider" => provider_str}) do
    provider = String.to_existing_atom(provider_str)

    if provider not in @login_providers do
      conn |> put_flash(:error, "Unsupported sign-in method") |> redirect(to: "/users/log-in")
    else
      case Integrations.authorize_url(provider) do
        {:ok, %{url: url, session_params: session_params}} ->
          store_state(session_params)

          conn
          |> put_session(:oauth_provider, provider)
          |> put_session(:oauth_flow, :login)
          |> redirect(external: url)

        {:error, reason} ->
          Logger.error("Failed to generate login URL for #{provider}: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Unable to reach #{format_provider(provider)}. Please try again.")
          |> redirect(to: "/users/log-in")
      end
    end
  end

  def request(conn, %{"provider" => provider_str}) do
    provider = String.to_existing_atom(provider_str)

    case Integrations.authorize_url(provider) do
      {:ok, %{url: url, session_params: session_params}} ->
        store_state(session_params)

        conn
        |> put_session(:oauth_provider, provider)
        |> put_session(:oauth_flow, :integration)
        |> redirect(external: url)

      {:error, reason} ->
        Logger.error("Failed to generate OAuth URL for #{provider}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to connect to #{format_provider(provider)}")
        |> redirect(to: "/")
    end
  end

  defp store_state(session_params) do
    state = Map.get(session_params, "state") || Map.get(session_params, :state)
    if state, do: OAuthStateStore.store(state, session_params)
  end

  def callback(conn, params) do
    provider = get_session(conn, :oauth_provider)
    flow = get_session(conn, :oauth_flow) || :integration

    state = Map.get(params, "state")

    session_params =
      if state do
        case OAuthStateStore.fetch(state) do
          {:ok, sp} -> sp
          :error -> %{}
        end
      else
        %{}
      end

    conn =
      conn
      |> delete_session(:oauth_provider)
      |> delete_session(:oauth_flow)

    case Map.get(params, "error") do
      nil ->
        dispatch_callback(conn, flow, provider, params, session_params)

      error ->
        conn
        |> put_flash(:error, format_oauth_error(error, params))
        |> redirect(to: callback_error_path(flow))
    end
  end

  # Social login: exchange the code first (no user yet), then find or
  # register by the provider-verified email, persist the integration
  # under the fresh scope, and log in.
  defp dispatch_callback(conn, :login, provider, params, session_params) do
    with {:ok, %{user: normalized, token: token}} <-
           Integrations.handle_login_callback(provider, params, session_params),
         {:ok, user, status} <- Users.find_or_register_oauth_user(normalized) do
      Integrations.save_integration(Scope.for_user(user), provider, token, normalized)

      conn
      |> put_flash(:info, login_flash(status, provider))
      |> put_session(:user_return_to, "/play")
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      {:error, :missing_email} ->
        conn
        |> put_flash(
          :error,
          "We couldn't get an email address from #{format_provider(provider)}."
        )
        |> redirect(to: "/users/log-in")

      {:error, reason} ->
        Logger.error("Social login failed for #{provider}: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Sign-in with #{format_provider(provider)} failed. Please try again.")
        |> redirect(to: "/users/log-in")
    end
  end

  defp dispatch_callback(conn, :integration, provider, params, session_params) do
    case conn.assigns[:current_scope] do
      nil ->
        conn
        |> put_flash(:error, "Please log in before connecting an integration.")
        |> redirect(to: "/users/log-in")

      scope ->
        case Integrations.handle_callback(scope, provider, params, session_params) do
          {:ok, _integration} ->
            conn
            |> put_flash(:info, "Successfully connected to #{format_provider(provider)}")
            |> redirect(to: "/integrations")

          {:error, reason} ->
            Logger.error("OAuth callback failed for #{provider}: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Failed to complete connection")
            |> redirect(to: "/integrations")
        end
    end
  end

  defp login_flash(:registered, provider),
    do: "Welcome! Your account was created with #{format_provider(provider)}."

  defp login_flash(:existing, provider),
    do: "Welcome back! Signed in with #{format_provider(provider)}."

  defp callback_error_path(:login), do: "/users/log-in"
  defp callback_error_path(_flow), do: "/integrations"

  def delete(conn, %{"provider" => provider_str}) do
    provider = String.to_existing_atom(provider_str)
    scope = conn.assigns.current_scope

    case Integrations.delete_integration(scope, provider) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Disconnected from #{format_provider(provider)}")
        |> redirect(to: "/integrations")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "No connection found")
        |> redirect(to: "/integrations")
    end
  end

  defp format_provider(:github), do: "GitHub"
  defp format_provider(:google), do: "Google"
  defp format_provider(:facebook), do: "Facebook"
  defp format_provider(:quickbooks), do: "QuickBooks"
  defp format_provider(:codemyspec), do: "CodeMySpec"
  defp format_provider(provider), do: provider |> to_string() |> String.capitalize()

  defp format_oauth_error("access_denied", _params),
    do: "You denied access. Please try again if you want to connect."

  defp format_oauth_error(error, %{"error_description" => desc}),
    do: "OAuth error: #{desc} (#{error})"

  defp format_oauth_error(error, _params), do: "OAuth error: #{error}"
end
