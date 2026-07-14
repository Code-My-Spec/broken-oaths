defmodule BrokenOaths.Check.Warning.BrokenOathsSpexDenies do
  use Credo.Check,
    id: "BROKEN0001",
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Project-local WHOLE-module denies for BDD spec files (`_spex.exs`).

      The framework check (`CodeMySpec.Check.Warning.SpexDeniedCalls`)
      carries the universal function-level denies; this check seals the
      module-level surface for Broken Oaths:

      Stdlib bypasses:

      - `File`, `:file` — real-disk access bypasses the test environment.
      - `Port` — talks to external programs; use cassettes instead.

      App internals (specs must act through the LiveView surface or the
      `BrokenOathsSpex.Fixtures` bridge — never call contexts or Repo):

      - `BrokenOaths.Repo` — direct DB access bypasses the public surface.
      - `BrokenOaths.Game` — gameplay state changes through GameLive, or
        is seeded via the fixtures bridge.
      - `BrokenOaths.Worlds` — worlds are created via `world_fixture/1`
        on the bridge and driven through WorldLive.
      - `BrokenOaths.Users` — session tokens and users come from the
        bridge (`user_fixture/1`, `generate_user_session_token/1`).
      - `BrokenOaths.Accounts` — membership flows go through AccountLive.
      - `BrokenOaths.Integrations` — OAuth flows go through the
        IntegrationsController surface.

      Schemas (e.g. `BrokenOaths.Game.Unit`) and web modules are NOT
      denied — pattern-matching on structs in assertions is legal.
      See .code_my_spec/knowledge/bdd/spex/index.md.
      """
    ]

  @denied_whole_modules [
    File,
    Port,
    BrokenOaths.Repo,
    BrokenOaths.Game,
    BrokenOaths.Worlds,
    BrokenOaths.Users,
    BrokenOaths.Accounts,
    BrokenOaths.Integrations
  ]

  @denied_whole_erlang_modules [:file]

  @doc false
  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if String.ends_with?(filename, "_spex.exs") do
      ctx = %{issue_meta: Context.build(source_file, params, __MODULE__), issues: []}
      Credo.Code.prewalk(source_file, &traverse/2, ctx).issues
    else
      []
    end
  end

  # Aliased Elixir modules — File.*, Port.*, BrokenOaths.<Context>.*
  defp traverse(
         {{:., _, [{:__aliases__, meta, module_parts}, fun]}, _, _args} = ast,
         ctx
       ) do
    module = Module.concat(module_parts)

    if module in @denied_whole_modules do
      {ast, add_issue(ctx, meta, "#{inspect(module)}.#{fun}")}
    else
      {ast, ctx}
    end
  end

  # Erlang modules — :file.*
  defp traverse({{:., _, [erl_mod, fun]}, meta, _args} = ast, ctx)
       when is_atom(erl_mod) do
    if erl_mod in @denied_whole_erlang_modules do
      {ast, add_issue(ctx, meta, "#{inspect(erl_mod)}.#{fun}")}
    else
      {ast, ctx}
    end
  end

  defp traverse(ast, ctx), do: {ast, ctx}

  defp add_issue(ctx, meta, trigger) do
    issue =
      format_issue(
        ctx.issue_meta,
        message:
          "Call to `#{trigger}` is denied in _spex.exs files. Drive the LiveView " <>
            "surface or use BrokenOathsSpex.Fixtures — specs never touch contexts, " <>
            "Repo, or the real filesystem. See .code_my_spec/knowledge/bdd/spex/index.md.",
        trigger: trigger,
        line_no: meta[:line],
        column: meta[:column]
      )

    %{ctx | issues: [issue | ctx.issues]}
  end
end
