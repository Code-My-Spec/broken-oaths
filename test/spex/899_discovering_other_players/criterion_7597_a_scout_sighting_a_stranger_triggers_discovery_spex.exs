defmodule BrokenOathsSpex.Story899.Criterion7597Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7597 — the moment one player's unit vision reaches another
  player's unit, first contact fires and the sighted civilization
  appears in the sighting player's Known Players list. Source:
  stone_age.md §8.1 ("When player's units gain vision of another
  player's unit or city, notification appears") and
  `.code_my_spec/spec/broken_oaths/game/discovery.spec.md`
  ("Detects first-contact when a player's vision reveals another
  player's unit or city; records KnownPlayer both ways").

  "Scout" has no literal unit type in this game (no Scout production
  item exists anywhere in `Game.Production`) — the Lord (vision radius
  3, the largest of any unit type per `Game.Visibility.vision_radius/1`)
  stands in as the reconnaissance unit, the same generic reading the
  story's own prose gives the word.

  Setup places the OTHER player's lord adjacent to MY lord (rather
  than marching mine to them) via `Fixtures.relocate_unit/3` — the
  same narrow, documented test-only bridge criterion 7542's moduledoc
  already establishes for cross-player adjacency, avoiding a long
  march exposed to real, roaming barbarians (stories 892/893).
  Discovery is assumed to be evaluated at a turn boundary, the same
  place every other cross-player/AI decision in this codebase already
  resolves (heir succession, city alerts, barbarian AI) — the `when_`
  triggers one `Fixtures.advance_turn/1` after the sighting unit is in
  place.

  Judgment call (same status as criterion 7573's "game:lineage" call
  for an equally unestablished shape, and `known_players_panel.spec.md`'s
  own "plus the discovery toast" framing for this exact component):
  the Known Players roster is DOM, not canvas — per the board doctrine,
  it is asserted via `has_element?/3` rather than a push event.
  "known-player-<user id>" per row, "known-players-empty" when nobody
  has been discovered yet. There is
  no display-name field anywhere in the `Users` schema (only `email`),
  so a row's identifying text is the other player's email.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a scout sighting a stranger triggers discovery" do
    scenario "another player's lord walking into my lord's sight adds them to my Known Players list" do
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

      then_ "the other player does not yet appear in my Known Players list", context do
        refute has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']"
               )

        assert has_element?(context.play_live, "[data-test='known-players-empty']")
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

      then_ "the other player's civilization now appears in my Known Players list", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']",
                 context.other_user.email
               )

        {:ok, context}
      end
    end
  end
end
