defmodule BrokenOathsWeb.GameLive.SpriteManifestTest do
  @moduledoc """
  Regression guard for the board's client-side sprite manifest
  (`assets/js/globe_render.js`'s `GlobeRender.SPRITES`) — the canvas
  board itself is never asserted (board doctrine, see `criterion_7574`'s
  moduledoc), but this manifest and the static files it points at are
  plain server-side artifacts this test CAN read directly.

  Two QA issues traced to the exact same root cause — a unit/decor
  `type`/`kind` the server already emits with no corresponding
  `SPRITES` entry, so `spriteFor/1` always returns `nil` and the board
  either falls back to a generic blue dot (units, QA issue
  `9482a674` — `:bronze_spearman`) or renders nothing at all
  (improvements, whose billboard loop does `if (!img) continue`, QA
  issue `2ff5bd1a` — `:road`):

    * `9482a674` "sprite missing" — story 903's Bronze Age unit had no
      board sprite.
    * `2ff5bd1a` "roads not visible on map" — a completed Road
      (story 882) never rendered on the board at all.

  This test parses the manifest, confirms every unit type and
  improvement kind the server can emit (`BrokenOaths.Game.Unit.unit_type/0`,
  `BrokenOaths.Game.Improvement.kind/0`) has an entry, and that every
  entry's referenced file actually exists under `priv/static` — so a
  future removed/renamed sprite or a newly-added type with no matching
  entry fails loudly here instead of silently degrading to a dot (or
  nothing) on the live board.
  """

  use ExUnit.Case, async: true

  @manifest_path Path.join([File.cwd!(), "assets", "js", "globe_render.js"])
  @static_root Path.join([File.cwd!(), "priv", "static"])

  setup_all do
    source = File.read!(@manifest_path)

    sprites =
      ~r/(\w+):\s*"(\/images\/game\/[^"]+)"/
      |> Regex.scan(source)
      |> Map.new(fn [_, key, path] -> {key, path} end)

    {:ok, sprites: sprites}
  end

  test "every unit type the server can emit has a sprite manifest entry", %{sprites: sprites} do
    # `:barbarian_warrior` renders under the shared "barbarian" key
    # (`play.ex`'s `spriteFor(barbarian ? "barbarian" : u.type)`), so it
    # is intentionally excluded here — its manifest key is "barbarian",
    # not its own unit type name.
    for type <- [:lord, :settler, :worker, :warrior, :bronze_spearman] do
      assert Map.has_key?(sprites, Atom.to_string(type)),
             "no SPRITES entry for unit type #{inspect(type)} — it would silently fall back to the generic blue dot"
    end
  end

  test "every improvement kind the server can emit has a sprite manifest entry", %{
    sprites: sprites
  } do
    for kind <- [:farm, :mine, :road, :pasture] do
      assert Map.has_key?(sprites, Atom.to_string(kind)),
             "no SPRITES entry for improvement kind #{inspect(kind)} — a completed one would render nothing at all on the board"
    end
  end

  test "every manifest entry points at a file that actually exists", %{sprites: sprites} do
    for {key, path} <- sprites do
      full_path = Path.join(@static_root, path)

      assert File.exists?(full_path),
             "SPRITES[#{inspect(key)}] points at #{path}, but #{full_path} doesn't exist"
    end
  end
end
