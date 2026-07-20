defmodule BrokenOathsSpex.Story906.Criterion7660Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7660 — a broken rival city the besieger never actually
  walks into is NOT captured, and its own owner can still move a fresh
  defender onto it (regarrison) before the besieger commits — "relief
  is possible... the owner or an ally can break the siege"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md` §A). This is
  `criterion_7659`'s own contrast: same broken city, but this time the
  besieger stays put — no entry, no capture.

  See `criterion_7657`'s own moduledoc for the shared `city-status`
  badge judgment call and `grind_city/6`'s regen-aware cap.

  The defending player's own Lord already spawns on a tile adjacent to
  their city's founding tile (`BrokenOaths.Simulation.Spawner`'s own doc), so
  "moves a fresh defender onto their own broken city's tile" is a
  one-hop march, not a long one — reusing `march_to/6` on `context.
  other_play_live`/`context.other_user` this time, not the besieger's.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a broken city left un-entered is not captured and can be regarrisoned" do
    scenario "the owner regarrisons a broken city the besieger never walked into" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my rival's city has been besieged down to broken, and I have NOT entered it",
             context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        broken_city =
          grind_city(
            context.play_live,
            context.world,
            my_lord,
            context.other_user,
            context.other_city
          )

        # I never move onto the city's tile — the besieger stays put,
        # exactly adjacent, for the rest of this scenario.
        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:broken_city, broken_city)
        |> then(&{:ok, &1})
      end

      when_ "the rival moves their own Lord onto their broken city's tile to regarrison it",
            context do
        [their_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        their_lord =
          march_to(
            context.other_play_live,
            context.world,
            context.other_user,
            their_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :their_lord, their_lord)}
      end

      then_ "the regarrisoning defender actually reaches the city's own tile", context do
        assert context.their_lord.tile_id == context.other_city.tile_id
        {:ok, context}
      end

      then_ "the city still reads broken, never occupied, on the owner's own panel", context do
        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "broken")
        refute has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end
    end
  end
end
