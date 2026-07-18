defmodule BrokenOathsSpex.Story901.Criterion7624Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7624 — the proportional bounty split (criterion 7614) does
  not require the two attacking players to have "discovered" each
  other first, or to have coordinated over chat (criterion 7623) at
  all: cooperation is emergent purely from both of their units
  striking the same target, exactly the resolution stone_age.md §8.2's
  own line ("whether cooperation is explicit or emergent from shared
  targeting... are Three Amigos decisions") settled on.

  Deliberately, this scenario sets up NEITHER a discovery precondition
  (story 899 — not implemented, and this story doesn't need it) NOR an
  alliance-chat exchange (story 900 / this story's own criterion
  7623): two players simply found cities in the same world and both
  happen to strike the same camp. If the split logic were ever gated
  behind a "these two are allies" flag, this is the criterion that
  would catch it — the two players here are, mechanically, complete
  strangers to one another the whole scenario through.

  Uses the same flat, unrolled 10-damage-per-hit camp assault as
  criterion 7614 (story 894 criterion 7559) but a DIFFERENT split ratio
  (40/60 instead of 7614's 70/30) so this is a distinct proof, not a
  restatement of 7614's own exact-math scenario. 4 hits (40 of the
  100-HP camp's total) and 6 hits (60) split a 30-gold
  `Camps.destroy_reward/0` cleanly into 12 and 18 gold, with no
  rounding ambiguity.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "even undiscovered attackers share the bounty" do
    scenario "two players who never discovered each other or coordinated still split a camp's bounty by damage dealt" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have founded cities, and each has a warrior standing beside the same barbarian camp — with no discovery or chat between them",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        assert_push_event(play_live, "game:camps", %{camps: pushed_camps}, 500)
        [camp | _] = pushed_camps
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{
          "city_id" => to_string(city.id),
          "item" => "warrior"
        })

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => to_string(other_settler.id)})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => to_string(other_city.id),
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [other_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [city.tile_id, lord.tile_id, other_city.tile_id, other_lord.tile_id]

        [target_a, target_b | _] =
          context.world
          |> Fixtures.adjacent_tiles(camp.tile_id)
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        clear_tile(context.world, target_a)
        :ok = Fixtures.relocate_unit(context.world, warrior.id, target_a)
        clear_tile(context.world, target_b)
        :ok = Fixtures.relocate_unit(context.world, other_warrior.id, target_b)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.id == warrior.id, do: u

        [other_warrior] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == other_warrior.id,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:other_warrior, other_warrior)
         |> Map.put(:camp, camp)
         |> Map.put(:gold_a0, player_gold(play_live))
         |> Map.put(:gold_b0, player_gold(other_play_live))}
      end

      when_ "player one lands four of the ten hits and player two lands the final six, felling it together",
            context do
        Enum.each(1..4, fn i ->
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
          assert dealt == 10
          if i < 4, do: Fixtures.recharge_unit(context.world, context.warrior.id)
        end)

        Fixtures.recharge_unit(context.world, context.other_warrior.id)

        Enum.each(1..6, fn i ->
          render_hook(context.other_play_live, "attack", %{
            "unit_id" => to_string(context.other_warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.other_play_live, "game:combat", %{damage_dealt: dealt}, 500)
          assert dealt == 10
          if i < 6, do: Fixtures.recharge_unit(context.world, context.other_warrior.id)
        end)

        {:ok, context}
      end

      then_ "the camp is destroyed", context do
        assert_push_event(context.other_play_live, "game:camps", %{camps: camps_after}, 500)
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "the 30-gold bounty still splits 12/18 by damage dealt, with no discovery or chat between the two",
            context do
        assert player_gold(context.play_live) == context.gold_a0 + 12
        assert player_gold(context.other_play_live) == context.gold_b0 + 18
        {:ok, context}
      end
    end
  end

  # Deliberate, narrow exception, same status as story 893/894's
  # restructured criteria: a real, active camp may have already spawned
  # a warrior of its own onto a tile this criterion needs to place
  # something ELSE on exactly — relocate it out of the way first. A
  # no-op if `tile_id` is already clear.
  defp clear_tile(world, tile_id) do
    occupant =
      world
      |> Fixtures.list_camps()
      |> Enum.flat_map(& &1.warriors)
      |> Enum.find(&(&1.tile_id == tile_id))

    if occupant do
      parking =
        Fixtures.adjacent_tiles(world, tile_id)
        |> Enum.filter(&(Fixtures.tile_class(world, &1) == :land and &1 != tile_id))

      Enum.find_value(parking, fn t -> Fixtures.relocate_unit(world, occupant.id, t) == :ok end)
    end

    :ok
  end

  # The gold badge renders the icon component (no digits) followed by
  # the plain integer — the last digit run in the fragment is always
  # the gold total, regardless of the icon's own markup (story 894
  # criterion 7560's own helper).
  defp player_gold(play_live) do
    html = play_live |> element("[data-test='player-gold']") |> render()

    ~r/\d+/
    |> Regex.scan(html)
    |> List.last()
    |> List.first()
    |> String.to_integer()
  end
end
