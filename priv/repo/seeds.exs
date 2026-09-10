# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BrokenOaths.Repo.insert!(%BrokenOaths.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Keep the preview's deterministic rebellion/vassalization walkthrough
# available whenever the deployment seed entry point runs. The scenario
# seed is idempotent and repairs an existing demo world in place.
Code.require_file("qa_seeds_rebellion.exs", __DIR__)
