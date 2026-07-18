defmodule BrokenOathsSpex.Story899.Criterion7598Spex do
  @moduledoc """
  Story 899 — Discovering Other Players
  Criterion 7598 — discovery is specifically about "another PLAYER's
  unit or city" (stone_age.md §8.1). A barbarian is an ownerless unit
  (`player_id: nil`) — the same seam `Game.Combat.hostile?/2` already
  recognizes, per `Fixtures.spawn_barbarian/2`'s own moduledoc note in
  criterion 7542. Sighting one must not fabricate a Known Players
  entry: there is no civilization behind it to discover.

  Single real player only — deliberately. The whole point is that an
  ownerless unit sighted in isolation never creates a KnownPlayer
  record, so a second real player would only muddy what's being
  proven.

  See criterion 7597's moduledoc for the "known-player-<user id>" /
  "known-players-empty" data-test judgment call this spec reuses.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "sighting a barbarian is not discovering a player" do
    scenario "a barbarian standing in my lord's sight never becomes a Known Player" do
      given_(:a_world)
      given_(:registered_player)

      given_ "I have joined the world with my lord standing alone", context do
        {:ok, join_live, _html} = live(context.conn, "/play")
        join_live |> element("[data-test='join-world-#{context.world.id}']") |> render_click()
        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        [my_settler] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:my_lord, my_lord)
         |> Map.put(:my_settler, my_settler)}
      end

      then_ "my Known Players list starts empty", context do
        assert has_element?(context.play_live, "[data-test='known-players-empty']")
        {:ok, context}
      end

      when_ "a barbarian appears within my lord's sight and the turn advances", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end
        occupied = [context.my_lord.tile_id, context.my_settler.tile_id]

        [target | _] =
          context.world
          |> Fixtures.adjacent_tiles(context.my_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 in occupied))

        _barbarian = Fixtures.spawn_barbarian(context.world, target)
        Fixtures.advance_turn(context.world)

        {:ok, context}
      end

      then_ "my Known Players list is still empty — no civilization was discovered", context do
        assert has_element?(context.play_live, "[data-test='known-players-empty']")
        {:ok, context}
      end
    end
  end
end
