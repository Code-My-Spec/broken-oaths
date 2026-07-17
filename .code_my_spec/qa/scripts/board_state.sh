#!/usr/bin/env bash
# board_state.sh [tile_id]
#
# Dumps the board hook's current client-side state as JSON: own units
# (id, type, tile_id, hp, movement, order), visible camps, visible
# cities, the currently selected unit id, and the full list of
# fog-known tile ids (`h.tiles`) — i.e. the only tile ids `board_click.sh`
# can target right now.
#
# With a `tile_id` argument, also computes that tile's neighbor ids
# among the currently-known tile set, using an edge-sharing test on the
# tile corner geometry the server already pushes (`game:window`'s
# `[id, color, decor, tex, cx, cy, cz, corner1x, corner1y, corner1z, ...]`
# rows — see play.ex's `tile_row/3`). Two known tiles are adjacent iff
# they share >= 2 corner points (exact match: both sides are rounded to
# 4 decimals server-side via `round4/1` before being sent, so string
# equality on the rounded triplet is reliable). This is a client-only
# stand-in for the server's real `neighbors` list
# (`BrokenOaths.Worlds.Globe`) — it can only answer for tiles already
# in the fog window, but that's exactly the set `board_click.sh` can
# act on anyway. Use this to pick a genuinely adjacent tile ("warrior
# strikes the barbarian next door") vs a genuinely non-adjacent one
# ("two tiles is too far") with confidence, rather than eyeballing a
# screenshot.
#
# Usage:
#   ./board_state.sh
#   ./board_state.sh 14741
#
# Requires: vibium CLI already navigated to /play/<world_id> (sandbox
# disabled).

set -euo pipefail

TILE_ID="${1:-}"

vibium eval "(function(){
  const h = Object.values(window.liveSocket.main.viewHooks)[0];
  if (!h) return 'ERR: no board hook found on this page — are you on /play/:id?';

  function corners(tileId) {
    const row = h.tileById.get(tileId);
    if (!row) return null;
    const out = [];
    for (let i = 7; i < row.length; i += 3) out.push(row[i] + ',' + row[i+1] + ',' + row[i+2]);
    return out;
  }
  function adjacent(a, b) {
    const ca = corners(a), cb = corners(b);
    if (!ca || !cb) return null;
    const setB = new Set(cb);
    return ca.filter((x) => setB.has(x)).length >= 2;
  }

  const knownTileIds = h.tiles.map((r) => r[0]);
  const out = {
    units: h.units,
    camps: h.camps,
    cities: h.cities,
    selectedId: h.selectedId,
    knownTileCount: knownTileIds.length,
    knownTileIds
  };

  const target = ${TILE_ID:-null};
  if (target != null) {
    out.neighborsOfTarget = knownTileIds.filter((id) => id !== target && adjacent(target, id));
  }

  return JSON.stringify(out);
})()"
