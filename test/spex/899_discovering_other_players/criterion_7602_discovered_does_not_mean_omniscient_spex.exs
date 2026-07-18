defmodule BrokenOathsSpex.Story899.Criterion7602Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7602 — discovery unlocks mutual visibility only "where
  vision overlaps," not a full reveal of the other civilization.
  Source: stone_age.md §8.1 ("Both players can now see each other's
  units/cities (when in vision)") and the top-level story description
  ("mutually visible where vision overlaps"). Being on someone's Known
  Players list must not bypass ordinary fog of war (story 876) for
  every unit they own — only the ones actually within vision right
  now.

  This reuses the SAME fog-filtered mechanism criterion 7542 (story
  891, "no friendly fire") already depends on for cross-player unit
  visibility (`Game.units_visible_to/2`, pushed as `"game:units"`) —
  the ONE unit an opponent brings within my sight becomes visible, but
  a SECOND unit of theirs I never approached must not. Only the
  other player's LORD is relocated into my sight; their SETTLER is
  left exactly where it spawned — guaranteed outside my vision by
  criterion 7435's own tested guarantee that spawn bubbles are
  mutually private (lord and settler always spawn one hex apart, per
  `Game.Spawner`, so leaving the settler untouched while only the lord
  travels is what keeps it a genuinely unapproached, far unit rather
  than an accidental near-miss).

  Mailbox note: joining broadcasts `:units_changed` to every already-
  subscribed view on the world's topic (`WorldServer`'s `do_join/2`),
  so by the time both players have joined, `play_live`'s mailbox holds
  TWO "game:units" pushes — its own mount push, then a second one
  triggered by the OTHER player's later join — not just the one. Both
  are drained in `given_` before the discovery-triggering push is
  asserted in `then_`, the same two-drain idiom criterion 7600's own
  `given_` steps use (its mount-time drain, then its own explicit
  discovery-time drain before the scenario's real `when_`) —
  `assert_push_event`'s `assert_receive` matches the OLDEST queued
  message of a given event name, not necessarily the latest, so an
  under-drained mailbox hands `then_` a stale, pre-discovery snapshot
  instead of the fresh one the scenario's own `when_` produces.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "discovered does not mean omniscient" do
    scenario "only the other player's unit that actually entered my sight becomes visible" do
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

        # Drain BOTH the mount-time "game:units" push and the second
        # one the other player's own join broadcasts to this
        # already-subscribed view (see this module's Mailbox note) —
        # otherwise the second, still-own-units-only push is what the
        # `then_` below would read instead of the discovery-time one.
        assert_push_event(play_live, "game:units", %{})
        assert_push_event(play_live, "game:units", %{})

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

      when_ "only the other player's lord walks within sight of my lord and the turn advances",
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

      then_ "we are now known to each other, and only the sighted lord is visible on my board",
            context do
        assert has_element?(
                 context.play_live,
                 "[data-test='known-player-#{context.other_user.id}']",
                 context.other_user.email
               )

        assert_push_event(context.play_live, "game:units", %{units: units}, 500)
        assert Enum.any?(units, &(&1.id == context.other_lord.id))
        refute Enum.any?(units, &(&1.id == context.other_settler.id))

        {:ok, context}
      end
    end
  end
end
