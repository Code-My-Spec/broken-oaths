defmodule BrokenOaths.Chat.Moderation do
  @moduledoc """
  Pure profanity filter (story 900) applied to a message's body before
  it's persisted/broadcast: any banned word is masked with asterisks of
  the same length, so the recipient never sees the raw profanity but
  the rest of the sentence is untouched. No `Repo`, no process state —
  a plain string transformation, matched the same way
  `BrokenOaths.Game.Discovery` keeps first-contact detection pure.

  The word list is intentionally small and self-contained (no external
  dependency, no config) — good enough to prove the delivery-time
  filtering contract, not a production-grade moderation service.
  """

  @banned_words ~w(fuck fucking fucked shit bitch asshole bastard cunt)

  @pattern Regex.compile!(
             "\\b(?:" <> Enum.map_join(@banned_words, "|", &Regex.escape/1) <> ")\\b",
             "i"
           )

  @doc """
  Masks every banned word in `body` with asterisks matching its
  original length, leaving everything else — spacing, punctuation,
  other words — untouched.
  """
  @spec filter(String.t()) :: String.t()
  def filter(body) when is_binary(body) do
    Regex.replace(@pattern, body, &String.duplicate("*", String.length(&1)))
  end
end
