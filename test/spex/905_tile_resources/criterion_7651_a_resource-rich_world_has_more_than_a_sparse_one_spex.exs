defmodule BrokenOathsSpex.Story905.Criterion7651Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7651 — resource density is a per-world setting: a world
  created "resource-rich" (dense) ends up with strictly more placed
  resource tiles than one created "sparse." Design doc:
  `.code_my_spec/knowledge/civ6_resources.md` §3 — "the target density
  (one per N land tiles)... is an open number for the PM," but the
  ORDERING the criterion names (dense > sparse) is the one fixed,
  testable fact regardless of the exact tuning the implementer picks.

  ## Assumed `BrokenOathsWeb.WorldLive.New` surface contract

  Doesn't exist yet (no `/worlds/new` route in `router.ex`;
  `WorldLive.Index`'s existing "New World" button creates a
  seed-random world inline with no density choice at all). This spec
  drives the following, designed to mirror this codebase's existing
  form conventions (`UserLive.Registration`'s `phx-submit`,
  `WorldLive.Index`'s `~p"/worlds/" <> world.id` navigate-on-create)
  closely enough for an implementer to build straight to it:

    * Route: `GET /worlds/new` -> `WorldLive.New`.
    * `[data-test='new-world-form']` — the create form,
      `phx-submit="create_world"`, fields `world[name]` and
      `world[resource_density]`.
    * `[data-test='resource-density-slider']` — the density control
      itself (a 3-position slider/select), one of `"sparse" |
      "standard" | "dense"` — the "resource-rich" setting the
      criterion names is `"dense"`.
    * On success: `push_navigate(socket, to: "/worlds/" <> to_string(world.id))`
      — mirroring `WorldLive.Index`'s existing `new_world` handler
      exactly, just with `resource_density` now part of the create
      attrs (an assumed new `BrokenOaths.Worlds.World` field).

  World seeds are globally unique (`unique_constraint(:seed)`), so the
  two worlds this scenario creates necessarily differ in seed as well
  as density — criterion 7644 already proves placement is
  seed-deterministic in isolation; this spec's job is the density
  ordering, which the design doc frames as a large enough gap (roughly
  Civ's own sparse-vs-dense spread) that it should hold regardless of
  ordinary per-seed terrain variance.

  ## Expected RED failure mode

  `router.ex` has no `/worlds/new` route today, only the DYNAMIC
  `live "/worlds/:id", WorldLive.Show, :show`. Without a literal
  `/worlds/new` route ahead of it, Phoenix matches "/worlds/new"
  against `:id`, so `live(conn, "/worlds/new")` mounts `WorldLive.Show`
  with `id: "new"` instead of 404ing — which then crashes with an
  `Ecto.Query.CastError` trying to cast `"new"` to an integer id. That
  crash — not a `Phoenix.Router.NoRouteError` — is the correct RED
  signal here: it is a direct, structural consequence of `WorldLive.New`
  and its route not existing yet, not a bug in this spec's own setup.
  """

  use BrokenOathsSpex.Case

  alias BrokenOathsSpex.Fixtures

  spex "a resource-rich world has more than a sparse one" do
    scenario "a world created with dense resource density places more resources than a sparse one" do
      given_ "the player is on the new-world form, ready to set resource density", context do
        {:ok, view, _html} = live(context.conn, "/worlds/new")
        assert has_element?(view, "[data-test='resource-density-slider']")
        {:ok, Map.put(context, :new_world_view, view)}
      end

      when_ "they create one sparse-density world and one dense (resource-rich) world", context do
        {:error, {:live_redirect, %{to: sparse_to}}} =
          context.new_world_view
          |> form("[data-test='new-world-form']",
            world: %{"name" => "Sparse Lands", "resource_density" => "sparse"}
          )
          |> render_submit()

        {:ok, dense_view, _html} = live(context.conn, "/worlds/new")

        {:error, {:live_redirect, %{to: dense_to}}} =
          dense_view
          |> form("[data-test='new-world-form']",
            world: %{"name" => "Resource-Rich Lands", "resource_density" => "dense"}
          )
          |> render_submit()

        sparse_world = Fixtures.get_world!(extract_world_id(sparse_to))
        dense_world = Fixtures.get_world!(extract_world_id(dense_to))

        {:ok,
         context
         |> Map.put(:sparse_world, sparse_world)
         |> Map.put(:dense_world, dense_world)}
      end

      then_ "the dense world has strictly more placed resource tiles than the sparse world", context do
        sparse_count = count_resources(context.sparse_world)
        dense_count = count_resources(context.dense_world)

        assert dense_count > sparse_count
        {:ok, context}
      end
    end
  end

  defp count_resources(world) do
    0..(Fixtures.tile_count(world) - 1)
    |> Enum.count(&(Fixtures.resource_at(world, &1) != nil))
  end

  defp extract_world_id(path) do
    [id] = Regex.run(~r{/worlds/(\d+)}, path, capture: :all_but_first)
    String.to_integer(id)
  end
end
