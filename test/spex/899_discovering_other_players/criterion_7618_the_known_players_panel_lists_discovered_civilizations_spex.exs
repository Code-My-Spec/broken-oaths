defmodule BrokenOathsSpex.Story899.Criterion7618Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7618 — the Known Players panel itself lists every
  civilization the player has discovered. Source: stone_age.md §8.1
  ("Discovered player shown in 'Known Players' list") and
  `known_players_panel.spec.md` ("Standalone panel listing
  civilizations the player has discovered").

  Distinct from criterion 7597 (which checks the TRANSITION — the
  moment sighting happens, the entry appears) — this criterion checks
  the panel's steady-state RENDERING once discovery has already
  happened: the row exists, is identifiable, and the panel's
  empty-state is gone. See criterion 7597's moduledoc for the
  "known-player-<user id>" / "known-players-empty" data-test judgment
  call this spec reuses.

  Setup places the OTHER player's lord adjacent to MY lord via
  `Fixtures.relocate_unit/3` — see criterion 7597's moduledoc for the
  full rationale.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the Known Players panel lists discovered civilizations" do
    scenario "the panel shows the discovered player's civilization once first contact is made" do
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

      then_ "the panel's empty state is gone", context do
        refute has_element?(context.play_live, "[data-test='known-players-empty']")
        {:ok, context}
      end

      then_ "the panel lists the discovered player's civilization by name", context do
        # Playtest issue 2a9df843: the row shows the player-facing display
        # name (here the "Player #N" fallback, since the fixture set none),
        # never the raw email.
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']",
                 "Player ##{context.other_user.id}"
               )

        refute render(context.play_live) =~ context.other_user.email

        {:ok, context}
      end
    end
  end
end
