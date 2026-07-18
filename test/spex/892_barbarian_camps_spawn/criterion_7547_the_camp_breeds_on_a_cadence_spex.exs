defmodule BrokenOathsSpex.Story892.Criterion7547Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7547 — a camp below its warrior cap respawns exactly one
  new warrior every 3 turns.

  Uses one of the 1-2 camps that spawn already inside the player's
  own (already-visible) territory (criterion 7543), so warrior counts
  are observable from turn 0 with no marching/exploring detour —
  keeping this spec about the cadence alone, not entangled with how
  long a march to a distant camp happens to take.

  House doctrine: anchor the 3-turn boundary to an observed event
  (the last snapshot where the camp was seen at N warriors), not a
  hardcoded absolute turn number — `game_auto_tick` is off in test
  (`config/test.exs`), so `Fixtures.advance_turn/1` is the only thing
  that ever advances a turn here; counting calls to it between two
  observed snapshots is exact, no wall clock or concurrent economy to
  tolerate.

  Truth surface is the "game:camps" push (inferred shape, see the
  Fixtures moduledoc for `list_camps/1`). It is content-diffed against
  its last-pushed value (QA issue dbcbd478), so not every turn is
  guaranteed to produce one — `latest_camps/2` (not `assert_push_event`)
  tracks the running snapshot, carrying the last-known warrior count
  forward on a quiet turn (which, by construction, means the count
  hasn't changed).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the camp breeds on a cadence" do
    scenario "a below-cap camp gains exactly one warrior three turns after being observed" do
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

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:camp_id, visible_camp.tile_id)
         |> Map.put(:starting_warriors, length(visible_camp.warriors))
         |> Map.put(:camps, camps0)}
      end

      when_ "turns pass until the camp's warrior count first increases", context do
        {elapsed, marker} =
          Enum.reduce_while(
            1..12,
            {0, %{warriors: List.duplicate(:seed, context.starting_warriors)}, context.camps},
            fn _turn, {elapsed, last_marker, camps} ->
              Fixtures.advance_turn(context.world)
              camps = latest_camps(context.play_live, camps)
              marker = Enum.find(camps, &(&1.tile_id == context.camp_id))
              elapsed = elapsed + 1

              if length(marker.warriors) > length(last_marker.warriors) do
                {:halt, {elapsed, marker}}
              else
                {:cont, {elapsed, marker, camps}}
              end
            end
          )

        {:ok, context |> Map.put(:turns_to_first_respawn, elapsed) |> Map.put(:marker_after, marker)}
      end

      then_ "exactly one new warrior appeared, exactly three turns after the last observation",
            context do
        assert context.turns_to_first_respawn == 3
        assert length(context.marker_after.warriors) == context.starting_warriors + 1
        {:ok, context}
      end
    end
  end
end
