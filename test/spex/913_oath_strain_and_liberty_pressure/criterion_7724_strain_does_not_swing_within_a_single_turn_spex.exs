defmodule BrokenOathsSpex.Story913.Criterion7724Spex do
  @moduledoc """
  Story 913 — Oath Strain and Liberty Pressure
  Criterion 7724 — "Oath Strain is slow and sticky: it moves on the
  scale of hours rather than per-turn, so the social and chat layer has
  time to operate before it shifts"
  (`.code_my_spec/knowledge/feudal_vassalage_design.md`). Since no
  `BrokenOaths.Feudal.OathStrain` per-tick engine exists at all today,
  this scenario's own "no new events, no big swing" invariant is
  trivially satisfied right now (nothing moves the figure per-tick at
  all) — that's expected and fine; the assertions are written as real,
  restrictive bounds so they stay meaningful once accrual/decay ships
  (they would catch, for instance, a buggy "decay straight to the
  driver's implied ceiling in one tick" implementation).

  ## Judgment call: reaching a real "high strain, after a spike" starting figure

  Same substitution as the sibling criteria in this story: the
  gherkin's "Oath Strain of 70 after a spike" precondition is reached
  via five real, already-shipped refused-call-to-arms spikes
  (`BrokenOaths.Feudal.Tribute.spike_oath_strain/1`, +15 each, 5×15=75) —
  both "high" and, per that same module's own moduledoc, genuinely "a
  spike."

  ## Encoding "at most a small sticky increment"

  The scenario's own number is unstated beyond "small," so this spec
  picks a concrete, generous-but-real bound (≤5 points, 1/20th of the
  full 0-100 range) for what "small" means within a SINGLE 60-second
  turn (`world.turn_seconds` defaults to 60 —
  `Fixtures.advance_turn/1` is exactly one such boundary), and a
  slightly looser bound (≤10 points) for "holds near 70... across many
  turns" — a longer idle stretch a real slow decay-toward-neutral curve
  might legitimately nudge a little further than one single tick would.
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

  spex "Oath Strain does not swing within a single turn",
    fail_on_error_logs: false do
    scenario "a single 60-second turn with no new events moves strain by at most a small sticky increment" do
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

      given_ "Wes has an Oath Strain of 75, after five refusal spikes", context do
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

      when_ "a single 60-second turn processes with no new events", context do
        Fixtures.advance_turn(context.world)
        strain_after_one_turn = read_strain(context.conn, context.world)

        {:ok, Map.put(context, :strain_after_one_turn, strain_after_one_turn)}
      end

      then_ "strain moves by at most a small sticky increment, not a full reset", context do
        delta = abs(context.strain_after_one_turn - context.strain_before)

        assert delta <= 5,
               "a single quiet turn should move Oath Strain by at most a small sticky increment " <>
                 "(<=5), moved by #{delta} (#{context.strain_before} -> #{context.strain_after_one_turn})"

        refute context.strain_after_one_turn == 0,
               "a single quiet turn should never reset Oath Strain to 0"

        {:ok, context}
      end

      then_ "it holds near its starting value across many further quiet turns", context do
        for _ <- 1..20, do: Fixtures.advance_turn(context.world)

        strain_after_many_turns = read_strain(context.conn, context.world)
        delta = abs(strain_after_many_turns - context.strain_before)

        assert delta <= 10,
               "twenty further quiet turns (still no rate change, no new grievance or concession) " <>
                 "should hold Oath Strain near its starting #{context.strain_before}, got " <>
                 "#{strain_after_many_turns}"

        {:ok, context}
      end
    end
  end
end
