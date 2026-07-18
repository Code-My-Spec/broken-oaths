defmodule BrokenOaths.Game.Vassalization do
  @moduledoc """
  The subjugation pivot (story 907): the business rules built on top of
  `BrokenOaths.Game.Vassalage`, mirroring `BrokenOaths.Game.
  Cooperation`'s own "pure changeset, no `Repo`" role for `Alliance`.
  `BrokenOaths.Game.WorldServer` is the imperative shell that calls into
  this module once `BrokenOaths.Game.Siege.materialize_captures/2`
  reports a fresh capture, actually persists the row, and pushes the
  notifications both players see.

  ## When vassalization fires

  Zeroing a city's HP and walking in (`Siege`'s own job) is necessary
  but not sufficient — vassalization only fires once the DEFEATED
  player has zero free cities left ("'Free city' = a city you own that
  no other player occupies... Vassalization fires at ZERO free cities",
  design doc, "Round-5 decisions"). `vassalization_events/2` is that
  filter, applied to whatever `Siege.materialize_captures/2` reports:
  a capture that still leaves the defeated player one free city is
  silently dropped (`BrokenOathsSpex.Story907.Criterion7667Spex`); a
  capture that leaves them none is kept.

  Several different players' own last cities can fall in the very same
  tick (each independently besieged down and walked into) — each is
  resolved on its own, deterministically, in `Siege`'s own capture
  order (ascending city id): `vassalization_events/2` also collapses
  the rare case of the SAME player's own last TWO cities somehow
  falling in one pass to a single event, so a defeated player is never
  vassalized twice for the same subjugation.

  ## Creating the relationship

  `vassalize_changeset/3` builds a fresh `Vassalage` row with every
  default forward-looking field the design doc calls for (25% tribute,
  0 Oath Strain, an empty contract-terms bag, `:active` status) — the
  caller is responsible for the actual `Repo.insert/1`.

  ## The Oath screen

  The fresh vassal's own Hidden Agenda pick — Restore, Usurp, Kingmaker,
  or Merchant Prince — is a SEPARATE, later commit
  (`choose_agenda_changeset/2`), not part of the vassalizing insert
  itself: the relationship exists (and both players are notified) the
  MOMENT the last free city falls, but the agenda stays secret and
  unset until the vassal actually picks one on their own view.
  """

  alias BrokenOaths.Game.Siege
  alias BrokenOaths.Game.Vassalage

  @type player_id :: term()

  # -------------------------------------------------------------------
  # When vassalization fires
  # -------------------------------------------------------------------

  @doc """
  Filters `capture_events` (`Siege.materialize_captures/2`'s own
  return) down to the ones that actually leave their defeated player
  with zero free cities among `cities` — `Siege.no_free_cities?/2`
  applied per event, deduplicated so the same defeated player is never
  reported twice even if several of their cities fell in the same pass.
  """
  @spec vassalization_events([Siege.capture_event()], [Siege.city()]) :: [Siege.capture_event()]
  def vassalization_events(capture_events, cities) do
    capture_events
    |> Enum.filter(&Siege.no_free_cities?(cities, &1.defeated_player_id))
    |> Enum.uniq_by(& &1.defeated_player_id)
  end

  # -------------------------------------------------------------------
  # Creating the relationship
  # -------------------------------------------------------------------

  @doc """
  Build the changeset for a fresh `Vassalage` row: `lord_player_id`
  captured `vassal_player_id`'s last free city in `world_id`. Every
  forward-looking field defaults per `Vassalage.changeset/2` (25%
  tribute, 0 Oath Strain, no agenda yet, an empty contract-terms bag,
  `:active` status) — the caller persists it.
  """
  @spec vassalize_changeset(term(), player_id(), player_id()) :: Ecto.Changeset.t()
  def vassalize_changeset(world_id, lord_player_id, vassal_player_id) do
    Vassalage.changeset(%Vassalage{}, %{
      world_id: world_id,
      lord_player_id: lord_player_id,
      vassal_player_id: vassal_player_id
    })
  end

  # -------------------------------------------------------------------
  # The Oath screen
  # -------------------------------------------------------------------

  @doc "Whether `vassalage` still awaits its vassal's own secret Hidden Agenda pick — the Oath screen's own trigger."
  @spec agenda_pending?(Vassalage.t()) :: boolean()
  def agenda_pending?(%Vassalage{hidden_agenda: nil}), do: true
  def agenda_pending?(%Vassalage{}), do: false

  @doc "Build the changeset recording the vassal's own secret Hidden Agenda pick."
  @spec choose_agenda_changeset(Vassalage.t(), Vassalage.hidden_agenda()) :: Ecto.Changeset.t()
  def choose_agenda_changeset(vassalage, agenda), do: Vassalage.changeset(vassalage, %{hidden_agenda: agenda})

  # -------------------------------------------------------------------
  # Notifications
  # -------------------------------------------------------------------

  @doc "The fresh vassal's own notification copy — the `\"game:vassalized\"` push both 906 and 907 share."
  @spec vassalized_message(String.t()) :: String.t()
  def vassalized_message(lord_email),
    do: "Your last free city has fallen — you are now sworn to #{lord_email}."

  @doc "The lord's own notification copy for their new vassal — the `\"game:new_vassal\"` push."
  @spec new_vassal_message(String.t()) :: String.t()
  def new_vassal_message(vassal_email), do: "#{vassal_email} has sworn fealty to you."
end
