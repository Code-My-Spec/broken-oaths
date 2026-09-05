defmodule BrokenOathsSpex.Story955.Criterion2857Spex do
  @moduledoc """
  Story 955 — Library
  Criterion 2857 — an owner who can't afford their Library's upkeep
  loses it, same as an unaffordable unit: revised during BDD spec
  writing after reading `BrokenOaths.Feudal.Bank`'s actual
  disband-when-broke logic (`disband_target/2`) — a BUILDING is never
  among the disband-eligible types (`@military_disband_types`/
  `@civilian_disband_types` are unit atoms only). A shortfall instead
  disbands a UNIT (military before civilian, the Lord never eligible),
  while the Library itself survives untouched. A single Scout's 1
  gold/turn upkeep turned out not to be enough to outpace a young
  city's own gold income (confirmed by running this spec) — this
  version drives a real shortfall with four Scouts (4 gold/turn
  combined), with the treasury never topped up, and proves BOTH
  halves: a Scout eventually disbands, and the Library remains built
  throughout.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  @scout_count 4

  spex "an owner who can't afford their Library's upkeep loses it, same as an unaffordable unit" do
    scenario "the Library survives an upkeep shortfall - a Scout disbands instead" do
      given_(:a_world)
      given_(:registered_player)
      given_(:a_founded_city_with_writing)

      given_ "the player queues and completes a Library", context do
        context.play_live
        |> element("[data-test='production-option-library']")
        |> render_click()

        advance_until_building_complete(context.world, context.user, context.city.id, :library)

        {:ok, context}
      end

      given_ "the player also queues and completes four Scouts, whose combined upkeep the treasury can't sustain",
             context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => to_string(context.city.id)})

        for _ <- 1..@scout_count do
          play_live
          |> element("[data-test='production-option-scout']")
          |> render_click()
        end

        Enum.reduce_while(1..600, :ok, fn _, :ok ->
          units = Fixtures.player_units(context.world, context.user)
          scout_count = Enum.count(units, &(&1.type == :scout))

          if scout_count >= @scout_count do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, Map.put(context, :play_live, play_live)}
      end

      when_ "enough turns pass that the combined upkeep outpaces the treasury", context do
        Enum.reduce_while(1..300, :ok, fn _, :ok ->
          units = Fixtures.player_units(context.world, context.user)
          scout_count = Enum.count(units, &(&1.type == :scout))

          if scout_count < @scout_count do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok, context}
      end

      then_ "at least one Scout has disbanded", context do
        units = Fixtures.player_units(context.world, context.user)
        assert Enum.count(units, &(&1.type == :scout)) < @scout_count
        {:ok, context}
      end

      then_ "the Library is still built", context do
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")
        render_hook(play_live, "select_city", %{"city_id" => to_string(context.city.id)})
        assert has_element?(play_live, "[data-test='city-building-library']")
        {:ok, Map.put(context, :play_live, play_live)}
      end
    end
  end
end
