defmodule BrokenOathsSpex.Story899.Criterion7601Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7601 — discovery unlocks chat between the two players.
  Source: stone_age.md §8.1 ("Chat unlocked between the two players
  (can now send messages)").

  Scope note: the chat surface itself — thread view, composer, message
  history — is `BrokenOathsWeb.GameLive.ChatPanel`, story 900's own
  component (`chat_panel.spec.md`: "Real-time chat panel... Surface
  for story 900"). This story's own component,
  `known_players_panel.spec.md`, only promises "listing civilizations
  the player has discovered, plus the discovery toast" — no composer.
  What THIS story owns is the unlock itself becoming visible somewhere
  a player can act on it once discovered.

  Judgment call (same status as criterion 7574's "unit-crown" marker
  call for an equally unestablished shape): a discovered player's row
  in the Known Players list carries a `data-test="chat-link"`
  affordance — the observable, panel-scoped proof that the channel is
  now open, without requiring story 900's composer to exist yet. The
  future implementer is free to rename it, but *something* actionable
  distinguishing "we can talk now" from a bare name in a list is what
  "opens the chat channel" requires.

  Setup places the OTHER player's lord adjacent to MY lord via
  `Fixtures.relocate_unit/3` — see criterion 7597's moduledoc for the
  full rationale.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "discovery opens the chat channel" do
    scenario "a discovered player's row in my Known Players list offers a way to chat with them" do
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

      then_ "no chat affordance exists for a stranger I haven't met", context do
        refute has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}'] [data-test='chat-link']"
               )

        {:ok, context}
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

      then_ "the newly discovered player's row now offers a way to chat with them", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}'] [data-test='chat-link']"
               )

        {:ok, context}
      end
    end
  end
end
