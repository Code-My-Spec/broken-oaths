defmodule BrokenOaths.Codemyspec.Client do
  @moduledoc """
  HTTP client for CodeMySpec feedback intake.

  Authenticates with the project deploy key (`CODEMYSPEC_DEPLOY_KEY`)
  against the deploy-key issue endpoint — the key alone resolves the
  project on the CodeMySpec side, so no per-user OAuth connection is
  involved and nothing in the app depends on one.
  """

  @doc "True when a deploy key is configured, i.e. feedback can be submitted."
  def enabled? do
    case deploy_key() do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  @doc """
  Creates an issue on the CodeMySpec platform.

  Attrs should include: title, description, severity. The source is
  set to "user_feedback"; CodeMySpec forces the scope server-side.
  """
  def create_issue(attrs) do
    url = "#{codemyspec_url()}/api/framework/issues"

    body = Jason.encode!(%{"issue" => Map.put(attrs, "source", "user_feedback")})

    headers = [
      {"authorization", "Bearer #{deploy_key()}"},
      {"content-type", "application/json"}
    ]

    case Req.post(url, body: body, headers: headers) do
      {:ok, %Req.Response{status: 201, body: body}} ->
        {:ok, body["data"]}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deploy_key do
    Application.get_env(:broken_oaths, :codemyspec_deploy_key)
  end

  defp codemyspec_url do
    Application.fetch_env!(:broken_oaths, :codemyspec_url)
  end
end
