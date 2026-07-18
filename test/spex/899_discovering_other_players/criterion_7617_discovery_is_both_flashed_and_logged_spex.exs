defmodule BrokenOathsSpex.Story899.Criterion7617Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7617 — the discovery notification takes two distinct
  forms: an immediate, ephemeral flash/toast at the moment of first
  contact, AND a durable record the player can still find afterward.
  Source: `known_players_panel.spec.md`'s own framing — "Standalone
  panel listing civilizations the player has discovered, PLUS the
  discovery toast" — names both halves as this component's job.

  This is deliberately distinct from criterion 7599 (which checks that
  BOTH players are notified, each with their own wording) and
  criterion 7618 (which checks the roster's steady-state content).
  7617's own subject is the DUALITY: the same discovery event must be
  observable two different ways, not just once.

  Judgment call for the "flashed" half (same status as criterion
  7573's "game:lineage" call): a pushed `"game:discovery"` event
  carrying a `:message` string — the ephemeral signal, fired once at
  the moment of contact.

  The "logged" half is operationalized as: the fact of discovery
  survives leaving the page entirely and mounting a brand new
  LiveView process for the same world — proving it is durable,
  reconstructible state (a persisted `KnownPlayer` record, per
  `known_player.spec.md`), not merely something painted once into the
  socket assigns of the connection that happened to be open when it
  fired.

  Setup places the OTHER player's lord adjacent to MY lord via
  `Fixtures.relocate_unit/3` — see criterion 7597's moduledoc for the
  full rationale.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "discovery is both flashed and logged" do
    scenario "discovery arrives as an immediate toast and remains on record after I leave and return" do
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

      then_ "I see an immediate toast about the discovery", context do
        assert_push_event(context.play_live, "game:discovery", %{message: message}, 500)
        assert message =~ "discovered"
        {:ok, context}
      end

      then_ "the discovery is still on record after I leave and come back", context do
        {:ok, revisited_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(
                 revisited_live,
                 "[data-test='known-player-#{context.other_user.id}']",
                 context.other_user.email
               )

        {:ok, context}
      end
    end
  end
end
