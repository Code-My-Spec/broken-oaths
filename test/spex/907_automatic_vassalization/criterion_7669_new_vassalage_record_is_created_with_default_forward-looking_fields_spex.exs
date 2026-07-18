defmodule BrokenOathsSpex.Story907.Criterion7669Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7669 — the Vassalage relationship record is created with
  its default forward-looking fields, not a bare "vassal or not" flag:
  "tribute rate (default 25%)... Oath Strain/liberty pressure (0-100)...
  Honor ledger hooks, agenda, and the reciprocal contract terms...
  Built this batch carrying the forward-looking fields so the rebellion
  batch doesn't rebuild it"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-5
  decisions").

  ## What this spec can actually observe, and what it deliberately can't

  A spex `then_` may only read the public surface (rendered HTML,
  pushed events) — never the schema/DB directly (this project's own
  `bdd/spex.md` boundary doc). Of the fields the design doc lists, only
  ONE has an established, story-mandated UI surface this batch: the
  tribute rate, via "You see them in your Vassals list with tribute
  settings" (`.code_my_spec/stories/more_stories.md` §7.1). This spec's
  own judgment call: the lord's `vassal-row` (see
  `BrokenOathsSpex.Story907.Criterion7666Spex`'s own moduledoc) carries
  a sibling `data-test="vassal-tribute-rate"` element reading `"25%"`
  for a freshly-created vassal — the DEFAULT this criterion actually
  asks for.

  Oath Strain, Honor hooks, and the reciprocal contract terms have NO
  established UI anywhere in this batch (Oath Strain accrual and the
  Protection Pact are explicitly a LATER batch per the design doc's own
  "What ships in THIS (foundation) batch vs later" section) — this spec
  does not invent surfaces for them; `criterion_7668` already covers
  the one forward-looking field THIS batch does surface end-to-end
  (the Hidden Agenda choice).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a new Vassalage record is created with its default tribute rate" do
    scenario "a freshly-created vassal's row shows the default 25% tribute rate" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my rival's last free city stands broken, and my Lord is adjacent", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        grind_city(
          context.play_live,
          context.world,
          my_lord,
          context.other_user,
          context.other_city
        )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "I capture their last free city, creating the Vassalage record", context do
        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      then_ "the new vassal's row on my Vassals list defaults to a 25% tribute rate", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}'] [data-test='vassal-tribute-rate']",
                 "25%"
               )

        {:ok, context}
      end
    end
  end
end
