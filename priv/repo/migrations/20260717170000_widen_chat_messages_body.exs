defmodule BrokenOaths.Repo.Migrations.WidenChatMessagesBody do
  use Ecto.Migration

  # QA issue eaeb3807: the original `create_chat_messages` migration
  # left `body` as a bare `:string`, which Postgres defaults to
  # `varchar(255)` — but `BrokenOaths.Chat.Message.changeset/2` (and
  # the story's documented cap) allows up to 500 characters. Any body
  # 256-500 chars long passed the Ecto changeset validation and then
  # blew up the DB insert with `StringDataRightTruncation`, crashing
  # the LiveView/component instead of delivering the message. Widen
  # the column to match the changeset's actual, promised limit.
  def up do
    alter table(:chat_messages) do
      modify :body, :string, size: 500
    end
  end

  def down do
    alter table(:chat_messages) do
      modify :body, :string, size: 255
    end
  end
end
