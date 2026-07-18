defmodule BrokenOathsSpex.Story905.Criterion7649Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7649 — resources are visible from the first look: no reveal
  tech, no worked/improved prerequisite, no research at all. Design
  doc: `.code_my_spec/knowledge/civ6_resources.md` §3.5 — "resources
  are visible from the start (bonus resources have no reveal-tech in
  Civ)", in contrast to Civ's strategic resources (explicitly out of
  scope, §6). This spec proves the negative case directly: a lone Lord
  scouts onto a resource tile with NO city founded, NO research picked,
  and NO improvement anywhere — the resource is already visible the
  moment the tile itself is looked at, same as ordinary terrain.

  Reuses `GameLive.Play`'s existing `"select_tile"` event and
  `[data-test='tile-panel']` (already showing `tile-terrain`/
  `tile-yields`/`tile-improvement`, see that handler's own moduledoc)
  — `[data-test='tile-resource']` is the natural next field on the same
  panel, assumed to render only `:if={@selected_tile.resource}`,
  mirroring the existing `:if={@selected_tile.improvement}` line right
  above it.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "resources are visible from the first look" do
    scenario "a scouted resource tile shows its resource with no research, city, or improvement" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the lord has scouted onto a resource tile — no city, research, or improvement anywhere",
             context do
        resource_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) != nil
          end)

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => resource_tile})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == resource_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        resource_kind = Fixtures.resource_at(context.world, resource_tile)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:resource_tile, resource_tile)
         |> Map.put(:resource_kind, resource_kind)}
      end

      when_ "the player looks at that tile", context do
        render_hook(context.play_live, "select_tile", %{"tile_id" => context.resource_tile})
        {:ok, context}
      end

      then_ "the tile panel already shows the resource, unconditionally", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='tile-resource']",
                 resource_label(context.resource_kind)
               )

        {:ok, context}
      end
    end
  end

  defp resource_label(:cattle), do: "Cattle"
  defp resource_label(:sheep), do: "Sheep"
  defp resource_label(:wheat), do: "Wheat"
  defp resource_label(:stone), do: "Stone"
end
