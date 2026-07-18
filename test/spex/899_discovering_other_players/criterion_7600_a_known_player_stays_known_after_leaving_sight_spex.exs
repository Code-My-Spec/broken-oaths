defmodule BrokenOathsSpex.Story899.Criterion7600Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7600 — a KnownPlayer record is permanent once set.
  Source: `.code_my_spec/spec/broken_oaths/game/known_player.spec.md`
  ("A discovery record: a viewer player has discovered another player
  in a world (permanent once set)"). Fog of war (story 876) still
  governs live board visibility — losing sight of the other
  civilization's units must not also erase the fact that they were
  ever discovered.

  Setup discovers the other player exactly as criterion 7597 does
  (their lord walks adjacent to mine via `Fixtures.relocate_unit/3`,
  then a turn boundary), then the `when_` sends their lord back to its
  own original spawn tile — guaranteed outside my vision, per
  criterion 7435's own tested guarantee that spawn bubbles are mutually
  private — rather than moving MY units. That keeps the "leaving
  sight" half of this scenario unambiguous regardless of where my own
  units happen to sit (my settler never moves, so relocating my own
  lord away wouldn't reliably clear their unit from every one of my
  units' vision).

  Mailbox note: `assert_push_event`'s underlying `assert_receive`
  matches the FIRST message of a given event name still queued, not
  necessarily the latest — criterion 7574's "drain the initial mount
  push before trusting a later one" idiom is followed here too: the
  mount-time and discovery-time "game:units" pushes are drained in
  `given_` so the `then_` after the retreat reads the fresh, final
  push (mirrors story 893 criterion 7552's lock-step
  trigger-then-assert pattern for the same reason).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a known player stays known after leaving sight" do
    scenario "the other civilization stays on my Known Players list after their unit walks out of sight" do
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

        # Drain the mount-time "game:units" push so a later assertion
        # can't accidentally match this stale one.
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
         |> Map.put(:other_settler, other_settler)
         |> Map.put(:other_lord_origin, other_lord.tile_id)}
      end

      given_ "the other player's civilization has already been discovered", context do
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

        # Drain the discovery-time "game:units" push too, so the
        # `then_` below reads the retreat's own fresh push.
        assert_push_event(context.play_live, "game:units", %{})

        {:ok, context}
      end

      when_ "the other player's lord walks back out of my sight and the turn advances", context do
        :ok =
          Fixtures.relocate_unit(context.world, context.other_lord.id, context.other_lord_origin)

        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "their lord no longer appears on my visible board", context do
        assert_push_event(context.play_live, "game:units", %{units: units}, 500)
        refute Enum.any?(units, &(&1.id == context.other_lord.id))
        {:ok, context}
      end

      then_ "the other player still appears in my Known Players list", context do
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
