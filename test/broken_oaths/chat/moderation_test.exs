defmodule BrokenOaths.Chat.ModerationTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Chat.Moderation

  test "clean text passes through unchanged" do
    assert Moderation.filter("Shall we clear that camp together?") ==
             "Shall we clear that camp together?"
  end

  test "a banned word is masked with asterisks matching its length, other words untouched" do
    assert Moderation.filter("you are a fucking coward") == "you are a ******* coward"
  end

  test "masking is case-insensitive" do
    assert Moderation.filter("FUCKING coward") == "******* coward"
  end

  test "multiple banned words in the same message are all masked" do
    assert Moderation.filter("shit bitch fuck") == "**** ***** ****"
  end

  test "a banned word does not mask a longer legitimate word containing it" do
    assert Moderation.filter("the assassin approached") == "the assassin approached"
  end

  test "punctuation immediately after a banned word is preserved" do
    assert Moderation.filter("what the shit!") == "what the ****!"
  end
end
