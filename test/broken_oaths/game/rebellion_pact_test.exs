defmodule BrokenOaths.Game.RebellionPactTest do
  use BrokenOathsTest.DataCase, async: true

  alias BrokenOaths.Game.Player
  alias BrokenOaths.Game.RebellionPact
  alias BrokenOaths.Game.RebellionPactMember
  alias BrokenOaths.UsersFixtures
  alias BrokenOaths.WorldsFixtures

  defp insert_player!(world, user, region_id) do
    {:ok, player} =
      %Player{}
      |> Player.changeset(%{
        world_id: world.id,
        user_id: user.id,
        region_id: region_id,
        joined_turn: 0
      })
      |> Repo.insert()

    player
  end

  # A lord plus three fellow vassals (Wes, Ada, Bo) — story 916's own
  # "three vassals of one lord" conspiracy shape.
  defp lord_and_vassals_fixture do
    world = WorldsFixtures.world_fixture()
    lord = insert_player!(world, UsersFixtures.user_fixture(), 1)

    [wes, ada, bo] =
      for region_id <- 2..4 do
        insert_player!(world, UsersFixtures.user_fixture(), region_id)
      end

    {world, lord, wes, ada, bo}
  end

  defp valid_attrs(overrides \\ %{}) do
    {world, lord, wes, _ada, _bo} = lord_and_vassals_fixture()

    Map.merge(
      %{
        world_id: world.id,
        lord_player_id: lord.id,
        opener_player_id: wes.id,
        strike_turn: 50
      },
      overrides
    )
  end

  defp insert_pact!(attrs) do
    {:ok, pact} = RebellionPact.changeset(%RebellionPact{}, attrs) |> Repo.insert()
    pact
  end

  defp insert_member!(pact, player, overrides \\ %{}) do
    attrs = Map.merge(%{rebellion_pact_id: pact.id, player_id: player.id}, overrides)
    {:ok, member} = RebellionPactMember.changeset(%RebellionPactMember{}, attrs) |> Repo.insert()
    member
  end

  describe "RebellionPact.changeset/2" do
    test "with valid attrs is valid" do
      changeset = RebellionPact.changeset(%RebellionPact{}, valid_attrs())
      assert changeset.valid?
    end

    test "requires world_id, lord_player_id, opener_player_id, strike_turn, and status" do
      changeset = RebellionPact.changeset(%RebellionPact{}, %{})
      refute changeset.valid?

      assert %{
               world_id: ["can't be blank"],
               lord_player_id: ["can't be blank"],
               opener_player_id: ["can't be blank"],
               strike_turn: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "status defaults to :forming" do
      pact = insert_pact!(valid_attrs())
      assert pact.status == :forming
    end

    test "status accepts every catalogued lifecycle value" do
      for status <- [:forming, :struck, :dissolved] do
        changeset = RebellionPact.changeset(%RebellionPact{}, Map.put(valid_attrs(), :status, status))
        assert changeset.valid?
      end
    end

    test "status refuses an unknown value" do
      changeset = RebellionPact.changeset(%RebellionPact{}, Map.put(valid_attrs(), :status, :active))
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "strike_turn must be greater than zero" do
      changeset = RebellionPact.changeset(%RebellionPact{}, Map.put(valid_attrs(), :strike_turn, 0))
      refute changeset.valid?
      assert %{strike_turn: [_]} = errors_on(changeset)

      changeset = RebellionPact.changeset(%RebellionPact{}, Map.put(valid_attrs(), :strike_turn, -5))
      refute changeset.valid?
      assert %{strike_turn: [_]} = errors_on(changeset)
    end

    test "the opener can never be the lord they're conspiring against" do
      attrs = valid_attrs()
      changeset = RebellionPact.changeset(%RebellionPact{}, %{attrs | opener_player_id: attrs.lord_player_id})
      refute changeset.valid?
      assert %{opener_player_id: ["can't be the same as the lord"]} = errors_on(changeset)
    end

    test "requires the world/lord/opener to actually exist" do
      attrs = valid_attrs(%{lord_player_id: -1})
      assert {:error, changeset} = RebellionPact.changeset(%RebellionPact{}, attrs) |> Repo.insert()
      assert %{lord_player: [_]} = errors_on(changeset)
    end

    test "a lord can be the target of more than one pact opened by different vassals" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()

      assert {:ok, _first} =
               RebellionPact.changeset(%RebellionPact{}, %{
                 world_id: world.id,
                 lord_player_id: lord.id,
                 opener_player_id: wes.id,
                 strike_turn: 50
               })
               |> Repo.insert()

      assert {:ok, _second} =
               RebellionPact.changeset(%RebellionPact{}, %{
                 world_id: world.id,
                 lord_player_id: lord.id,
                 opener_player_id: ada.id,
                 strike_turn: 60
               })
               |> Repo.insert()
    end
  end

  describe "RebellionPactMember.changeset/2" do
    test "with valid attrs is valid" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      changeset =
        RebellionPactMember.changeset(%RebellionPactMember{}, %{
          rebellion_pact_id: pact.id,
          player_id: ada.id
        })

      assert changeset.valid?
    end

    test "requires rebellion_pact_id, player_id, and commit_status" do
      changeset = RebellionPactMember.changeset(%RebellionPactMember{}, %{})
      refute changeset.valid?

      assert %{
               rebellion_pact_id: ["can't be blank"],
               player_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "commit_status defaults to :invited" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})
      member = insert_member!(pact, ada)

      assert member.commit_status == :invited
    end

    test "informer defaults to false" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})
      member = insert_member!(pact, ada)

      assert member.informer == false
    end

    test "commit_status accepts every catalogued value" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      for status <- [:invited, :committed, :declined] do
        changeset =
          RebellionPactMember.changeset(%RebellionPactMember{}, %{
            rebellion_pact_id: pact.id,
            player_id: ada.id,
            commit_status: status
          })

        assert changeset.valid?
      end
    end

    test "commit_status refuses an unknown value" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      changeset =
        RebellionPactMember.changeset(%RebellionPactMember{}, %{
          rebellion_pact_id: pact.id,
          player_id: ada.id,
          commit_status: :outstanding
        })

      refute changeset.valid?
      assert %{commit_status: [_]} = errors_on(changeset)
    end

    test "a player can only be invited into the same pact once" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      _first = insert_member!(pact, ada)

      assert {:error, changeset} =
               RebellionPactMember.changeset(%RebellionPactMember{}, %{
                 rebellion_pact_id: pact.id,
                 player_id: ada.id
               })
               |> Repo.insert()

      assert %{rebellion_pact_id: [_]} = errors_on(changeset)
    end

    test "requires the pact to actually exist" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()

      changeset =
        RebellionPactMember.changeset(%RebellionPactMember{}, %{
          rebellion_pact_id: -1,
          player_id: ada.id
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{rebellion_pact: [_]} = errors_on(changeset)

      # Anchor — a valid pact with an invalid player likewise fails,
      # against a real `assoc_constraint(:player)` (not vacuously
      # passing because the pact reference alone already errors).
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      changeset =
        RebellionPactMember.changeset(%RebellionPactMember{}, %{
          rebellion_pact_id: pact.id,
          player_id: -1
        })

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{player: [_]} = errors_on(changeset)
    end

    test "committed?/1, declined?/1, outstanding?/1, and informer?/1 read the secret state" do
      {world, lord, wes, ada, bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      outstanding = insert_member!(pact, ada)
      committed = insert_member!(pact, bo, %{commit_status: :committed})
      declined = insert_member!(pact, wes, %{commit_status: :declined, informer: true})

      assert RebellionPactMember.outstanding?(outstanding)
      refute RebellionPactMember.committed?(outstanding)
      refute RebellionPactMember.declined?(outstanding)
      refute RebellionPactMember.informer?(outstanding)

      assert RebellionPactMember.committed?(committed)
      refute RebellionPactMember.outstanding?(committed)

      assert RebellionPactMember.declined?(declined)
      assert RebellionPactMember.informer?(declined)
    end
  end

  describe "RebellionPact roster/committed_members/informer helpers" do
    test "roster/1 lists every invited member regardless of their secret answer" do
      {world, lord, wes, ada, bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      insert_member!(pact, wes, %{commit_status: :committed})
      insert_member!(pact, ada)
      insert_member!(pact, bo, %{commit_status: :declined})

      pact = Repo.preload(pact, :members)

      assert Enum.sort(RebellionPact.roster(pact)) == Enum.sort([wes.id, ada.id, bo.id])
    end

    test "committed_members/1 filters to only the secretly committed" do
      {world, lord, wes, ada, bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      insert_member!(pact, wes, %{commit_status: :committed})
      insert_member!(pact, ada, %{commit_status: :committed})
      insert_member!(pact, bo, %{commit_status: :declined})

      pact = Repo.preload(pact, :members)

      committed_player_ids =
        pact |> RebellionPact.committed_members() |> Enum.map(& &1.player_id) |> Enum.sort()

      assert committed_player_ids == Enum.sort([wes.id, ada.id])
    end

    test "informer/1 finds the single betrayer, if any" do
      {world, lord, wes, ada, bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      insert_member!(pact, wes)
      insert_member!(pact, ada)
      informer_member = insert_member!(pact, bo, %{informer: true})

      pact = Repo.preload(pact, :members)

      found = RebellionPact.informer(pact)
      assert found.id == informer_member.id
      assert found.player_id == bo.id
    end

    test "informer/1 returns nil when no one has betrayed the plot" do
      {world, lord, wes, ada, _bo} = lord_and_vassals_fixture()
      pact = insert_pact!(%{world_id: world.id, lord_player_id: lord.id, opener_player_id: wes.id, strike_turn: 50})

      insert_member!(pact, ada)

      pact = Repo.preload(pact, :members)

      assert RebellionPact.informer(pact) == nil
    end
  end
end
