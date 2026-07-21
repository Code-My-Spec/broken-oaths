defmodule BrokenOaths.Repo.Migrations.AddDisplayNameToUsers do
  use Ecto.Migration

  # Playtest issue 2a9df843: players saw each other's raw email everywhere
  # an identity was surfaced (Known Players, chat, alliances). A user now
  # chooses a global display_name — a handle shown to other players in
  # place of the email. Nullable: a user who never sets one falls back to
  # a non-email "Player ##{id}" label (see `Users.User.display_name/1`),
  # so no backfill is needed and the email is never shown to anyone else.
  def change do
    alter table(:users) do
      add :display_name, :string
    end
  end
end
