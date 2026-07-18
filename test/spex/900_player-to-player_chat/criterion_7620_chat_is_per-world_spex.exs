defmodule BrokenOathsSpex.Story900.Criterion7620Spex do
  @moduledoc """
  Story 900 — Player-to-Player Chat
  Criterion 7620 — chat is per-world: two players can share more than
  one world at once (`GameLive.Join`'s membership-limit error implies
  up to three), and discovering each other in one world must not
  unlock chat in another world where they've never crossed paths —
  chat availability is scoped to the world the discovery happened in,
  the same way region/exploration state already is (story 876/877).

  See `Criterion7604Spex`'s moduledoc for the assumed ChatPanel surface
  contract this spec drives. This spec doesn't use the
  `:two_players_discovered_each_other` shared given because it needs
  the scout-until-visible sequence run against one specific world
  (`context.world_one`) while a second world (`context.world_two`)
  is only ever joined, never scouted.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "chat is per-world" do
    scenario "a discovery in one world doesn't unlock chat in another" do
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "two separate worlds exist", context do
        world_one = Fixtures.world_fixture(%{seed: 424_242})
        world_two = Fixtures.world_fixture(%{seed: 646_464})

        {:ok, context |> Map.put(:world_one, world_one) |> Map.put(:world_two, world_two)}
      end

      given_ "both players joined and discovered each other in world one", context do
        for conn <- [context.conn, context.other_conn] do
          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world_one.id}']")
          |> render_click()
        end

        {:ok, play_live, _html} = live(context.conn, ~p"/play/#{context.world_one.id}")

        [lord | _] =
          for u <- Fixtures.player_units(context.world_one, context.user), u.type == :lord, do: u

        [stranger | _] = Fixtures.player_units(context.world_one, context.other_user)

        render_hook(play_live, "queue_move", %{
          "unit_id" => lord.id,
          "to_tile" => stranger.tile_id
        })

        seen? =
          Enum.reduce_while(1..30, false, fn _, _ ->
            Fixtures.advance_turn(context.world_one)
            assert_push_event(play_live, "game:units", %{units: units}, 1000)

            if Enum.any?(units, &(&1.id == stranger.id)),
              do: {:halt, true},
              else: {:cont, false}
          end)

        assert seen?, "the lord never scouted within sight of the other player's unit"

        {:ok, context}
      end

      given_ "both players also joined world two, but never scouted there", context do
        for conn <- [context.conn, context.other_conn] do
          {:ok, join_live, _html} = live(conn, ~p"/play")

          join_live
          |> element("[data-test='join-world-#{context.world_two.id}']")
          |> render_click()
        end

        {:ok, context}
      end

      when_ "the player opens the chat panel in world one", context do
        {:ok, play_live_one, _html} = live(context.conn, ~p"/play/#{context.world_one.id}")

        play_live_one
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :play_live_one, play_live_one)}
      end

      then_ "the discovered player is reachable from world one's chat", context do
        assert has_element?(
                 context.play_live_one,
                 "[data-test='known-player-#{context.other_user.id}']"
               )

        {:ok, context}
      end

      when_ "the player opens the chat panel in world two", context do
        {:ok, play_live_two, _html} = live(context.conn, ~p"/play/#{context.world_two.id}")

        play_live_two
        |> element("[data-test='chat-button']")
        |> render_click()

        {:ok, Map.put(context, :play_live_two, play_live_two)}
      end

      then_ "the same player is NOT reachable from world two's chat", context do
        refute has_element?(
                 context.play_live_two,
                 "[data-test='known-player-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
