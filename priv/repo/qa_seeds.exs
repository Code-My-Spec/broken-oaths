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

# A deliberately tiny world (frequency 8 -> 642 tiles) that resolves to
# exactly two spawnable regions (per BrokenOaths.Worlds.Regions.spawnable/1's
# 175-tile habitability floor). QA World (frequency 54) has ~104 spawnable
# regions and can't be filled by hand — this fixture exists so "world just
# filled up" / abandon-and-reclaim scenarios (story 873) are testable
# through the browser with two throwaway joins.
#
# NOTE: frequency 5-6 worlds reliably trigger a Spawner crash (see issue
# 6b8a69f3-d401-4cb7-b45f-ad3ceaf414e6 — a `:land` tile fully enclosed by
# same-region `:mountain` tiles has no path to the BFS boundary and blows
# up `Map.fetch!/2`), which crashes `world_full?/1` and takes down the
# entire /play picker for every world, not just the broken one. Frequency
# 7-8 avoided it in every seed tried during QA. Do NOT lower this
# frequency without re-verifying every spawnable region is crash-safe
# (see the per-region probe in the story 873 QA session) — a bad world
# left `status: "active"` breaks /play for everyone until fixed or
# archived. The frequency-5 repro world from that bug hunt is world id 7,
# "QA World (Full Test)", left in the DB with `status: "archived"` as a
# standing repro case — do not reactivate it.
qa_fill_world =
  case Enum.find(Worlds.list_worlds(), &(&1.name == "QA World (Fill Test)")) do
    nil ->
      {:ok, world} =
        Worlds.create_world(%{name: "QA World (Fill Test)", seed: 111_222, frequency: 8})

      IO.puts("Created QA World (Fill Test) (seed 111222, 2 spawnable regions)")
      world

    world ->
      IO.puts("QA World (Fill Test) already exists (id #{world.id})")
      world
  end

IO.puts("""

=== QA credentials ===
email:    #{qa_email}
password: #{qa_password}
user id:  #{user.id}

=== QA URLs (dev server, port 4050) ===
login:              http://localhost:4050/users/log-in
world (globe):      http://localhost:4050/worlds/#{qa_world.id}
world (DOM):        http://localhost:4050/worlds/#{qa_world.id}?mode=classic
fill-test world:    http://localhost:4050/worlds/#{qa_fill_world.id}
mailbox:            http://localhost:4050/dev/mailbox
""")
