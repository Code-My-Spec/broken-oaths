defmodule BrokenOathsSpex.Story905.Criterion7648Spex do
  @moduledoc """
  Story 905 — Tile Resources
  Criterion 7648 — Pasture is only offered once Animal Husbandry is
  researched (`BrokenOaths.Technology.Research.pasture_enabled?/1`, story
  902's own exact spec — see that module's moduledoc: "story 905
  (Pasture/resources) should read `pasture_enabled?/1`"). Before the
  tech completes, a worker standing on an eligible (Cattle/Sheep) tile
  is offered Farm/Mine/Road only, never Pasture — same "only legal
  builds render" contract `GameLive.UnitPanel`'s `allowed_improvements`
  already enforces for story 882 (criterion 7482: Farm never offered on
  hills/forest).

  Reuses story 902's OWN established `TechPanel` surface contract
  exactly (`"toggle_tech_panel"` + `"select_research"`,
  `[data-test='tech-completed-<name>']`) — see
  `BrokenOathsSpex.Story902.Criterion7625Spex`'s moduledoc for the full
  contract. 25 turns is that same spec's own turn math for Animal
  Husbandry's 50-science cost at a size->=1 city's >=2/turn income.

  `[data-test='build-pasture']` is the natural extension of
  `GameLive.UnitPanel`'s existing generic `build_button/1` component
  (`data-test={"build-" <> to_string(kind)}`, already used by `build-farm`/
  `build-mine`/`build-road`) once `:pasture` is a `kind` `Improvement`
  recognizes — no new naming invented here, just the next `kind` down
  the same list.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "Pasture needs Animal Husbandry first" do
    scenario "the build-Pasture option only appears once Animal Husbandry completes" do
      given_(:a_world)
      given_(:registered_player)

      given_ "a worker stands on a Cattle tile within a founded city's territory", context do
        land? = fn t -> Fixtures.tile_class(context.world, t) == :land end

        cattle_tile =
          Enum.find(0..(Fixtures.tile_count(context.world) - 1), fn t ->
            Fixtures.resource_at(context.world, t) == :cattle
          end)

        founding_tile = Fixtures.adjacent_tiles(context.world, cattle_tile) |> Enum.find(land?)

        {:ok, join_live, _html} = live(context.conn, "/play")

        join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, play_live, _html} = live(context.conn, "/play/#{context.world.id}")

        [settler | _] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :settler, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => settler.id, "to_tile" => founding_tile})

        Enum.reduce_while(1..30, :ok, fn _, :ok ->
          [s] = for u <- Fixtures.player_units(context.world, context.user), u.id == settler.id, do: u

          if s.tile_id == founding_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        render_hook(play_live, "found_city", %{"unit_id" => settler.id})
        [city] = Fixtures.player_cities(context.world, context.user)

        render_hook(play_live, "queue_production", %{"city_id" => city.id, "item" => "worker"})
        for _ <- 1..12, do: Fixtures.advance_turn(context.world)

        [worker] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :worker, do: u

        render_hook(play_live, "queue_move", %{"unit_id" => worker.id, "to_tile" => cattle_tile})

        Enum.reduce_while(1..10, :ok, fn _, :ok ->
          [w] = for u <- Fixtures.player_units(context.world, context.user), u.id == worker.id, do: u

          if w.tile_id == cattle_tile do
            {:halt, :ok}
          else
            Fixtures.advance_turn(context.world)
            {:cont, :ok}
          end
        end)

        {:ok,
         context
         |> Map.put(:play_live, play_live)
         |> Map.put(:worker, worker)
         |> Map.put(:cattle_tile, cattle_tile)}
      end

      when_ "the player selects the worker before researching Animal Husbandry", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "Build Pasture is not offered", context do
        refute has_element?(context.play_live, "[data-test='build-pasture']")
        {:ok, context}
      end

      given_ "the player opens the tech panel and researches Animal Husbandry to completion", context do
        render_hook(context.play_live, "toggle_tech_panel", %{})
        render_hook(context.play_live, "select_research", %{"tech" => "animal_husbandry"})
        for _ <- 1..25, do: Fixtures.advance_turn(context.world)
        assert has_element?(context.play_live, "[data-test='tech-completed-animal_husbandry']")
        {:ok, context}
      end

      when_ "the player selects the same worker again", context do
        render_hook(context.play_live, "select_unit", %{"unit_id" => context.worker.id})
        {:ok, context}
      end

      then_ "Build Pasture is now offered", context do
        assert has_element?(context.play_live, "[data-test='build-pasture']")
        {:ok, context}
      end
    end
  end
end
