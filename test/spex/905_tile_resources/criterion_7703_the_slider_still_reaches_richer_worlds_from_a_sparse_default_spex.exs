defmodule BrokenOathsSpex.Story905.Criterion7703Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7703 — playtest update (issue 3e1159d1, resource density
  too high): the per-world density slider still spans sparser-to-richer
  worlds, but its DEFAULT position now lands at the sparse, Civ-like
  ~7%-of-land target rather than the old resource-heavy default — a
  player who never touches the slider gets the sparse world; raising it
  toward its maximum still reaches a noticeably richer world, and
  lowering it toward its minimum still reaches an even sparser one.

  Same `WorldLive.New` surface `Criterion7651Spex` establishes
  (`[data-test='new-world-form']`, `[data-test='resource-density-slider']`,
  `world[resource_density]` one of `"sparse" | "standard" | "dense"`) —
  "default position" here means submitting the form WITHOUT setting
  `resource_density` at all, which lands on the schema's own default
  (`"standard"` — migration `20260718050000`), now retuned to the
  sparse target itself rather than the old midpoint.
  """

  use BrokenOathsSpex.Case

  alias BrokenOathsSpex.Fixtures

  spex "the slider still reaches richer worlds from a sparse default" do
    scenario "the default density is sparse, and the slider still reaches richer and sparser worlds" do
      given_ "the density slider left at its default position", context do
        {:ok, view, _html} = live(context.conn, "/worlds/new")
        assert has_element?(view, "[data-test='resource-density-slider']")
        {:ok, Map.put(context, :new_world_view, view)}
      end

      when_ "a world is created without touching the density slider", context do
        {:error, {:live_redirect, %{to: default_to}}} =
          context.new_world_view
          |> form("[data-test='new-world-form']", world: %{"name" => "Default Density World"})
          |> render_submit()

        default_world = Fixtures.get_world!(extract_world_id(default_to))

        {:ok, Map.put(context, :default_world, default_world)}
      end

      then_ "the world is generated at the sparse ~7%-of-land target", context do
        assert context.default_world.resource_density == :standard

        pct = resource_pct(context.default_world)

        assert pct >= 5.0 and pct <= 9.0,
               "default density covered #{Float.round(pct, 2)}% of land tiles"

        {:ok, context}
      end

      when_ "the player raises the slider toward its maximum and regenerates", context do
        {:ok, dense_view, _html} = live(context.conn, "/worlds/new")

        {:error, {:live_redirect, %{to: dense_to}}} =
          dense_view
          |> form("[data-test='new-world-form']",
            world: %{"name" => "Richer World", "resource_density" => "dense"}
          )
          |> render_submit()

        dense_world = Fixtures.get_world!(extract_world_id(dense_to))

        {:ok, Map.put(context, :dense_world, dense_world)}
      end

      then_ "noticeably more land tiles carry resources than at the default", context do
        default_pct = resource_pct(context.default_world)
        dense_pct = resource_pct(context.dense_world)

        assert dense_pct > default_pct * 1.5,
               "dense (#{Float.round(dense_pct, 2)}%) is not noticeably richer than default (#{Float.round(default_pct, 2)}%)"

        {:ok, context}
      end

      when_ "the player lowers the slider toward its minimum and regenerates", context do
        {:ok, sparse_view, _html} = live(context.conn, "/worlds/new")

        {:error, {:live_redirect, %{to: sparse_to}}} =
          sparse_view
          |> form("[data-test='new-world-form']",
            world: %{"name" => "Sparser World", "resource_density" => "sparse"}
          )
          |> render_submit()

        sparse_world = Fixtures.get_world!(extract_world_id(sparse_to))

        {:ok, Map.put(context, :sparse_world, sparse_world)}
      end

      then_ "an even sparser world results than the default", context do
        default_pct = resource_pct(context.default_world)
        sparse_pct = resource_pct(context.sparse_world)

        assert sparse_pct < default_pct,
               "sparse (#{Float.round(sparse_pct, 2)}%) is not sparser than default (#{Float.round(default_pct, 2)}%)"

        {:ok, context}
      end
    end
  end

  defp resource_pct(world) do
    land =
      for tile_id <- 0..(Fixtures.tile_count(world) - 1),
          Fixtures.tile_class(world, tile_id) == :land,
          do: tile_id

    resource_count = Enum.count(land, &(Fixtures.resource_at(world, &1) != nil))
    resource_count / length(land) * 100
  end

  defp extract_world_id(path) do
    [id] = Regex.run(~r{/worlds/(\d+)}, path, capture: :all_but_first)
    String.to_integer(id)
  end
end
