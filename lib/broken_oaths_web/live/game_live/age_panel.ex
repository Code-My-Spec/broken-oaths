defmodule BrokenOathsWeb.GameLive.AgePanel do
  @moduledoc """
  The player's current age, story 903: an always-visible badge (the
  same "persistent status, not a selection-triggered side panel"
  status `GameLive.Play`'s own `player-gold` badge already has) reading
  "Stone Age" or "Bronze Age" — derived, never a separate flag, exactly
  the way `BrokenOaths.Technology.Research.age/1` itself is derived purely
  from `completed_techs`.

  A presentational component mounted unconditionally by
  `BrokenOathsWeb.GameLive.Play`, which owns the notification side of
  this story: `AgePanel` renders state, it never calls
  `BrokenOaths.Game` and defines no `handle_event/3` of its own (a
  `live_component` can't receive `handle_info/2` either, so the
  one-shot "You have entered the Bronze Age!" toast this story also
  calls for is `Play`'s own job — see its moduledoc's `game:age` entry
  — the same "component renders, `Play` notifies" split `GameLive.
  TechPanel` already establishes for its own research state).

  Assigns (from `Play`):

    * `:id` - the DOM id for this component instance
    * `:player_research` - `BrokenOaths.Game.player_research/2`'s own
      shape (the same one `GameLive.TechPanel` already receives) — only
      `:completed_techs` is actually read here, via `Research.age/1`,
      so this component never drifts out of sync with what unlocked
      the age in the first place.
  """

  use BrokenOathsWeb, :live_component

  alias BrokenOaths.Technology.Research

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :age, Research.age(assigns.player_research))

    ~H"""
    <span id={@id} class="badge badge-outline gap-1" data-test="age-panel">
      <.icon name="hero-flag" class="w-3 h-3" />
      <span data-test="age-status">{age_label(@age)}</span>
    </span>
    """
  end

  defp age_label(:stone_age), do: "Stone Age"
  defp age_label(:bronze_age), do: "Bronze Age"
end
