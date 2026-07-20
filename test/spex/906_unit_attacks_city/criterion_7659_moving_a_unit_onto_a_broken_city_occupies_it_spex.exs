defmodule BrokenOathsSpex.Story906.Criterion7659Spex do
  @moduledoc """
  Story 906 — Unit Attacks City
  Criterion 7659 — once a rival city is broken, the besieger must still
  MOVE A UNIT ONTO THE CITY'S OWN TILE to occupy it — "Civ-style. No
  range-flip — you commit and hold a body"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`, "Round-4 final
  foundation mechanics"). This criterion is the capture moment itself:
  an ungarrisoned broken city, entered by the besieger's own unit,
  becomes occupied.

  See `criterion_7657`'s own moduledoc for the shared judgment calls
  this criterion builds on (the `city-status` badge, why today's code
  auto-pillages instead of truly reaching a persisted 0 HP, and
  `grind_city/6`'s regen-aware safety cap).

  ## This criterion's own judgment call: nothing blocks the walk-in today

  `Turn.attempt_step/2`'s `blocked?/5` only refuses a step into a tile
  occupied by other UNITS (`positions`) — it never looks at
  `state.cities` at all. An ungarrisoned rival city's own tile therefore
  has ZERO occupants today, so `march_to/6` (an ordinary `"queue_move"`
  order) already lands the besieger's unit ON that tile without any
  collision refusal, even though nothing today changes who OWNS the
  city as a result — that ownership change (`BrokenOaths.Combat.Siege`'s
  own job) is this criterion's real subject and RED signal.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "moving a unit onto a broken city occupies it" do
    scenario "walking my Lord onto a broken, ungarrisoned rival city occupies it" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "an ungarrisoned rival city has been besieged down to broken", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        broken_city =
          grind_city(
            context.play_live,
            context.world,
            my_lord,
            context.other_user,
            context.other_city
          )

        context
        |> Map.put(:my_lord, my_lord)
        |> Map.put(:broken_city, broken_city)
        |> then(&{:ok, &1})
      end

      when_ "I move my Lord onto the broken city's own tile", context do
        my_lord =
          march_to(
            context.play_live,
            context.world,
            context.user,
            context.my_lord,
            context.other_city.tile_id
          )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      then_ "my Lord stands on the city's tile and the rival's own city panel now reads occupied",
            context do
        assert context.my_lord.tile_id == context.other_city.tile_id

        render_hook(context.other_play_live, "select_city", %{
          "city_id" => to_string(context.other_city.id)
        })

        assert has_element?(context.other_play_live, "[data-test='city-status']", "occupied")
        {:ok, context}
      end

      then_ "the original owner still keeps the city on their own roster", context do
        [still_theirs] =
          for c <- Fixtures.player_cities(context.world, context.other_user),
              c.id == context.other_city.id,
              do: c

        assert still_theirs.id == context.other_city.id
        {:ok, context}
      end
    end
  end
end
