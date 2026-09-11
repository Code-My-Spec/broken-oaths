defmodule BrokenOaths.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: BrokenOaths.Vault
end
