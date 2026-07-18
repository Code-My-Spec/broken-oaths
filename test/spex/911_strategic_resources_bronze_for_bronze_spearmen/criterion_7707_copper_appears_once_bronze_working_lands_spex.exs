defmodule BrokenOathsSpex.Story911.Criterion7707Spex do
  @moduledoc """
  Story 911 — Strategic Resources: Bronze for Bronze Spearmen
  Criterion 7707 — Copper is revealed by (i.e. becomes visible only
  after) researching Bronze Working, mirroring Civ 6's own "Bronze
  Working reveals Iron" convention — before a player completes Bronze
  Working, a Copper tile isn't visible/known to them at all; after,
  it is.

  `BrokenOaths.Worlds.Resources.at/2` places Copper on the map
  UNCONDITIONALLY (worldgen state, no concept of a viewing player —
  see that module's own moduledoc); the reveal gate lives entirely in
  `BrokenOathsWeb.GameLive.Play`'s `visible_resource/3`, exercised here
  through the real `"select_tile"` surface story 905's own
  `Criterion7649Spex` already established for bonus resources (which
  have NO reveal gate at all — this criterion is the one exception).

  A lone Lord scouts onto a real Copper tile with no research done yet
  — the same "prove the negative case directly" idiom
  `Criterion7649Spex`'s own moduledoc documents — then the SAME tile is
  looked at again after Bronze Working completes, on the same
  connection, so this is a single before/after comparison of one fixed
  tile rather than two different worlds. A city IS founded (with the
  player's own starting settler, wherever it happens to be — this
  criterion's own subject is VISIBILITY, not Copper access/territory,
  so its exact location is irrelevant here) purely to generate the
  science income Mining/Bronze Working need to ever complete
  (`Research.science_per_turn/1` sums `2 * size` over a player's
  cities — zero cities means zero science, so research would otherwise
  never finish).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Copper appears once Bronze Working lands" do
    scenario "a Copper tile stays hidden until Bronze Working completes, then reveals" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a city is founded (for science income) and the lord scouts onto a Copper tile", context do
        copper_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) == :copper
          end)

        refute is_nil(copper_tile), "this world's own placement rolled no Copper anywhere"

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})

        [lord | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => copper_tile})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [l] = for u <- Fixtures.player_units(context.world, context.user), u.id == lord.id, do: u

          if l.tile_id == copper_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:copper_tile, copper_tile)}
      end

      when_ "the player looks at that tile before researching Bronze Working", context do
        render_hook(context.play_live, "select_tile", %{"tile_id" => context.copper_tile})
        {:ok, context}
      end

      then_ "the tile panel does not show Copper yet", context do
        refute has_element?(context.play_live, "[data-test='tile-resource']"),
               "Copper showed up on the tile panel before Bronze Working was ever researched"

        {:ok, context}
      end

      given_ "the player reaches the Bronze Age (Mining, then Bronze Working)", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "mining"})

        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          if has_element?(context.play_live, "[data-test='tech-completed-mining']") do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(context.play_live, "select_research", %{"tech" => "bronze_working"})
        render_hook(context.play_live, "bronze_working_confirm", %{})

        for _ <- 1..60, do: Fixtures.advance_turn(context.world)

        assert has_element?(context.play_live, "[data-test='tech-completed-bronze_working']")
        {:ok, context}
      end

      when_ "the player looks at the exact same Copper tile again", context do
        render_hook(context.play_live, "select_tile", %{"tile_id" => context.copper_tile})
        {:ok, context}
      end

      then_ "the tile panel now shows Copper", context do
        assert has_element?(context.play_live, "[data-test='tile-resource']", "Copper")
        {:ok, context}
      end
    end
  end
end
