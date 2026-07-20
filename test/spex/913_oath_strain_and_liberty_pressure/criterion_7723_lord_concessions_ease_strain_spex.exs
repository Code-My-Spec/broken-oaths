defmodule BrokenOathsSpex.Story913.Criterion7723Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7723 — "Oath Strain falls from investment: lord gifts, a
  granted autonomy or lowered tribute rate, and a shared enemy against
  a common foe" (`.code_my_spec/knowledge/feudal_vassalage_design.md`).
  No `BrokenOaths.Feudal.OathStrain` decay engine exists yet, so both
  assertions below are expected to fail today: nothing currently lowers
  `Vassalage.oath_strain` at all.

  ## Judgment call: reaching a real "high strain" starting figure

  Same substitution rationale as the sibling criteria in this story:
  the gherkin's "Oath Strain of 70" precondition has no exact real
  production path. Five real, already-shipped refused-call-to-arms
  spikes (`BrokenOaths.Feudal.Tribute.spike_oath_strain/1`, +15 each,
  5×15=75) land closer to the illustrative "70" than any other multiple
  of the real spike size — the SUBJECT under test ("a high strain eases
  after concessions") survives the literal-number substitution intact.

  Also real and already shipped: raising the rate to 50% first (so the
  scenario's own "lowers his tribute rate from 50% to 20%" has a real
  50% to lower FROM — `criterion_7673`'s own already-wired
  `"set_tribute_rate"` flow).

  ## Invented surfaces: "gifts him a warrior" and "share a common enemy"

  Neither a lord-to-vassal gift mechanic nor any war/common-enemy
  declaration exists anywhere in this codebase (`grep -rn gift lib/`
  and `grep -rn declare_war lib/` both come back empty). This spec
  invents the narrowest plausible seams: `"gift_vassal"` (fired on the
  LORD's own connection, alongside the rate cut — both are lord-side
  concessions happening in the same beat the gherkin's own single
  `When` clause describes) and `"declare_shared_enemy"` (fired on the
  LORD's connection, naming the already-joined third player as the
  common foe, for the scenario's own "if Mira and Wes share a common
  enemy" follow-on). Both driven through `attempt_event/3` since no
  `handle_event/3` clause exists for either yet.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  alias BrokenOathsSpex.Fixtures

  defp read_strain(conn, world) do
    {:ok, live, _html} = live(conn, "/play/#{world.id}")
    html = render(live)
    [_, strain_text] = Regex.run(~r/data-test="vassal-oath-strain"[^>]*>(\d+)/, html)
    String.to_integer(strain_text)
  end

  spex "lord concessions ease a vassal's Oath Strain downward",
    fail_on_error_logs: false do
    scenario "a lowered tribute rate plus a gift ease strain, and a shared enemy eases it further" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "my rival is already my vassal, at the default 25% rate", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a third player exists as a legal levy target and future common enemy", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "I already raised their tribute rate to 50%", context do
        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "50"
        })

        {:ok, context}
      end

      given_ "Wes has a high Oath Strain of 75, from five earlier refused calls to arms",
             context do
        for _ <- 1..5 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        75 = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_before, 75)}
      end

      when_ "Lord Mira lowers his tribute rate from 50% to 20% and gifts him a warrior", context do
        attempt_event(context.play_live, "set_tribute_rate", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "rate" => "20"
        })

        attempt_event(context.play_live, "gift_vassal", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "gift" => "warrior"
        })

        strain_after_concessions = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_after_concessions, strain_after_concessions)}
      end

      then_ "his Oath Strain eases downward from the concessions", context do
        assert context.strain_after_concessions < context.strain_before,
               "a lowered rate plus a gift should ease Oath Strain below its starting " <>
                 "#{context.strain_before}, got #{context.strain_after_concessions}"

        {:ok, context}
      end

      then_ "sharing a common enemy eases strain further still", context do
        attempt_event(context.play_live, "declare_shared_enemy", %{
          "vassal_user_id" => to_string(context.other_user.id),
          "enemy_user_id" => to_string(context.third_user.id)
        })

        strain_after_shared_enemy = read_strain(context.conn, context.world)

        assert strain_after_shared_enemy < context.strain_after_concessions,
               "a shared common enemy should ease Oath Strain further below " <>
                 "#{context.strain_after_concessions}, got #{strain_after_shared_enemy}"

        {:ok, context}
      end
    end
  end
end
