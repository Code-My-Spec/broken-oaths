# QA seed script — idempotent. Run with:
#
#     mix run priv/repo/qa_seeds.exs
#
# Creates a confirmed QA user with a known password and a deterministic
# QA world, then prints credentials and URLs. Safe to re-run: existing
# records are reused, never duplicated.

alias BrokenOaths.{Repo, Users, Worlds}
alias BrokenOaths.Users.UserToken

qa_email = "qa@broken-oaths.test"
qa_password = "qa-password-123!"

user =
  case Users.get_user_by_email(qa_email) do
    nil ->
      {:ok, user} = Users.register_user(%{email: qa_email})

      # Confirm via the magic-link flow (same path production uses)
      {encoded_token, user_token} = UserToken.build_email_token(user, "login")
      Repo.insert!(user_token)
      {:ok, {user, _expired}} = Users.login_user_by_magic_link(encoded_token)

      {:ok, {user, _expired}} = Users.update_user_password(user, %{password: qa_password})
      IO.puts("Created QA user #{qa_email}")
      user

    user ->
      IO.puts("QA user already exists: #{qa_email}")
      user
  end

qa_world =
  case Enum.find(Worlds.list_worlds(), &(&1.name == "QA World")) do
    nil ->
      {:ok, world} = Worlds.create_world(%{name: "QA World", seed: 424_242, frequency: 54})
      IO.puts("Created QA World (seed 424242)")
      world

    world ->
      IO.puts("QA World already exists (id #{world.id})")
      world
  end

IO.puts("""

=== QA credentials ===
email:    #{qa_email}
password: #{qa_password}
user id:  #{user.id}

=== QA URLs (dev server, port 4050) ===
login:         http://localhost:4050/users/log-in
world (globe): http://localhost:4050/worlds/#{qa_world.id}
world (DOM):   http://localhost:4050/worlds/#{qa_world.id}?mode=classic
mailbox:       http://localhost:4050/dev/mailbox
""")
