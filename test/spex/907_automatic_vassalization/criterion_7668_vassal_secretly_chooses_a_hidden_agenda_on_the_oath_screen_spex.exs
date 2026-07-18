defmodule BrokenOathsSpex.Story907.Criterion7668Spex do
  @moduledoc """
  Story 907 — Automatic Vassalization
  Criterion 7668 — the moment of subjugation raises an "Oath screen
  ('Terms of Oath')" where the fresh vassal SECRETLY picks a Hidden
  Agenda: "a personal ongoing ambition (e.g. Restore my realm / Usurp
  my lord / Kingmaker / Merchant Prince). Reframes defeat as a new
  game" (`.code_my_spec/knowledge/feudal_vassalage_design.md`, §B, and
  "Hidden Agenda v1 = all four: Restore, Usurp, Kingmaker, Merchant
  Prince" — "Round-4 final foundation mechanics"). "Secretly" is the
  criterion's own word: the choice must be invisible to the lord.

  See `BrokenOathsSpex.Story907.Criterion7666Spex`'s own moduledoc for
  the shared `vassals-list`/`vassal-status` judgment calls.

  ## This criterion's own new judgment calls

  1. **The Oath screen**: `data-test="oath-screen"` on the fresh
     vassal's own `GameLive.Play`, appearing once their last free city
     falls, offering exactly the four agenda options as `data-test=
     "agenda-option-restore"`/`"-usurp"`/`"-kingmaker"`/
     `"-merchant_prince"` (matching the enum-style naming this
     codebase already uses for other choice sets, e.g. story 902's
     tech ids). No `handle_event/3` clause exists yet for choosing one
     — driven through `attempt_event/3`.
  2. **Secrecy**: the LORD's own Vassals list/panel never renders the
     agenda text anywhere, even after the vassal has chosen — the
     agenda is "secret" per the criterion's own wording, a real
     assertion this spec can drive today by checking the lord's own
     rendered HTML never contains any of the four agenda labels.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  spex "the vassal secretly chooses a Hidden Agenda on the Oath screen", fail_on_error_logs: false do
    scenario "a fresh vassal sees the Oath screen, picks an agenda, and it stays secret from the lord" do
      given_(:a_world)
      given_(:registered_player)
      given_(:second_registered_player)

      given_ "my rival's last free city stands broken, and my Lord is adjacent", context do
        context = join_and_found_rival_city(context)
        :ok = clear_all_camps(context.world)

        [my_lord] =
          for u <- Fixtures.player_units(context.world, context.user), u.type == :lord, do: u

        target = adjacent_land_tile(context.world, context.other_city.tile_id, [my_lord.tile_id])
        my_lord = march_to(context.play_live, context.world, context.user, my_lord, target)

        grind_city(
          context.play_live,
          context.world,
          my_lord,
          context.other_user,
          context.other_city
        )

        {:ok, Map.put(context, :my_lord, my_lord)}
      end

      when_ "I capture their last free city, subjugating them", context do
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

      then_ "the fresh vassal sees the Oath screen with all four Hidden Agenda options", context do
        assert context.my_lord.tile_id == context.other_city.tile_id
        assert has_element?(context.other_play_live, "[data-test='oath-screen']")

        for option <- ~w(restore usurp kingmaker merchant_prince) do
          assert has_element?(
                   context.other_play_live,
                   "[data-test='agenda-option-#{option}']"
                 )
        end

        {:ok, context}
      end

      then_ "choosing an agenda closes the Oath screen, and it never reaches the lord's own view",
            context do
        attempt_event(context.other_play_live, "choose_hidden_agenda", %{"agenda" => "usurp"})

        refute has_element?(context.other_play_live, "[data-test='oath-screen']")

        lord_html = render(context.play_live)
        refute lord_html =~ "usurp"
        refute lord_html =~ "Usurp"
        {:ok, context}
      end
    end
  end
end
