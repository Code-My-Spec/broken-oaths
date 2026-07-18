defmodule BrokenOathsSpex.Story906.Criterion7657Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7657 — a besieger who keeps assaulting the SAME rival city
  across several turn boundaries eventually grinds its HP to 0 — and,
  unlike a barbarian's assault (story 895, `Game.CityDefense.pillage/2`),
  a broken player city STAYS at 0 HP rather than being instantly reset
  to 50 with a population loss. This is `BrokenOaths.Game.Siege`'s own
  new "broken" state — the first genuinely new mechanic this story
  introduces (`criterion_7652`-`criterion_7656` all exercise combat/
  defense math that already worked before this story landed).

  ## Judgment calls this criterion establishes for the rest of story 906

  These are shared by every later 906 criterion that touches capture
  (`criterion_7658` on); this is the first one to need them, so they're
  spelled out here once.

  1. **"Broken" is observable, not just `hp == 0`.** No UI exists for it
     yet. This spec's judgment call: a new `data-test="city-status"`
     badge on `GameLive.CityPanel` (sibling to the existing `city-hp`/
     `city-defense` badges from story 895), rendered only when the city
     isn't in its ordinary healthy state — text `"broken"` at 0 HP and
     not yet entered, `"occupied"` once a besieger has walked in
     (`criterion_7659`). A healthy city renders no such badge at all
     (`criterion_7664` relies on that absence as its own anchor).
  2. **A single swing never breaks a 100-HP city.** A size-1,
     undefended city's own defense is 20+5×1 = 25; against a Lord's
     effective strength (12), `Game.Combat.damage/3`'s curve lands
     roughly 13-22 damage per hit (30 × e^(0.04×(12-25)) × a 0.75-1.25
     roll) — several real turn boundaries (this criterion's own
     `grind_city/6` helper throws one swing per boundary) are
     mechanically REQUIRED to reach 0, independent of any single
     assertion this spec makes about turn count.
  3. Today's code has NO "broken" state at all: the instant a hit would
     take a city's HP to 0, `Game.CityDefense.take_damage/3` calls
     `pillage/2` in the SAME call, snapping HP back up to 50 with a
     population loss — a barbarian-vs-city rule (story 895) this story
     must NOT apply to a player-vs-player siege. This criterion's own
     RED signal is exactly that: `city-hp` reading `0`, not `50`, right
     after the finishing blow.

  Setup uses `BrokenOathsSpex.SharedGivens.grind_city/6` — see its own
  doc for the repeated-attack/turn-boundary loop.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "repeated assaults grind a city down to broken over several turns" do
    scenario "a besieged rival city ends up at exactly 0 HP, not pillaged back to 50" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my Lord stands adjacent to an undefended rival city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        # Un-work the founding pop's auto-assigned tile (the same real
        # in-game action `criterion_7562`, story 895, already uses) so
        # the rival city's food income stays at its bare center-only
        # floor and it never organically grows past size 1 mid-siege —
        # growth would raise `defensive_strength/2` and confound this
        # criterion's own "several turns, still breaks" claim with an
        # unrelated one about growth timing.
        case context.other_city.worked_tiles do
          [worked | _] ->
            render_hook(context.other_play_live, "assign_worked_tile", %{
              "city_id" => to_string(context.other_city.id),
              "from_tile_id" => to_string(worked)
            })

          [] ->
            :ok
        end

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "I keep assaulting the city across several turn boundaries", context do
        final_city =
          grind_city(
            context.play_live,
            context.world,
            context.my_lord,
            context.other_user,
            context.other_city
          )

        {:ok, Map.put(context, :final_city, final_city)}
      end

      then_ "the city is broken — at exactly 0 HP, not pillaged back up to 50", context do
        assert context.final_city.hp == 0

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-hp']", "0/100")
        assert has_element?(context.other_play_live, "[data-test='city-status']", "broken")
        {:ok, context}
      end

      then_ "the city still stands, still on its original owner's roster", context do
        [still_theirs] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert still_theirs.id == context.other_city.id
        {:ok, context}
      end
    end
  end
end
