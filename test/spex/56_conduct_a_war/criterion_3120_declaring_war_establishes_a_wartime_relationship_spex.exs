defmodule BrokenOathsSpex.Story996.Criterion3120Spex do
  @moduledoc """
  Story 996 — Conduct a War
  Criterion 3120 — Declaring war establishes a wartime relationship.
  """

  use BrokenOathsSpex.Case

  import BrokenOathsSpex.SharedGivens

  spex "a player declares war through diplomacy" do
    scenario "a discovered rival becomes a wartime opponent" do
      given_ :a_world
      given_ :registered_player
      given_ :second_registered_player
      given_ :two_players_discovered_each_other

      when_ "the player declares war on the discovered rival", context do
        render_hook(context.play_live, "declare_war", %{
          "neighbor_user_id" => to_string(context.other_user.id)
        })

        {:ok, context}
      end

      then_ "the diplomacy panel shows the rival as hostile", context do
        assert has_element?(
                 context.play_live,
                 "[data-test='war-hostile-#{context.other_user.id}']"
               )

        {:ok, context}
      end
    end
  end
end
