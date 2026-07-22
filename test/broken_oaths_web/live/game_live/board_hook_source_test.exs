defmodule BrokenOathsWeb.GameLive.BoardHookSourceTest do
  @moduledoc """
  Regression guard for the board's client-side canvas hook (QA issues
  d80792c6 "long press selects text", 551f9a55 "textures ripple on
  panning", 46047ea6 "hexes not super obvious") — same "the canvas
  board itself is never asserted, but plain server-side source IS"
  status `SpriteManifestTest`'s own moduledoc already establishes for
  `assets/js/globe_render.js`.

  `BrokenOathsWeb.GameLive.Play`'s `.Board` colocated hook is extracted
  to a separate compiled JS asset at build time (`Phoenix.LiveView.
  ColocatedHook`) — it never appears in a rendered LiveView's own HTML,
  so it can't be asserted via `Phoenix.LiveViewTest`. These tests read
  `play.ex`'s own source instead, the same "parse the plain artifact
  this test CAN read directly" move `SpriteManifestTest` already makes
  for `globe_render.js`. Actual visual confirmation (no shimmer, a
  faint grid, no native callout on a real touch device) is a human/
  Vibium QA pass, not something ExUnit can see.
  """

  use ExUnit.Case, async: true

  @play_path Path.join([File.cwd!(), "lib", "broken_oaths_web", "live", "game_live", "play.ex"])
  @globe_render_path Path.join([File.cwd!(), "assets", "js", "globe_render.js"])

  setup_all do
    {:ok,
     play_source: File.read!(@play_path), globe_render_source: File.read!(@globe_render_path)}
  end

  describe "QA issue d80792c6 — long press selects text" do
    test "the board hook's pointerdown handler suppresses the native touch gesture at its source",
         %{play_source: source} do
      [_before, after_pointerdown] =
        String.split(source, ~s[addEventListener("pointerdown", (e) => {], parts: 2)

      assert after_pointerdown =~ ~s{e.pointerType === "touch"}
      assert after_pointerdown =~ "e.preventDefault()"
    end

    test "the board hook still prevents the desktop right-click menu", %{play_source: source} do
      assert source =~ ~s{addEventListener("contextmenu", (e) => e.preventDefault())}
    end
  end

  describe "QA issue 551f9a55 — textures ripple on panning" do
    test "the frame disables image smoothing before the terrain pattern fill runs", %{
      play_source: source
    } do
      smoothing_index = :binary.match(source, "ctx.imageSmoothingEnabled = false") |> elem(0)
      fill_index = :binary.match(source, "GR.tracePolygon(ctx, R, row, 7)") |> elem(0)

      assert smoothing_index < fill_index,
             "expected `ctx.imageSmoothingEnabled = false` to run before the terrain fill loop, so the pattern fill itself gets nearest-neighbor sampling instead of the shimmering default"

      # Only ONE assignment left — it used to be set again, redundantly,
      # right before the decor billboard loop; the ripple fix moved it
      # to the top of `draw()` so it covers the terrain layer too.
      assert length(:binary.matches(source, "ctx.imageSmoothingEnabled = false")) == 1
    end

    test "the pattern pool anchors its zoom-transform to a pixel-snapped tile center", %{
      globe_render_source: source
    } do
      assert source =~ "Math.round(px)"
      assert source =~ "Math.round(py)"
    end
  end

  describe "owner rings — telling one player's units from another" do
    test "the owner color helper reserves one color for the viewer's own units", %{
      play_source: source
    } do
      [_before, owner_color] = String.split(source, "ownerColor(u) {", parts: 2)
      [owner_color_body, _rest] = String.split(owner_color, "},", parts: 2)

      # Own units get a reserved color; an unowned (barbarian) unit reads
      # neutral; everyone else indexes the deterministic palette.
      assert owner_color_body =~ "if (u.own) return"
      assert owner_color_body =~ "u.player_id == null"
      assert owner_color_body =~ "this.OWNER_COLORS["
    end

    test "the palette holds several distinct colors so two rivals stay apart", %{
      play_source: source
    } do
      [_before, palette] = String.split(source, "OWNER_COLORS: [", parts: 2)
      [entries, _rest] = String.split(palette, "]", parts: 2)

      colors = Regex.scan(~r/#[0-9a-fA-F]{6}/, entries) |> List.flatten()
      assert length(colors) >= 4
      assert length(Enum.uniq(colors)) == length(colors)
    end

    test "the unit draw loop strokes an owner-colored hex border on each unit's tile", %{
      play_source: source
    } do
      [_before, unit_loop] = String.split(source, "for (const u of this.units) {", parts: 2)
      [unit_loop_body, _rest] = String.split(unit_loop, "if (this.path", parts: 2)

      assert unit_loop_body =~ "this.ownerColor(u)"
      # The owner indicator is the unit's OWN tile hex polygon stroked in
      # the owner color (playtest: "color the hex border instead of a ring").
      assert unit_loop_body =~ "tileById.get(u.tile_id)"
      assert unit_loop_body =~ "GR.tracePolygon(ctx, R, trow, 7)"
      assert unit_loop_body =~ "ctx.strokeStyle = oc"
    end
  end

  describe "playtest issue cee40da6 — city name + build-progress fill" do
    test "the city draw loop labels each city with its own name, stroked for legibility", %{
      play_source: source
    } do
      [_before, city_loop] = String.split(source, "for (const c of this.cities) {", parts: 2)
      [city_loop_body, _rest] = String.split(city_loop, "// Story 759d02c8", parts: 2)

      assert city_loop_body =~ "ctx.fillText(c.name, px, labelY)"
      # A dark outline behind the fill keeps the label legible over any
      # terrain color underneath it, not just a fixed background.
      assert city_loop_body =~ "ctx.strokeText(c.name, px, labelY)"
      assert city_loop_body =~ ~s{ctx.textAlign = "center"}
    end

    test "the city draw loop fills a bar sized off the banked/cost fraction, clamped both ways",
         %{play_source: source} do
      [_before, city_loop] = String.split(source, "for (const c of this.cities) {", parts: 2)
      [city_loop_body, _rest] = String.split(city_loop, "// Story 759d02c8", parts: 2)

      assert city_loop_body =~ "ctx.fillRect("
      # Clamped both directions before it ever reaches the canvas — an
      # overflow-banked head item (past 1.0) never draws past the
      # track's own width, and never a negative one either.
      assert city_loop_body =~ "Math.min(1, Math.max(0, c.progress))"
    end

    test "a hostile (fogged) city draws no bar at all — gated on the field its own marker never carries",
         %{play_source: source} do
      [_before, city_loop] = String.split(source, "for (const c of this.cities) {", parts: 2)
      [city_loop_body, _rest] = String.split(city_loop, "// Story 759d02c8", parts: 2)

      assert city_loop_body =~ "if (c.progress != null)"
    end
  end

  describe "QA issue 46047ea6 — hexes not super obvious" do
    test "every drawn tile gets its own faint edge stroke", %{play_source: source} do
      [_before, terrain_loop] =
        String.split(source, "for (const {row, cx, cy} of order) {", parts: 2)

      [tile_loop_body, _rest] =
        String.split(terrain_loop, "// Terrain decor billboards", parts: 2)

      assert tile_loop_body =~ "ctx.stroke()"
      assert tile_loop_body =~ "ctx.strokeStyle ="
      # Subtle, per the issue's own ask — a low alpha, not a bold line.
      assert tile_loop_body =~ ~r/rgba\(\s*\d+,\s*\d+,\s*\d+,\s*0\.\d+\)/
      assert tile_loop_body =~ "ctx.lineWidth = 1"
    end
  end
end
