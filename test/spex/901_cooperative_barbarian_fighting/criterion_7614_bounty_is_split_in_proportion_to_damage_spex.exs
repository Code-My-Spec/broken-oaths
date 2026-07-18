defmodule BrokenOathsSpex.Story901.Criterion7614Spex do
  @moduledoc """
  Story 901 — Cooperative Barbarian Fighting
  Criterion 7614 — when a barbarian camp falls to combined attacks
  from two different players, its gold bounty is split between them in
  proportion to how much damage each actually dealt — not paid whole
  to whichever of them happened to land the final, killing blow
  (stone_age.md §8.2, "gold reward for killing barbarians/camps split
  among participants" — the Three Amigos' resolution of "how the
  bounty splits" is "proportional to damage").

  As of this writing `BrokenOaths.Game.WorldServer`'s
  `pay_bounty_if_barbarian_fell/2` pays the FULL `Camps.destroy_reward/0`
  (30 gold) to whichever single player's attacker's own `do_attack_camp`
  call happens to zero the camp's HP — there is no notion of "who else
  contributed" at all. This is the RED criterion this story exists to
  drive: today player one (who deals 70 of the 100 total damage but
  never lands the actual killing blow) would receive nothing, and
  player two (who lands the last 30 damage AND the kill) would receive
  the entire 30 gold.

  A 7-hit / 3-hit split is deliberately chosen: a full-HP Warrior's
  `attack_camp` is flat, unrolled 10 damage per hit (story 894
  criterion 7559 — no counter, no random roll), so 7 hits is EXACTLY 70
  of the camp's 100 total HP and 3 hits is EXACTLY 30 — a clean 70/30
  split of a 30-gold pot is 21 and 9 gold with no rounding ambiguity,
  regardless of which specific proportional-split rule the
  implementation ultimately picks (floor, round, largest-remainder all
  agree on an exact split).

  Surface note: see criterion 7611's moduledoc for why this reuses the
  existing `"attack"` + `target_camp_id` hook across two independent
  LiveView connections. Gold is read from the same rendered
  `[data-test='player-gold']` badge story 893/894's own bounty criteria
  already established as the legal surface for this fact.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "bounty is split in proportion to damage" do
    scenario "a camp felled by 70% one ally's damage and 30% the other's pays a 70/30 gold split" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have founded cities, and each has a warrior standing beside the same barbarian camp",
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

      when_ "player one lands seven of the ten hits and player two lands the final three, felling it together",
            context do
        Enum.each(1..7, fn i ->
          render_hook(context.play_live, "attack", %{
            "unit_id" => to_string(context.warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.play_live, "game:combat", %{damage_dealt: dealt}, 500)
          assert dealt == 10
          if i < 7, do: Fixtures.recharge_unit(context.world, context.warrior.id)
        end)

        Fixtures.recharge_unit(context.world, context.other_warrior.id)

        Enum.each(1..3, fn i ->
          render_hook(context.other_play_live, "attack", %{
            "unit_id" => to_string(context.other_warrior.id),
            "target_camp_id" => to_string(context.camp.id)
          })

          assert_push_event(context.other_play_live, "game:combat", %{damage_dealt: dealt}, 500)
          assert dealt == 10
          if i < 3, do: Fixtures.recharge_unit(context.world, context.other_warrior.id)
        end)

        {:ok, context}
      end

      then_ "the camp is destroyed", context do
        assert_push_event(context.other_play_live, "game:camps", %{camps: camps_after}, 500)
        refute Enum.any?(camps_after, &(&1.id == context.camp.id))
        {:ok, context}
      end

      then_ "the 30-gold bounty splits 21/9 — proportional to the 70/30 damage split, not winner-take-all",
            context do
        assert player_gold(context.play_live) == context.gold_a0 + 21
        assert player_gold(context.other_play_live) == context.gold_b0 + 9
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
