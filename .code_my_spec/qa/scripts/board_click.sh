#!/usr/bin/env bash
# board_click.sh <tile_id> <left|right>
#
# GameLive.Play's board (`/play/:id`) is canvas-only — no tile DOM
# (see play.ex's own moduledoc: "Canvas-only board: no tile DOM").
# There is no `[phx-value-id]`-style selector to click. The client hook
# (`this.` in play.ex's `.Board` colocated hook) listens for raw
# PointerEvents on `#board-viewport` and hit-tests them against tile
# geometry pushed over the wire (`game:window`).
#
# This script reaches into the live LiveView hook instance via
# `window.liveSocket.main.viewHooks` (confirmed empirically during
# story 891 QA — this app has exactly one hook, keyed by ref, whose
# `.el.id === "board-viewport"`), asks it to project a known tile_id's
# center to screen coordinates the same way it projects for painting,
# and dispatches a synthetic PointerEvent at that exact point:
#
#   - left click (button 0)  -> selects the unit/city/tile there
#   - right click (button 2) -> queues a move, OR (if a hostile unit or
#     camp sits on that exact tile) issues an attack order — see
#     `orderMove` in play.ex's board hook
#
# `tile_id` must be one of the ids currently in the client's
# fog-filtered window (`h.tiles` — visible ∪ explored tiles only). Use
# board_state.sh to list them, and to check adjacency before choosing a
# target for "in range" vs "out of range" attack scenarios.
#
# Usage:
#   ./board_click.sh 14741 left
#   ./board_click.sh 14742 right
#
# Requires: vibium CLI already navigated to /play/<world_id> and
# logged in (sandbox disabled — the vibium daemon socket lives outside
# the default sandbox's writable allowlist).

set -euo pipefail

TILE_ID="${1:?usage: board_click.sh <tile_id> <left|right>}"
SIDE="${2:?usage: board_click.sh <tile_id> <left|right>}"

case "$SIDE" in
  left)  BTN=0; BTNS=1 ;;
  right) BTN=2; BTNS=2 ;;
  *) echo "second arg must be 'left' or 'right'" >&2; exit 1 ;;
esac

vibium eval "(function(){
  try {
    const h = Object.values(window.liveSocket.main.viewHooks)[0];
    if (!h) return 'ERR: no board hook found on this page — are you on /play/:id?';
    const rect = h.el.getBoundingClientRect();
    const c = h.center(${TILE_ID});
    if (!c) return 'ERR: tile ${TILE_ID} is not in the current fog-filtered window (h.tiles) — pick a known tile id (see board_state.sh).';
    const p = h.project(c[0], c[1], c[2]);
    const clientX = rect.left + p.px;
    const clientY = rect.top + p.py;
    function fire(type, opts) {
      const ev = new PointerEvent(type, Object.assign({
        bubbles: true, cancelable: true, composed: true,
        clientX, clientY, pointerId: Math.floor(Math.random() * 100000) + 1,
        pointerType: 'mouse', isPrimary: true, view: window
      }, opts));
      h.el.dispatchEvent(ev);
    }
    fire('pointerdown', {button: ${BTN}, buttons: ${BTNS}});
    fire('pointerup', {button: ${BTN}, buttons: 0});
    return JSON.stringify({ok: true, tile: ${TILE_ID}, side: '${SIDE}', clientX, clientY});
  } catch (e) {
    return 'ERR: ' + e.message;
  }
})()"
