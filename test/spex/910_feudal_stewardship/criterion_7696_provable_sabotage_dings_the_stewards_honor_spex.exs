defmodule BrokenOathsSpex.Story910.Criterion7696Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7696 — "provable sabotage dings the steward's HONOR
  (engine-enforced)"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). This spec's own reading (the design doc pairs
  this directly with `criterion_7695`'s own log, "Constructive-only +
  Honor stakes keep stewardship a benefit, not a grief vector"): an
  attempt that VIOLATES the constructive-only/defensive-only whitelist
  is "provable sabotage" the moment it's attempted and logged — whether
  or not the underlying action itself is also blocked
  (`criterion_7694`'s own subject) — so this reuses that criterion's
  exact trigger (a steward trying to march an attacked owner's army off
  during the emergency window) and adds the Honor consequence on top.

  ## Honor: this criterion's own new judgment call

  No Honor ledger/UI exists ANYWHERE in this codebase yet, for any
  story (`BrokenOathsSpex.Story906.Criterion7662Spex`'s own moduledoc
  already flags this same gap for execute-a-garrison Honor loss). This
  criterion is the first that actually NEEDS Honor to be observable, so
  it introduces the surface: `data-test="player-honor"` on the
  STEWARD's own `GameLive.Play` (sibling to the existing `player-gold`
  treasury badge) — this spec only asserts it goes DOWN after the
  sabotage attempt, comparing two reads of the steward's OWN view
  before/after, never a specific starting number or delta (the design
  doc's own "Round-5 decisions": "Honor deltas are small and tunable...
  not a blocker").

  Reuses `subjugate/5`'s own `vassal_play_live` directly (rather than a
  fresh `live/2` remount) before calling `go_offline/1` on it — see
  `criterion_7689`'s own moduledoc for why a stray extra mount would
  otherwise strand the vassal "online" against `BrokenOaths.Game.
  Presence`'s own `:duplicate` Registry keys.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "provable sabotage dings the steward's Honor", fail_on_error_logs: false do
    scenario "attempting to march an attacked owner's army off during the emergency window lowers the steward's own Honor" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline and under attack, and I read my own Honor before acting",
             context do
        %{lord_play_live: lord_play_live, vassal_play_live: vassal_play_live} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        honor_before_html = render(lord_play_live)
        honor_before = Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_before_html)

        go_offline(vassal_play_live)

        [vassal_lord | _] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(vassal_lord.tile_id)
          |> Enum.filter(land?)

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, barbarian.id, vassal_lord.id)

        [vassal_lord_now] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.id == vassal_lord.id,
              do: u

        assert vassal_lord_now.hp > 0,
               "setup's own barbarian strike killed the Lord outright — nothing left to steward"

        [far_tile | _] =
          context.world
          |> Fixtures.adjacent_tiles(barbarian_target)
          |> Enum.flat_map(&Fixtures.adjacent_tiles(context.world, &1))
          |> Enum.uniq()
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in [vassal_lord_now.tile_id, barbarian_target]))

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_lord, vassal_lord_now)
        |> Map.put(:far_tile, far_tile)
        |> Map.put(:honor_before, honor_before)
        |> then(&{:ok, &1})
      end

      when_ "I, the steward, try to march the attacked Lord far away instead of defending it",
            context do
        attempt_event(context.lord_play_live, "steward_defend", %{
          "owner_user_id" => to_string(context.other_user.id),
          "unit_id" => to_string(context.vassal_lord.id),
          "to_tile" => context.far_tile
        })

        {:ok, context}
      end

      then_ "my own Honor, as the steward, reads lower than before the sabotage attempt",
            context do
        {:ok, fresh_lord_play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(fresh_lord_play_live, "[data-test='player-honor']"),
               "no \"player-honor\" element rendered yet — GameLive.Play doesn't show Honor until this story lands"

        honor_after_html = render(fresh_lord_play_live)
        [_, honor_after_text] = Regex.run(~r/data-test="player-honor"[^>]*>(-?\d+)/, honor_after_html)
        honor_after = String.to_integer(honor_after_text)

        assert context.honor_before != nil,
               "no \"player-honor\" element rendered BEFORE the sabotage attempt either — nothing to compare against"

        [_, honor_before_text] = context.honor_before
        honor_before = String.to_integer(honor_before_text)

        assert honor_after < honor_before
        {:ok, context}
      end
    end
  end
end
