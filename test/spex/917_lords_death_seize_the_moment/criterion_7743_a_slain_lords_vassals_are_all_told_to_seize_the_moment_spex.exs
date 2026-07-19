defmodule BrokenOathsSpex.Story917.Criterion7743Spex do
  @moduledoc """
  Story 917 — Lord's Death — Seize the Moment
  Criterion 7743 — "When a lord's Lord unit is killed in combat by
  anyone, every vassal of that lord is immediately notified with a
  prominent prompt: 'Your lord has fallen — seize the moment.'"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, story 917).
  The prompt must also link directly to the Declare Independence
  action (story 915).

  Nothing in this pipeline exists yet: `grep -rn seize_the_moment
  lib/` and `grep -rn declare_independence lib/` both come back empty
  (the same fact `BrokenOathsSpex.Story913.Criterion7725Spex`'s own
  moduledoc already documents for `declare_independence`). This spec
  is expected to fail red until the notification and its DOM surface
  land.

  ## Judgment calls (flagged — the story's own Three Amigos note
  explicitly leaves "the notification/modal copy and dwell" open)

  1. **"Killed in combat by anyone"** — a real, ownerless barbarian
     delivers the killing blow, the same documented narrow-exception
     lethal setup `BrokenOathsSpex.Story896.Criterion7573Spex`
     (the pre-vassalage heir spec) and `BrokenOathsSpex.Story891.
     Criterion7539Spex` already rely on
     (`Fixtures.set_unit_hp/3` + `Fixtures.resolve_barbarian_attack/3`).
     The rule's own text is "by anyone," so an ownerless barbarian
     unambiguously qualifies without needing a second full player
     session just to be the killer.
  2. **DOM shape of the prompt** — since "the prompt links directly to
     the Declare Independence action" requires more than a fire-once
     toast (it must remain clickable/actionable, not merely announce),
     this spec asserts a PERSISTENT rendered element,
     `data-test="seize-the-moment-prompt"`, on the vassal's own
     `GameLive.Play` mount, carrying the literal locked copy "Your
     lord has fallen — seize the moment" and containing a nested
     `data-test="declare-independence-action"` link/button. A future
     implementer is free to ALSO push a one-shot toast (mirroring
     `"game:lineage"`/`"game:alert"`) as long as this durable,
     re-mountable element also exists — "seize the moment" implies a
     standing invitation the player can act on whenever they return,
     not a message that vanishes if they miss it.
  3. **Three vassals, one lord** — mirrors
     `BrokenOathsSpex.Story908.Criterion7679Spex`'s own "world with
     room for four players" / inline-per-vassal subjugation loop,
     reused verbatim here (lord + 3 vassals = 4 players).
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "a slain lord's vassals are all told to seize the moment", fail_on_error_logs: false do
    scenario "each of three vassals sees a prominent seize-the-moment prompt linking to Declare Independence" do
      given_ "a world with room for four players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 7, frequency: 10}))}
      end

      given_(:registered_player)

      given_ "a lord holds three vassals across the world", context do
        vassals =
          for _ <- 1..3 do
            other_user = Fixtures.user_fixture()

            conn =
              Phoenix.ConnTest.build_conn()
              |> BrokenOathsTest.ConnCase.log_in_user(other_user)

            vassal_context =
              context
              |> Map.put(:other_user, other_user)
              |> Map.put(:other_conn, conn)
              |> join_and_found_rival_city()

            :ok = clear_all_camps(context.world)

            [my_lord] =
              for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

            target =
              adjacent_land_tile(
                context.world,
                vassal_context.other_city.tile_id,
                [my_lord.tile_id]
              )

            my_lord =
              march_to(
                vassal_context.play_live,
                context.world,
                context.user,
                my_lord,
                target,
                150
              )

            {my_lord, _broken_city} =
              capture_city(
                vassal_context.play_live,
                context.world,
                context.user,
                my_lord,
                other_user,
                vassal_context.other_city
              )

            %{user: other_user, conn: conn, city: vassal_context.other_city, my_lord: my_lord}
          end

        {:ok, Map.put(context, :vassals, vassals)}
      end

      given_ "the lord's Lord unit is engaged by a rival army", context do
        [%{my_lord: last_lord}] = Enum.take(context.vassals, -1)

        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        [barbarian_target | _] =
          context.world
          |> Fixtures.adjacent_tiles(last_lord.tile_id)
          |> Enum.filter(land?)
          |> Enum.reject(&(&1 == last_lord.tile_id))

        barbarian = Fixtures.spawn_barbarian(context.world, barbarian_target)

        # Weak enough that the barbarian's next hit is lethal, regardless
        # of the random damage roll — the same documented lethal-setup
        # exception story 891/896's own killing-blow criteria rely on.
        Fixtures.set_unit_hp(context.world, last_lord.id, 1)

        {:ok,
         context
         |> Map.put(:lord_unit, last_lord)
         |> Map.put(:barbarian, barbarian)}
      end

      when_ "the Lord unit is killed in combat", context do
        {:ok, _result} =
          Fixtures.resolve_barbarian_attack(context.world, context.barbarian.id, context.lord_unit.id)

        {:ok, context}
      end

      then_ "each of the three vassals receives a prominent \"Your lord has fallen — seize the moment\" prompt",
            context do
        for %{user: vassal_user, conn: vassal_conn} <- context.vassals do
          {:ok, vassal_live, _html} = live(vassal_conn, "/play/#{context.world.id}")

          assert has_element?(
                   vassal_live,
                   "[data-test='seize-the-moment-prompt']",
                   "Your lord has fallen — seize the moment"
                 ),
                 "vassal #{vassal_user.email} never saw the seize-the-moment prompt"
        end

        {:ok, context}
      end

      then_ "the prompt links directly to the Declare Independence action", context do
        for %{conn: vassal_conn} <- context.vassals do
          {:ok, vassal_live, _html} = live(vassal_conn, "/play/#{context.world.id}")

          assert has_element?(
                   vassal_live,
                   "[data-test='seize-the-moment-prompt'] [data-test='declare-independence-action']"
                 )
        end

        {:ok, context}
      end
    end
  end
end
