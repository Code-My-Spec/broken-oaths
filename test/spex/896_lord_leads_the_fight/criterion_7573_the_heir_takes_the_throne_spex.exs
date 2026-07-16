defmodule BrokenOathsSpex.Story896.Criterion7573Spex do
  @moduledoc """
  Story 896 — Lord Leads the Fight
  Criterion 7573 — when the lord dies, the heir arrives at the
  player's capital exactly 10 turn boundaries after the death, taking
  the throne as the new lord. Leveling penalties are explicitly out of
  scope (deferred to a future leveling system per the story's Three
  Amigos notes) — this spec only covers the lineage continuing.

  "10 turn boundaries pass" is counted from the death event itself:
  `Fixtures.advance_turn/1` is called exactly 10 times right after the
  killing blow, not compared against an absolute turn number — the
  setup already burns turns producing the barbarian stand-in, and this
  spec stays agnostic to exactly how many (the running-economy
  tolerance the story calls for).

  Barbarian-fixture note: see `BrokenOathsSpex.Story891.Criterion7533Spex`'s
  moduledoc — the barbarian is a real, ownerless unit placed via
  `Fixtures.spawn_barbarian/2`. Story 893 (barbarian roaming/AI)
  doesn't exist yet, so there's no player session to drive an attack
  FROM it through the ordinary "attack" event — the barbarian is the
  attacker here, so this resolves the killing blow directly via
  `Fixtures.resolve_barbarian_attack/3` instead. The lord is weakened
  first with `Fixtures.set_unit_hp/3` — the same documented, narrow
  exception story 881's healing criteria and story 891's killing-blow
  criteria (7538/7539) already rely on — so the barbarian's attack is
  lethal regardless of the random damage roll.

  "Capital" has no modeled concept yet anywhere in the schema. This
  spec founds exactly one city, which is trivially the player's only
  (and therefore capital) city — the same simplification every other
  story 878-883 spec already makes for "the" city.

  "I was notified the lineage continues" has no established event
  shape yet. This spec's judgment call (mirroring criterion 7540's
  "game:combat" judgment call for an equally unestablished shape): a
  pushed `"game:lineage"` event carrying a `:message` string. The
  future implementer is free to rename it, but some pushed (or
  rendered) fact reaching the player is what "notified" requires.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the heir takes the throne" do
    scenario "a new lord arrives at the capital ten turns after the old one dies" do
      given_(:a_world)
      given_(:registered_player)

      given_ "my lord is near death with a barbarian beside it, and I hold a capital", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => to_string(settler.id)})
        [city] = Fixtures.player_cities(context.world, context.user)

        [lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        my_occupied = [city.tile_id, lord.tile_id]

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in my_occupied))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        # Weak enough that the barbarian's next hit is lethal, regardless
        # of the random damage roll (same documented workaround as story
        # 891's killing-blow criteria).
        Fixtures.set_unit_hp(context.world, lord.id, 1)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:lord, lord)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "the barbarian delivers the killing blow and 10 turn boundaries pass", context do
        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, context.barbarian.id, context.lord.id)

        for _ <- 1..10, do: Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "a new lord stands on my capital's tile and I was notified the lineage continues",
            context do
        [heir] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        assert heir.id != context.lord.id
        assert heir.tile_id == context.city.tile_id

        assert_push_event(context.play_live, "game:lineage", %{message: message}, 500)
        assert is_binary(message) and message != ""

        {:ok, context}
      end
    end
  end
end
