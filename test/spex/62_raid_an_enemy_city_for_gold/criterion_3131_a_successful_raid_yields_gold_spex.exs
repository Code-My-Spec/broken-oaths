defmodule BrokenOathsSpex.Story1002.Criterion3131Spex do
  @moduledoc """
  Story 1002 — Raid an Enemy City for Gold
  Criterion 3131 — a successful raid yields gold.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a successful raid yields gold" do
    scenario "the raiding player sees more gold after the raid resolves" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "a wartime player can raid a rival city", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        render_hook(context.play_live, "declare_war", %{
          "counterparty_user_id" => to_string(context.other_user.id)
        })

        [lord] = for unit <- Fixtures.player_units(context.world, context.user), unit.type == :lord, do: unit
        tile = adjacent_land_tile(context.world, context.other_city.tile_id, [lord.tile_id])
        lord = march_to(context.play_live, context.world, context.user, lord, tile)
        gold_before = context.play_live |> element("[data-test='player-gold']") |> render()

        {:ok, context |> Map.put(:lord, lord) |> Map.put(:gold_before, gold_before)}
      end

      when_ "the player successfully raids the city", context do
        render_hook(context.play_live, "raid_city", %{
          "unit_id" => to_string(context.lord.id),
          "target_city_id" => to_string(context.other_city.id)
        })

        {:ok, context}
      end

      then_ "the player sees gold gained from the raid", context do
        gold_after = context.play_live |> element("[data-test='player-gold']") |> render()

        assert gold_after != context.gold_before
        {:ok, context}
      end
    end
  end
end
