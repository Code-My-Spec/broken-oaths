defmodule BrokenOathsSpex.Story913.Criterion7725Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7725 — "Oath Strain never auto-fires a rebellion and never
  gates the ability to declare independence — declaring is always
  available. Its one mechanical job is to SIZE the temporary rebellion
  army when the vassal revolts: higher strain means a bigger uprising"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`).

  Story 915 (the actual rebellion/declare-independence mechanic) hasn't
  been built or speced yet either — no "declare independence" affordance
  exists anywhere in `GameLive.Play` today (`grep -rn
  declare_independence lib/` comes back empty), which is exactly why
  this criterion is safe to encode faithfully without inventing 915's
  own surface: the scenario's own `When` is "many turns process and Wes
  NEVER clicks Declare Independence" — the absence of any such click.
  There is nothing to drive; only many quiet real turn boundaries
  (`Fixtures.advance_turn/1`) to prove nothing fires on its own.

  This spec deliberately does NOT assert anything about rebellion ARMY
  SIZE or WHICH CITIES rise — both belong to story 915 (sizing) and the
  lord's separate Honor/tribute-rate lever (targeting), neither of
  which this story or its component (`BrokenOaths.Feudal.OathStrain`)
  owns. It only proves the negative: no auto-rebellion, vassal status
  unchanged, on both sides of the bond.

  ## Judgment call: reaching a real "max strain" starting figure

  Same substitution as the sibling criteria in this story: the
  gherkin's "Oath Strain of 95" precondition is reached via seven real,
  already-shipped refused-call-to-arms spikes (`BrokenOaths.Game.
  Tribute.spike_oath_strain/1`, +15 each, 7×15=105 raw, clamped at
  100) — landing on the LITERAL maximum rather than merely near it,
  which if anything makes "the powder is dry" framing MORE apt than the
  gherkin's own illustrative 95, not less.
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

  spex "max Oath Strain never auto-fires a rebellion", fail_on_error_logs: false do
    scenario "many quiet turns at maximum strain never sever the vassalage on their own" do
      given_ "a world with room for three players", context do
        {:ok, Map.put(context, :world, Fixtures.world_fixture(%{seed: 1, frequency: 9}))}
      end

      given_(:registered_player)
      given_(:second_registered_player)
      given_(:third_registered_player)

      given_ "my rival is already my vassal", context do
        {:ok, a_freshly_subjugated_vassal(context)}
      end

      given_ "a third player exists as a legal levy target", context do
        {:ok, third_join_live, _html} = live(context.third_conn, "/play")

        third_join_live
        |> element("[data-test='join-world-#{context.world.id}']")
        |> render_click()

        {:ok, context}
      end

      given_ "Wes has an Oath Strain of 100 — \"the powder is dry\"", context do
        for _ <- 1..7 do
          attempt_event(context.play_live, "issue_levy", %{
            "vassal_user_id" => to_string(context.other_user.id),
            "target_user_id" => to_string(context.third_user.id),
            "share" => "0.5"
          })

          attempt_event(context.other_play_live, "refuse_levy", %{
            "lord_user_id" => to_string(context.user.id)
          })
        end

        100 = read_strain(context.conn, context.world)

        {:ok, context}
      end

      when_ "many turns process and Wes never clicks Declare Independence", context do
        for _ <- 1..50, do: Fixtures.advance_turn(context.world)
        {:ok, context}
      end

      then_ "no rebellion fires automatically and Wes remains a vassal on his own view", context do
        {:ok, vassal_live, _html} = live(context.other_conn, "/play/#{context.world.id}")

        assert has_element?(
                 vassal_live,
                 "[data-test='vassal-status']",
                 "Sworn to #{context.user.email}"
               )

        {:ok, context}
      end

      then_ "the lord still lists Wes as an active vassal on the lord's own Vassals panel", context do
        {:ok, lord_live, _html} = live(context.conn, "/play/#{context.world.id}")

        assert has_element?(lord_live, "[data-test='vassal-row-#{context.other_user.id}']")

        strain_still_at_max = read_strain(context.conn, context.world)

        assert strain_still_at_max == 100,
               "max Oath Strain should hold at the ceiling across quiet turns, not sever the bond " <>
                 "or reset it — read #{strain_still_at_max}"

        {:ok, context}
      end
    end
  end
end
