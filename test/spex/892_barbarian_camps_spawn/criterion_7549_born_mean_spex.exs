defmodule BrokenOathsSpex.Story892.Criterion7549Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7549 — a barbarian warrior spawns with 15 attack, 15
  defense, and 120 HP.

  Field names: there is no existing attack/defense concept anywhere
  in this codebase yet (`Game.Unit` has no such fields — see the
  moduledoc on criterion 7533/story 891, which stands a second
  player's warrior in for "the barbarian" specifically because Camps
  doesn't exist and there's no hostility concept on `Game.Unit`). This
  spec follows the Three Amigos' own wording for story 892 ("15
  attack / 15 defense / 120 HP") for the new, camp-nested warrior
  shape (see the Fixtures moduledoc for `list_camps/1`).

  Uses one of the 1-2 camps that spawn already inside the player's
  own (already-visible) territory (criterion 7543), so a spawned
  warrior is observable from turn 0 through the "game:camps" push
  with no marching detour.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "born mean" do
    scenario "a freshly spawned barbarian warrior has 15/15/120 stats" do
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

      when_ "turns pass until the camp spawns its first warrior", context do
        warrior =
          Enum.reduce_while(1..6, nil, fn _turn, _acc ->
            Fixtures.advance_turn(context.world)
            assert_push_event(context.play_live, "game:camps", %{camps: camps}, 500)
            camp = Enum.find(camps, &(&1.tile_id == context.camp_id))

            case camp.warriors do
              [w | _] -> {:halt, w}
              [] -> {:cont, nil}
            end
          end)

        {:ok, Map.put(context, :warrior, warrior)}
      end

      then_ "the warrior is born with barbarian-grade stats", context do
        assert context.warrior != nil
        assert context.warrior.attack == 15
        assert context.warrior.defense == 15
        assert context.warrior.hp == 120
        {:ok, context}
      end
    end
  end
end
