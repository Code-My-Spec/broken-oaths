defmodule BrokenOathsSpex.Story899.Criterion7599Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7599 — discovery notifies BOTH players, each in their own
  words. Source: stone_age.md §8.1's literal copy —

    * "You have discovered [Player Name]'s civilization!" (the
      discoverer's own notification)
    * "Discovered player also notified: '[Your Name] has discovered
      your civilization!'" (the discovered player's own notification,
      naming the discoverer)

  Judgment call: there is no display-name field anywhere in the
  `Users` schema (only `email`), so "[Player Name]"/"[Your Name]" are
  read as the other party's email — the only identifying string this
  codebase currently has. This spec asserts on the substance (each
  message names the OTHER party and uses the word "discovered") rather
  than pinning the exact copy, since the bracketed placeholder in the
  story text is itself evidence the literal wording isn't decided.

  Notification shape: same status as criterion 7573's "game:lineage"
  judgment call and criterion 7569's "game:alert" judgment call for an
  equally unestablished shape — a pushed `"game:discovery"` event
  carrying a `:message` string, scoped to the player it's for (mirrors
  `handle_info({:city_alert, user_id, message}, socket)`'s pattern of
  only pushing to the socket whose `user.id` matches).

  Setup places the OTHER player's lord adjacent to MY lord via
  `Fixtures.relocate_unit/3` — see criterion 7597's moduledoc for the
  full rationale (avoids a long march exposed to real, roaming
  barbarians per stories 892/893).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "discovery notifies both sides" do
    scenario "each player is notified about the other, in their own words" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "both players have joined the world, each still alone in their own spawn bubble",
             context do
        {:ok, join_live, _html} = live(context.conn, "/play")
        join_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        {:ok, other_join_live, _html} = live(context.other_conn, "/play")

        other_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, other_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [my_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        [other_lord] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :lord,
              do: u

        [other_settler] =
          for u <- Fixtures.player_units(context.world, context.other_user),
              u.type == :settler,
              do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:other_play_live, other_play_live)
         |> Map.put(:my_lord, my_lord)
         |> Map.put(:my_settler, my_settler)
         |> Map.put(:other_lord, other_lord)
         |> Map.put(:other_settler, other_settler)}
      end

      when_ "the other player's lord walks within sight of my lord and the turn advances",
            context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        occupied = [
          context.my_lord.tile_id,
          context.my_settler.tile_id,
          context.other_lord.tile_id,
          context.other_settler.tile_id
        ]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.my_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        :ok = Fixtures.relocate_unit(context.world, context.other_lord.id, target)
        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "I am told I discovered them", context do
        assert_push_event(context.play_live, "game:discovery", %{message: my_message}, 500)
        assert my_message =~ "discovered"
        assert my_message =~ context.other_user.email
        {:ok, context}
      end

      then_ "they are told I discovered them", context do
        assert_push_event(context.other_play_live, "game:discovery", %{message: their_message}, 500)
        assert their_message =~ "discovered"
        assert their_message =~ context.user.email
        {:ok, context}
      end
    end
  end
end
