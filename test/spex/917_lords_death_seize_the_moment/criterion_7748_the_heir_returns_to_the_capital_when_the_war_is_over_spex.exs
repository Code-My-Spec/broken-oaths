defmodule BrokenOathsSpex.Story917.Criterion7748Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7748 — "When the war touched off by a lord's death ends —
  the last active rebellion against the leaderless realm resolves
  (story 919) — an heir respawns at the realm's capital and lordship
  is re-established."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).

  ## Flagged conflict with the ALREADY-SHIPPED story 896 heir mechanic

  `BrokenOaths.Game.Turn`'s `schedule_heir_if_lord_fell/3`
  (`lib/broken_oaths/game/world_server.ex`) already respawns a fresh
  Lord unit at a player's capital exactly 10 turn boundaries after
  ANY Lord unit hits 0 HP — UNCONDITIONALLY, with no
  `Game.feudal_enabled?/0` gate and no awareness of Vassalage or
  Rebellion at all (`BrokenOathsSpex.Story896.Criterion7573Spex`).
  This story's own locked design instead ties heir arrival to "the
  last active rebellion against the realm resolves" — a materially
  different, war-duration-dependent trigger, not a fixed 10-turn
  clock. The two mechanics are NOT reconciled anywhere in the
  codebase yet, which is a real risk this spec surfaces rather than
  papers over: if the rebellion this scenario sets up is STILL active
  well past turn 10, the OLD unconditional mechanic would incorrectly
  spawn an heir anyway, independent of whether the new war-gated
  trigger has been implemented. This spec cannot fully discriminate
  the two mechanics on its own without a pinned "hold for N turns"
  value — explicitly still an open Three Amigos item on BOTH this
  story and story 919 ("the 'hold for N turns' threshold"). Flagging
  this for the implementer rather than fabricating a number neither
  story has locked.

  ## Operationalizing "the war ends"

  Story 919 (`Game.Rebellion`'s end transitions) doesn't exist yet
  either, so there is no dedicated "resolve rebellion" hook to drive.
  Per this story's own locked design + story 919's gherkin,
  independence is WON purely by holding every risen city for enough
  consecutive turns with no lord re-occupation — since the lord is
  dead (no counterattack is possible, `criterion_7746`), this
  scenario's own `when_` is real turn advancement only, in a bounded
  convergence loop (mirroring `BrokenOathsSpex.SharedGivens.
  grow_city_to/5`'s own halt-on-condition idiom) watching for the
  heir's own arrival, capped generously well past the old mechanic's
  10-turn window so a real (if not war-gated) implementation has room
  to resolve.

  ## "Capital" and "lordship re-established" — reused judgment calls

  Same as `BrokenOathsSpex.Story896.Criterion7573Spex`'s own
  moduledoc: "capital" has no modeled concept yet, so Mira founds
  exactly one city (trivially her capital); "lordship re-established"
  is proven the same way that spec already proves it — a genuine,
  differently-id'd Lord unit standing on the capital's own tile.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the heir returns to the capital when the war is over", fail_on_error_logs: false do
    scenario "an heir respawns at the capital once the lone rebellion against the fallen lord's realm ends" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Lord Mira's Lord unit was killed and her vassal Wes rose in rebellion, leaving the realm leaderless",
             context do
        context = a_freshly_subjugated_vassal(context)

        [mira_city] = Fixtures.player_cities(context.world, context.user)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.my_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == context.my_lord.tile_id))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)
        Fixtures.set_unit_hp(context.world, context.my_lord.id, 1)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, context.my_lord.id)

        attempt_event(context.other_play_live, "declare_independence", %{
          "lord_user_id" => to_string(context.user.id)
        })

        {:ok, Map.put(context, :mira_city, mira_city)}
      end

      when_ "Wes's rebellion reaches an ended status and no other rebellion against Mira's realm remains active",
            context do
        Enum.reduce_while(1..200, :ok, fn _, :ok ->
          heir_present? =
            context.world
            |> Fixtures.player_units(context.user)
            |> Enum.any?(&(&1.type == :lord and &1.id != context.my_lord.id))

          if heir_present? do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "an heir Lord unit respawns at Mira's realm capital", context do
        [heir] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.type == :lord,
              u.id != context.my_lord.id,
              do: u

        assert heir.tile_id == context.mira_city.tile_id,
               "the heir should respawn on Mira's own capital tile, not somewhere else"

        {:ok, context}
      end

      then_ "lordship over the realm is re-established under the heir", context do
        {:ok, mira_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [heir] =
          for u <- Fixtures.player_units(context.world, context.user),
              u.type == :lord,
              u.id != context.my_lord.id,
              do: u

        # Anchor: Mira's own board renders real content (proves the page
        # isn't simply empty/errored).
        assert has_element?(mira_live, "[data-test='player-gold']")
        assert heir.hp > 0, "the heir should be a genuine, living Lord unit, not a placeholder"

        {:ok, context}
      end
    end
  end
end
