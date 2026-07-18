defmodule BrokenOaths.Game.VassalizationTest do
  use ExUnit.Case, async: true

  alias BrokenOaths.Game.Vassalage
  alias BrokenOaths.Game.Vassalization

  defp city(id, opts) do
    %{
      id: id,
      player_id: Keyword.fetch!(opts, :player_id),
      occupied_by_player_id: Keyword.get(opts, :occupied_by_player_id)
    }
  end

  defp event(city_id, captor_player_id, defeated_player_id) do
    %{city_id: city_id, captor_player_id: captor_player_id, defeated_player_id: defeated_player_id}
  end

  describe "vassalization_events/2" do
    test "keeps a capture that leaves the defeated player with zero free cities" do
      cities = [city(1, player_id: 2, occupied_by_player_id: 1)]
      events = [event(1, 1, 2)]

      assert Vassalization.vassalization_events(events, cities) == events
    end

    test "drops a capture that still leaves the defeated player a free city" do
      cities = [
        city(1, player_id: 2, occupied_by_player_id: 1),
        city(2, player_id: 2)
      ]

      events = [event(1, 1, 2)]

      assert Vassalization.vassalization_events(events, cities) == []
    end

    test "several different players' own last cities each fire independently in the same pass" do
      cities = [
        city(1, player_id: 2, occupied_by_player_id: 1),
        city(2, player_id: 3, occupied_by_player_id: 1)
      ]

      events = [event(1, 1, 2), event(2, 1, 3)]

      assert Vassalization.vassalization_events(events, cities) |> Enum.map(& &1.defeated_player_id) |> Enum.sort() ==
               [2, 3]
    end

    test "the same defeated player is never reported twice, even if two of their cities fell at once" do
      cities = [
        city(1, player_id: 2, occupied_by_player_id: 1),
        city(2, player_id: 2, occupied_by_player_id: 1)
      ]

      events = [event(1, 1, 2), event(2, 1, 2)]

      assert [%{defeated_player_id: 2}] = Vassalization.vassalization_events(events, cities)
    end

    test "an empty event list stays empty" do
      assert Vassalization.vassalization_events([], []) == []
    end
  end

  describe "vassalize_changeset/3" do
    test "builds a valid changeset carrying every default forward-looking field" do
      changeset = Vassalization.vassalize_changeset(1, 10, 20)
      assert changeset.valid?

      vassalage = Ecto.Changeset.apply_changes(changeset)
      assert vassalage.world_id == 1
      assert vassalage.lord_player_id == 10
      assert vassalage.vassal_player_id == 20
      assert vassalage.tribute_rate == 0.25
      assert vassalage.oath_strain == 0
      assert vassalage.hidden_agenda == nil
      assert vassalage.contract_terms == %{}
      assert vassalage.status == :active
    end

    test "refuses a lord vassalizing themselves" do
      changeset = Vassalization.vassalize_changeset(1, 10, 10)
      refute changeset.valid?
    end
  end

  describe "agenda_pending?/1" do
    test "true for a freshly created vassalage (no agenda chosen yet)" do
      changeset = Vassalization.vassalize_changeset(1, 10, 20)
      vassalage = Ecto.Changeset.apply_changes(changeset)
      assert Vassalization.agenda_pending?(vassalage)
    end

    test "false once an agenda has been chosen" do
      vassalage = %Vassalage{hidden_agenda: :usurp}
      refute Vassalization.agenda_pending?(vassalage)
    end
  end

  describe "choose_agenda_changeset/2" do
    test "sets the chosen agenda" do
      changeset = Vassalization.vassalize_changeset(1, 10, 20)
      vassalage = Ecto.Changeset.apply_changes(changeset)

      agenda_changeset = Vassalization.choose_agenda_changeset(vassalage, :kingmaker)
      assert agenda_changeset.valid?
      assert Ecto.Changeset.apply_changes(agenda_changeset).hidden_agenda == :kingmaker
    end

    test "accepts every Hidden Agenda v1 option" do
      changeset = Vassalization.vassalize_changeset(1, 10, 20)
      vassalage = Ecto.Changeset.apply_changes(changeset)

      for agenda <- [:restore, :usurp, :kingmaker, :merchant_prince] do
        assert Vassalization.choose_agenda_changeset(vassalage, agenda).valid?
      end
    end
  end

  describe "notification copy" do
    test "vassalized_message/1 names the new lord" do
      assert Vassalization.vassalized_message("lord@example.com") =~ "lord@example.com"
    end

    test "new_vassal_message/1 names the new vassal" do
      assert Vassalization.new_vassal_message("vassal@example.com") =~ "vassal@example.com"
    end
  end
end
