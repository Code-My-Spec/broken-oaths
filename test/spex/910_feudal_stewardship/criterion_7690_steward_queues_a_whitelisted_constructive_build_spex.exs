defmodule BrokenOathsSpex.Story910.Criterion7690Spex do
  @moduledoc """
  Story 910 — Feudal Stewardship
  Criterion 7690 — "PRODUCTION STEWARDSHIP: a steward may set the
  offline player's production queue, CONSTRUCTIVE-ONLY — from a safe
  whitelist of economic/defensive builds"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Feudal
  Stewardship (910)"). This is the allowed half: a Warrior (a
  defensive, already-buildable item, story 881) queued by the steward
  actually lands in the offline vassal's own production queue.
  `criterion_7691` is the disallowed half (disband/cancel).

  ## This criterion's own new judgment call

  `"steward_queue_production"`, `%{"owner_user_id" => ..., "city_id" =>
  ..., "item" => "warrior"}` — mirrors `Game.queue_production/4`'s own
  `"queue_production"` param shape exactly (`"city_id"`/`"item"`),
  scoped through stewardship instead of straight ownership. Driven
  through `attempt_event/3` since no `handle_event/3` clause exists for
  it yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the steward queues a whitelisted constructive build", fail_on_error_logs: false do
    scenario "a lord stewards a Warrior into their offline vassal's empty production queue" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my vassal is offline with an empty production queue in their own city", context do
        %{lord_play_live: lord_play_live, vassal_city: vassal_city} =
          subjugate(context.world, context.conn, context.user, context.other_conn, context.other_user)

        {:ok, vassal_play_live, _html} = live(context.other_conn, "/play/#{context.world.id}")
        go_offline(vassal_play_live)

        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == vassal_city.id,
              do: c

        assert city_now.queue == []

        context
        |> Map.put(:lord_play_live, lord_play_live)
        |> Map.put(:vassal_city, vassal_city)
        |> then(&{:ok, &1})
      end

      when_ "I steward a Warrior into their production queue", context do
        attempt_event(context.lord_play_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.other_user.id),
          "city_id" => to_string(context.vassal_city.id),
          "item" => "warrior"
        })

        {:ok, context}
      end

      then_ "the vassal's own city now has a Warrior queued", context do
        [city_now] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.vassal_city.id,
              do: c

        assert city_now.queue != [],
               "no production item queued at all — the steward's build order never took"

        [current | _] = city_now.queue
        assert current.type == :warrior
        {:ok, context}
      end
    end
  end
end
