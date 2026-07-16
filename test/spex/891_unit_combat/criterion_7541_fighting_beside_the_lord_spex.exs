defmodule BrokenOathsSpex.Story891.Criterion7541Spex do
  @moduledoc """
  Story 891 — Unit Combat
  Criterion 7541 — an attacker standing adjacent to its own lord fights
  with +2 strength: my warrior (strength 10, +2 lord aura = effective
  12) attacking a barbarian warrior (strength 15) should deal damage
  from the strength-12 band, not the plain strength-10 band.

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — "the barbarian" here is mechanically a second real
  player's warrior, produced and walked into place through the
  ordinary `GameLive.Play` surface (documented stand-in for story 892,
  `Game.Camps`, which doesn't exist yet).

  KNOWN LIMITATION: same numeric caveat as criterion 7537 — these
  bands assume the defender's strength is 15
  (`.code_my_spec/spec/broken_oaths/game/camps.spec.md`); this
  stand-in barbarian is a plain second-player `:warrior` with no
  hostility marker, so this spec may stay red even after combat lands
  until it is swapped for a real Camps-spawned barbarian.

  KNOWN LIMITATION (statistical): the strength-10 band (~18 to 31, per
  criterion 7537) and the strength-12 band computed here (~20 to 33)
  overlap — a single random combat roll cannot conclusively rule out
  "got lucky within the strength-10 band" the way a wider gap would.
  This spec asserts membership in the strength-12 band, the most
  literal single-scenario encoding of "comes from the strength-12
  band" available without a deterministic-roll test hook; a future
  reviewer may want to strengthen it with repeated trials once combat
  exists for real.

  My lord is walked next to my warrior's landed position — Lord spawn
  adjacency to the settler-turned-city gives no adjacency guarantee to
  wherever the warrior itself lands, so this is engineered with a real
  move (`queue_move`), not a fixture trick.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "fighting beside the lord" do
    scenario "the lord's aura raises the attacker's effective strength" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my warrior stands adjacent to both my lord and a barbarian", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)
        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "warrior"})

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [other_settler | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        render_hook(other_play_live, "found_city", %{"unit_id" => other_settler.id})
        [other_city] = Fixtures.player_cities(context.world, context.other_user)

        render_hook(other_play_live, "queue_production", %{
          "city_id" => other_city.id,
          "item" => "warrior"
        })

        for _ <- 1..8, do: Fixtures.advance_turn(context.world)

        [warrior] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :warrior, do: u

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :warrior,
              do: u

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id, warrior.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        render_hook(other_play_live, "queue_move", %{
          "unit_id" => barbarian.id,
          "to_tile" => barbarian_target
        })

        Enum.reduce_while(1..40, :ok, fn _, :ok ->
          [b] =
            for u <- Fixtures.player_units(context.world, context.other_user),
                u.id == barbarian.id,
                do: u

          if b.tile_id == barbarian_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == barbarian.id,
              do: u

        # Bring the lord to a free tile adjacent to my warrior — not
        # already the barbarian's tile or the warrior's own tile.
        [lord_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(warrior.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [city.tile_id, warrior.tile_id, barbarian.tile_id, lord.tile_id]))

        render_hook(play_live, "queue_move", %{"unit_id" => lord.id, "to_tile" => lord_target})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [l] =
            for u <- Fixtures.player_units(context.world, context.user),
                u.id == lord.id,
                do: u

          if l.tile_id == lord_target do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:warrior, warrior)
         |> Map.put(:barbarian, barbarian)
         |> Map.put(:warrior_hp0, warrior.hp)
         |> Map.put(:barbarian_hp0, barbarian.hp)}
      end

      when_ "my warrior attacks the barbarian", context do
        render_hook(context.play_live, "attack", %{
          "unit_id" => to_string(context.warrior.id),
          "target_unit_id" => to_string(context.barbarian.id)
        })

        {:ok, context}
      end

      then_ "the damage dealt comes from the strength-12 band, not the strength-10 band",
            context do
        [barbarian] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == context.barbarian.id,
              do: u

        dealt = context.barbarian_hp0 - barbarian.hp

        # 30 * e^(0.04 * (12 - 15)) ± 25% ≈ [19.96, 33.26]
        assert dealt >= 20 and dealt <= 33
        {:ok, context}
      end
    end
  end
end
