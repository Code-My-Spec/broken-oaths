defmodule BrokenOathsSpex.Story892.Criterion7548Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7548 — a camp never holds more than 2 warriors alive at
  once, no matter how many turns pass.

  Uses one of the 1-2 camps that spawn already inside the player's
  own (already-visible) territory (criterion 7543), so warrior counts
  are observable from turn 0 with no marching detour.

  `game_auto_tick` is off in test (`config/test.exs`), so
  `Fixtures.advance_turn/1` is the only thing that ever advances a
  turn — 21 turns is comfortably more than the ~6 turns (two 3-turn
  cadence cycles, criterion 7547) a fresh camp needs to reach a
  2-warrior cap, covering several cycles' worth of "would it have
  overshot by now" margin ("holds overnight"). Truth surface is the
  "game:camps" push (inferred shape, see the Fixtures moduledoc for
  `list_camps/1`), drained turn-by-turn so every single snapshot —
  not just the last — is checked against the cap.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the cap holds overnight" do
    scenario "a camp reaches two warriors and never exceeds it across many turns" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player founded their first city, revealing a nearby barbarian camp",
             context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [visible_camp | _] = camps0

        {:ok, context |> Map.put(:play_live, play_live) |> Map.put(:camp_id, visible_camp.tile_id)}
      end

      when_ "twenty-one turns pass with no player intervention", context do
        warrior_counts =
          Enum.map(1..21, fn _turn ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.tile_id == context.camp_id))
            length(camp.warriors)
          end)

        {:ok, Map.put(context, :warrior_counts, warrior_counts)}
      end

      then_ "the camp never exceeds two warriors, and reaches the cap", context do
        assert Enum.max(context.warrior_counts) == 2
        assert Enum.all?(context.warrior_counts, &(&1 <= 2))
        {:ok, context}
      end
    end
  end
end
