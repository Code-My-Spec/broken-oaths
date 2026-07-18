defmodule BrokenOaths.Repo.Migrations.AddReadAtToChatMessages do
  use Ecto.Migration

  # Story 900: nullable read marker, set by `BrokenOaths.Chat.mark_read/3`
  # for every not-yet-read message a viewer didn't send — `nil` means
  # unread. Also adds a `(conversation_id, id)` index: `id` (not
  # `inserted_at`) is the ordering/pagination key `BrokenOaths.Chat`
  # uses for "recent 50" / "load older", since insertion order is
  # exactly id order and immune to timestamp-precision ties under a
  # tight burst of messages.
  def change do
    alter table(:chat_messages) do
      add :read_at, :naive_datetime
    end

    create index(:chat_messages, [:conversation_id, :id])
  end
end
