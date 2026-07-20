defmodule BrokenOathsSpex.Story907.Criterion7666Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7666 — capturing a rival's ONLY (last free) city creates
  the Vassalage relationship: "when you take a player's last city, you
  do not eliminate them — they swear a... oath of fealty and keep
  playing as your vassal"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "The one-line
  pitch"). This is 907's own acceptance test that the RELATIONSHIP
  itself gets created and surfaces in both players' UIs, building on
  story 906's own capture mechanic (`BrokenOaths.Combat.Siege`) — see
  `BrokenOathsSpex.Story906.Criterion7659Spex`'s own moduledoc for why
  an ungarrisoned broken city's tile is already walkable today with no
  collision refusal (the capture itself, and everything downstream of
  it including this story's own vassalage relationship, is what's
  missing).

  ## New judgment calls this story establishes

  No Vassalage UI exists anywhere yet. This spec's judgment calls,
  shared by every later 907 criterion:

  1. **The lord's own "Vassals" list**: `data-test="vassals-list"` on
     `GameLive.Play`, containing one `data-test="vassal-row-<vassal
     user id>"` row per vassal, rendering the vassal's own
     `user.email` (the established "identify a player" convention —
     see `BrokenOathsWeb.GameLive.KnownPlayersPanel`, story 899:
     `data-test="known-player-<id>"` with `user.email` text).
  2. **The vassal's own "Sworn to" badge**: `data-test="vassal-status"`
     on `GameLive.Play`, rendering their lord's own `user.email`.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "losing the last free city triggers vassalization" do
    scenario "capturing a rival's only city creates the Vassalage relationship, visible to both" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "the rival's only city stands broken, and my Lord is adjacent", context do
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

      when_ "I walk my Lord onto the tile, capturing their last free city", context do
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

      then_ "the lord's own Vassals list gains the new vassal", context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        assert has_element?(
                 context.play_live,
                 "[data-test='vassal-row-#{context.other_user.id}']",
                 context.other_user.email
               )

        {:ok, context}
      end

      then_ "the vassal's own view shows they're sworn to the lord", context do
        assert has_element?(
                 context.other_play_live,
                 "[data-test='vassal-status']",
                 context.user.email
               )

        {:ok, context}
      end
    end
  end
end
