defmodule BrokenOathsSpex.Story892.Criterion7546Spex do
  @moduledoc """
  Story 892 — Barbarian Camps Spawn
  Criterion 7546 — fog of war is a HARD constraint for barbarian
  camps: a camp (and its warriors) the player has not scouted must
  never appear in any payload the client receives, even as turns pass
  and the hidden camp keeps spawning warriors behind the fog.

  This is the strongest legal check the sealed spec boundary allows
  for "never travels over the wire" — pushed board data IS this
  project's wire (see `.code_my_spec/knowledge/bdd/spex/index.md`:
  "Pushed board data ... is the canvas board's equivalent of the
  DOM"); a spec cannot inspect LiveView assigns directly (no
  `:sys.get_state`, no context reads in a `then_`), so every "game:*"
  push captured across several turns stands in for "assigns," mirroring
  criterion 7436 (story 876, "hidden tiles never travel over the
  wire") which established this exact pattern for terrain/units.

  Ground truth for which camps are hidden comes from
  `Fixtures.list_camps/1` + the region reads, the same sanctioned,
  no-UI-surface shortcut criterion 7543 uses — never used here to
  assert what the player *sees*, only to know which camps the
  assertions below must never find leaking.

  `"game:camps"` is content-diffed against its last-pushed value (QA
  issue dbcbd478): a turn only re-pushes when the player's own
  fog-filtered camp set actually changed, so NOT every one of the six
  turns below is guaranteed to produce a push (a hidden camp spawning
  a warrior, by construction, never changes what the player's own
  push contains). `latest_camps/2` (not `assert_push_event`) collects
  whatever pushes DO arrive, carrying the last-known snapshot forward
  on a quiet turn — the assertions below only care that every push
  that DOES happen omits hidden data, not that one happens every turn.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fog keeps its secrets" do
    scenario "hidden camps and their warriors never appear in a push, turn after turn" do
      given_(:a_world)
      given_(:registered_player)

      given_ "the player joined the world and founded their first city", context do
        {:ok, join_live, _html} = live(context.conn, ~p"/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})

        assert_push_event(play_live, "game:camps", %{camps: camps0})
        [city] = Fixtures.player_cities(context.world, context.user)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:camps, camps0)
         |> Map.put(:camps_pushes, [camps0])}
      end

      when_ "six turns pass while the wilderness camps stay unscouted", context do
        {pushes, _camps} =
          Enum.reduce(1..6, {context.camps_pushes, context.camps}, fn _turn, {acc, camps} ->
            Fixtures.advance_turn(context.world)
            camps = latest_camps(context.play_live, camps)
            {[camps | acc], camps}
          end)

        {:ok, Map.put(context, :camps_pushes, pushes)}
      end

      then_ "every push omits every camp the player has not explored", context do
        region_id = Fixtures.claimed_region(context.world, context.user)
        %{regions: regions} = Fixtures.region_partition(context.world)
        home = MapSet.new(Map.fetch!(regions, region_id))

        all_camps = Fixtures.list_camps(context.world)
        hidden_camps = Enum.reject(all_camps, &MapSet.member?(home, &1.tile_id))

        hidden_ids = MapSet.new(hidden_camps, & &1.id)
        hidden_tile_ids = MapSet.new(hidden_camps, & &1.tile_id)
        hidden_warrior_ids = hidden_camps |> Enum.flat_map(& &1.warriors) |> MapSet.new(& &1.id)

        # Anchors: hidden camps genuinely exist, and by six turns in at
        # least one has spawned a warrior — the "secret" is substantive,
        # not a vacuous empty set that would pass every refute below.
        assert hidden_camps != []
        assert Enum.any?(hidden_camps, &(&1.warriors != []))

        for push <- context.camps_pushes, camp <- push do
          refute camp.id in hidden_ids
          refute camp.tile_id in hidden_tile_ids

          for warrior <- camp.warriors do
            refute warrior.id in hidden_warrior_ids
          end
        end

        # Anchor: the player's own, already-visible camp(s) DO keep
        # appearing in every single push — the fog filter hides
        # specific camps, not the whole "game:camps" push.
        assert Enum.all?(context.camps_pushes, fn push ->
                 Enum.any?(push, &MapSet.member?(home, &1.tile_id))
               end)

        {:ok, context}
      end
    end
  end
end
