defmodule BrokenOathsSpex.Story917.Criterion7750Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7750 — "If a lord's Lord unit dies with no rebellion
  raised against the realm at all, the heir respawns after a short
  fixed delay rather than waiting on a war that never came."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  ## Flagged ambiguity — the exact delay value is an open Three
  Amigos item

  The story's own "Three Amigos" note explicitly lists "the no-rebellion
  short-delay value" as still open. This spec does NOT assert a
  specific turn count for that reason — asserting an unpinned number
  would be fabricating a rule the story doesn't state. It instead
  asserts the two things the criterion's own text DOES commit to: (a)
  the heir eventually arrives WITHOUT ever waiting on a rebellion (no
  `declare_independence` is ever driven anywhere in this scenario, and
  no vassal even exists — "a single lord dies, nobody rises" is the
  simplest reading of "not a single vassal raises a rebellion"), and
  (b) the realm is left fully intact (no city lost, nothing to
  reconquer) once the heir arrives. The wait loop is bounded generously
  (60 turns) as a ceiling, not a locked value.

  ## Note — this criterion may already be (coincidentally) satisfied

  `BrokenOaths.Simulation.Turn`'s already-shipped `schedule_heir_if_lord_fell/3`
  (story 896, unconditional, no `Vassalage`/`Rebellion` awareness at
  all — see `criterion_7748`'s own moduledoc) already respawns an
  heir exactly 10 turns after ANY Lord unit's death, regardless of
  vassals. For a lord with NO vassals at all — this scenario — that
  legacy mechanic already produces the exact externally-observable
  shape this criterion asks for (heir at capital, realm intact, no war
  waited on). Unlike `criterion_7748`/`criterion_7749`, this criterion
  does not depend on the NEW rebellion-gated trigger at all, so it is
  not expected to be as reliably RED as its siblings — flagging this
  rather than engineering an artificial failure, per this batch's own
  "don't soften, but don't fabricate a failure either" instruction.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a quiet death still brings an heir, after a short delay", fail_on_error_logs: false do
    scenario "a lone lord's death with no rebellion raised still respawns an heir at the capital" do
      given_(:a_world)
      given_(:registered_player)

      given_ "Lord Mira's Lord unit is killed but not a single vassal raises a rebellion", context do
        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
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
        Fixtures.set_unit_hp(context.world, lord.id, 1)

        {:ok, _result} = Fixtures.resolve_barbarian_attack(context.world, barbarian.id, lord.id)

        # No vassal exists and no `declare_independence` is ever driven
        # here — "not a single vassal raises a rebellion" in its
        # simplest, most literal reading.

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:city, city)
         |> Map.put(:lord, lord)}
      end

      when_ "the short fixed delay passes", context do
        Enum.reduce_while(1..60, :ok, fn _, :ok ->
          heir_present? =
            context.world
            |> Fixtures.player_units(context.user)
            |> Enum.any?(&(&1.type == :lord and &1.id != context.lord.id))

          if heir_present? do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "the heir respawns at the capital with the realm fully intact", context do
        [heir] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.type == :lord,
              u.id != context.lord.id,
              do: u

        assert heir.tile_id == context.city.tile_id,
               "the heir should respawn on the lone lord's own capital tile"

        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.user),
              c.id == context.city.id,
              do: c

        assert Map.get(city_now, :status, :free) == :free,
               "the realm's only city should still be fully the player's own — nothing to reconquer since no war ever happened"

        {:ok, context}
      end

      then_ "lordship resumes without ever having waited on a war", context do
        {:ok, mira_live, _html} = live(context.conn, "/play/#{context.world.id}")

        refute has_element?(mira_live, "[data-test='vassals-list']"),
               "there were never any vassals to begin with — the heir's return isn't gated on any rebellion resolving"

        assert has_element?(mira_live, "[data-test='player-gold']")

        {:ok, context}
      end
    end
  end
end
