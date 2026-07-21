defmodule BrokenOathsSpex.Story919.Criterion7753Spex do
  @moduledoc """
  Story 919 — Winning, Losing, or Ending a Rebellion
  Criterion 7753 — "A rebellion ends CRUSHED when the former lord
  retakes and holds the contested cities by normal siege (906), or the
  rebel is knocked out of the fight. The normal siege/vassalization
  rules apply to the losing rebel — including being re-vassalized on
  the loss of their last city."
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round 2").

  Reuses `"declare_independence"` and `data-test="rebellion-status"`
  from criterion_7751's own moduledoc (same rationale, not repeated
  here). This criterion's own new focus, distinct from 7751's generic
  "one transition" invariant, is the RE-vassalization consequence: "the
  normal siege/vassalization rules apply... re-vassalizing him." Story
  907's vassalization trigger is ALREADY real and already has an
  established judgment call from `BrokenOathsSpex.Story906.
  Criterion7665Spex`: a pushed `"game:vassalized"` event carrying a
  `:message` string, fired the moment the losing player's last free
  city falls. This spec asserts that SAME real signal fires again here
  — "normal... rules apply" means the SAME trigger, not a new one — and
  that the rendered `vassal-status` badge (also real, story 907) reads
  "Sworn to" Mira's own email again afterward.

  Wes owns exactly one city in this batch's own standard single-city
  vassal fixture (`a_freshly_subjugated_vassal/1`), so "Wes loses his
  last city in the fight" and "Lord Mira retakes and holds the
  contested cities" are the SAME event here: Mira's second capture of
  Wes's only city. As with criterion_7751, Wes's city never actually
  rises back to him first (story 915 isn't built), so Mira's siege
  attempt below has no real rival target — expected to fail today.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "the lord retakes the cities and crushes the rebellion" do
    scenario "Mira retakes Wes's last city, crushing the rebellion and re-vassalizing him" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "Wes's rebellion is active but Lord Mira besieges and retakes and holds the contested city",
             context do
        context = a_freshly_subjugated_vassal(context)

        attempt_event(context.other_play_live, "declare_independence", %{})

        target =
          adjacent_land_tile(context.world, context.other_city.tile_id, [context.my_lord.tile_id])

        stepped_off =
          march_to(context.play_live, context.world, context.user, context.my_lord, target)

        {:ok, Map.put(context, :my_lord, stepped_off)}
      end

      when_ "Wes loses his last city in the fight", context do
        {retaken_lord, _city} =
          capture_city(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.other_user,
            context.other_city
          )

        {:ok, Map.put(context, :my_lord, retaken_lord)}
      end

      then_ "the rebellion ends with status crushed", context do
        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(fresh_wes_live, "[data-test='rebellion-status']", "crushed")

        {:ok, context}
      end

      then_ "the normal siege and vassalization rules apply to Wes, re-vassalizing him on the loss of his last city",
            context do
        # The SAME real vassalization-trigger signal established by
        # story 907 (`BrokenOathsSpex.Story906.Criterion7665Spex`) —
        # "normal rules apply" means this fires again here.
        assert_push_event(context.other_play_live, "game:vassalized", %{message: message}, 500)
        assert is_binary(message) and message != ""

        {:ok, fresh_wes_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(
                 fresh_wes_live,
                 "[data-test='vassal-status']",
                 "Sworn to Player ##{context.user.id}"
               )

        {:ok, context}
      end
    end
  end
end
