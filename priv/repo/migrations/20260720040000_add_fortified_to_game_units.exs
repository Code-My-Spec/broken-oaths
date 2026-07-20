defmodule BrokenOaths.Repo.Migrations.AddFortifiedToGameUnits do
  use Ecto.Migration

  # Story 920: the Fortify stance — a defend-capable unit (`:defend in
  # Units.Actions.available/1`) may brace immediately for a defensive
  # combat bonus (`Combat.Resolver.effective_strength/2`) until it next
  # moves or attacks. Every unit type gets the column (mirroring
  # `charges`/`temporary`, likewise generic on `Game.Unit` even though
  # only some types ever flip them) but only a `:defend`-capable type
  # ever sets it true — a barbarian or civilian-only type simply carries
  # the default and is never read for it.
  def change do
    alter table(:game_units) do
      add :fortified, :boolean, null: false, default: false
    end
  end
end
