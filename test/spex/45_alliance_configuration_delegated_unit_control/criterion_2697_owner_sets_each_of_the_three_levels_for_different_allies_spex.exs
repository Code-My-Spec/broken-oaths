defmodule BrokenOathsSpex.Story947.Criterion2697Spex do
  @moduledoc """
  Story 947 — Alliance Configuration: delegated unit control
  Criterion 2697 — steward eligibility differs per relationship, not
  per a manually-configured "level": `BrokenOaths.Feudal.Stewardship.
  steward_role/4` resolves an ACCEPTED ally as automatically eligible
  to steward (the real surface — emergency defense, bank sweep,
  opted-in production; see criterion 2701/2709's own moduledoc for why
  unrestricted "Full" control never exists for anyone), while a player
  with no accepted alliance is `:none` — not eligible for anything.
  There is no separate `set_delegated_control`/level to configure; the
  relationship itself is the grant. This criterion proves the SAME
  owner has both an eligible accepted ally and an ineligible stranger
  side by side.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "an owner's steward eligibility differs for an accepted ally vs. an unrelated player",
    fail_on_error_logs: false do
    scenario "the accepted ally may steward me; the unrelated player may not" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "I am accepted allies with one player and have no relationship with another", context do
        %{play_live_a: owner_live, play_live_b: ally_live} =
          establish_accepted_alliance(
            context.world,
            context.conn,
            context.user,
            context.other_conn,
            context.other_user
          )

        [my_settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(owner_live, "found_city", %{"unit_id" => to_string(my_settler.id)})

        go_offline(owner_live)

        {:ok, stranger_join, _html} = live(context.third_conn, "/play")

        stranger_join
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, stranger_live, _html} = live(context.third_conn, "/play/#{context.world.id}")

        Fixtures.advance_turn(context.world)
        banked0 = Fixtures.bank_status(context.world, context.user).gold
        assert banked0 > 0
        treasury0 = Fixtures.gold(context.world, context.user)

        context
        |> Map.put(:ally_live, ally_live)
        |> Map.put(:stranger_live, stranger_live)
        |> Map.put(:banked0, banked0)
        |> Map.put(:treasury0, treasury0)
        |> then(&{:ok, &1})
      end

      when_ "the accepted ally stewards my bank, and the unrelated player tries to steward my production",
            context do
        # `steward_collect_bank`'s own handler never surfaces a
        # `steward_error` toast either way (it ignores the result) —
        # `steward_queue_production` is used for the stranger's refusal
        # instead, since ITS handler does check and display the reason.
        # Eligibility is checked first, before the city/item even
        # exist, so the placeholder ids below never matter.
        attempt_event(context.stranger_live, "steward_queue_production", %{
          "owner_user_id" => to_string(context.user.id),
          "city_id" => "0",
          "item" => "warrior"
        })

        attempt_event(context.ally_live, "steward_collect_bank", %{
          "owner_user_id" => to_string(context.user.id)
        })

        {:ok, context}
      end

      then_ "only the accepted ally's stewardship actually moved my gold", context do
        assert Fixtures.gold(context.world, context.user) ==
                 context.treasury0 + context.banked0

        assert Fixtures.bank_status(context.world, context.user).gold == 0
        {:ok, context}
      end

      then_ "the unrelated player is told they aren't eligible", context do
        assert has_element?(context.stranger_live, "[data-test='steward-error']", "eligible")
        {:ok, context}
      end
    end
  end
end
