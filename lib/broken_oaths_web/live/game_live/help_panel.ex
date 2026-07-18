defmodule BrokenOathsWeb.GameLive.HelpPanel do
  @moduledoc """
  A first-pass in-game reference (QA issue 937ea82b "There is no help
  or wiki"): an always-reachable `help-button` that opens a modal of
  concise, scannable sections covering every mechanic that exists in
  the game TODAY — turns, movement/fog, founding, production, growth
  and worked tiles, resources, terrain improvements, the unit roster,
  healing, combat, barbarians, city defense, the tech tree, and the
  Progress panel's own milestones.

  Content is static prose (no external wiki, no `BrokenOaths.Game`
  reads) but the NUMBERS quoted throughout are pulled straight from the
  game's own constants (`BrokenOaths.Game.Combat`, `BrokenOaths.Game.
  CityDefense`, `BrokenOaths.Game.Camps`, `BrokenOaths.Game.Production`,
  `BrokenOaths.Game.Research`, `BrokenOaths.Game.Turn`'s healing phase,
  `BrokenOaths.Game.Yields.threshold/2`) rather than invented — see each
  section's own comment for exactly which module/line it mirrors, so a
  future balance change has one clear place to update this copy too.

  A stateful `LiveComponent` (own local `:open?`, own
  `phx-target={@myself}` events) — the same self-contained toggle shape
  `GameLive.ChatPanel`/`GameLive.TechPanel` already establish. Mounted
  unconditionally by `BrokenOathsWeb.GameLive.Play` in the top bar, so
  `help-button` is always reachable regardless of what's selected on
  the board — it has no interaction with unit/city/tile/camp selection
  at all (not part of the "one side panel at a time" rule).
  """

  use BrokenOathsWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:open?, fn -> false end)}
  end

  @impl true
  def handle_event("toggle_help", _params, socket) do
    {:noreply, assign(socket, open?: !socket.assigns.open?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <button
        type="button"
        data-test="help-button"
        phx-click="toggle_help"
        phx-target={@myself}
        class="btn btn-sm btn-outline gap-1"
      >
        <.icon name="hero-question-mark-circle" class="w-4 h-4" /> Help
      </button>

      <div :if={@open?} class="modal modal-open" data-test="help-modal">
        <div class="modal-box max-w-2xl max-h-[85vh] overflow-y-auto select-text [-webkit-touch-callout:default]">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-bold text-lg">How to Play</h3>
            <button
              type="button"
              data-test="close-help"
              phx-click="toggle_help"
              phx-target={@myself}
              class="btn btn-ghost btn-xs btn-circle"
            >
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>

          <div class="flex flex-col gap-4 text-sm">
            <.section test="help-section-turns" title="Turns">
              <p>
                The world advances automatically every <strong>60 seconds</strong>
                by default (each world's own turn length, chosen once when it's
                created) — there's no "End Turn" button. Queue whatever orders
                you want at any point; they all resolve the instant the boundary
                hits.
              </p>
            </.section>

            <.section test="help-section-movement" title="Movement &amp; Fog of War">
              <p>
                Every unit has a fixed movement allowance each turn: Lord and
                Settler 2, Worker 2, Warrior 1, Bronze Spearman 1. Right-click
                a tile (long-press on touch) to queue a move — orders resolve
                automatically at the boundary and can march through fog.
              </p>
              <p>
                Tiles you can see right now are <em>visible</em>; tiles you've
                seen before but can't see this instant stay <em>explored</em>
                (dimmed, remembered terrain). Everything else is hidden under
                the fog shroud.
              </p>
            </.section>

            <.section test="help-section-founding" title="Founding Cities">
              <p>
                A Settler's Found City action trades itself for a brand-new,
                size-1 city immediately — no turn boundary required — on any
                land tile at least <strong>4 hexes</strong>
                (over the land graph) from every other city, yours or a
                rival's. A founded city's starting territory is the tile
                itself plus its six neighboring hexes; more tiles are added
                as it grows.
              </p>
            </.section>

            <.section test="help-section-production" title="Production">
              <p>
                Every city produces a flat <strong>5 production/turn</strong>
                base plus whatever its worked tiles contribute. Queue from the
                Build list: Settler (100), Worker (60), Warrior (40), Granary
                (60, needs Pottery), Bronze Spearman (60, needs the Bronze
                Age). Queued items can be reordered toward the front for free,
                or abandoned any time before completion (forfeiting whatever
                production was already banked into them).
              </p>
            </.section>

            <.section test="help-section-growth" title="City Growth &amp; Worked Tiles">
              <p>
                A city's center tile is always worked for free. Every other
                worked tile is either auto-assigned on growth (picked for the
                best combined food+production) or chosen by hand from the City
                panel's Work/Unwork buttons, from the tiles inside the city's
                own territory.
              </p>
              <p>
                Banked food grows a city from size 1→2→3→4 at 20/30/40 food
                (the Stone Age cap), then 4→5→6 at 50/60 once you've reached
                the Bronze Age.
              </p>
            </.section>

            <.section test="help-section-resources" title="Resources">
              <p>
                Bonus resources (Cattle, Sheep, Wheat, Stone) show up the
                moment you can see the tile — no reveal tech needed. Cattle,
                Sheep, and Wheat each add +1 food; Stone adds +1 production.
                A Cattle or Sheep tile can also carry a Pasture once you've
                researched Animal Husbandry.
              </p>
            </.section>

            <.section test="help-section-improvements" title="Terrain Improvements">
              <p>
                Workers build improvements over several turns standing still
                on the target tile:
              </p>
              <ul class="list-disc list-inside opacity-80">
                <li>Farm — +2 food, 3 turns, flat terrain with no feature only.</li>
                <li>
                  Mine — +2 production, 5 turns (3 turns once you've researched
                  Mining), hills only.
                </li>
                <li>
                  Road — no yield bonus yet; its real effect (cheaper movement
                  along it) is planned but not implemented in this build.
                </li>
                <li>
                  Pasture — +2 food, 4 turns, only on a Cattle/Sheep tile and
                  only after Animal Husbandry.
                </li>
              </ul>
              <p>
                A barbarian walking onto a completed improvement pillages it;
                a worker resuming the same kind repairs it in just 1 turn.
              </p>
            </.section>

            <.section test="help-section-units" title="Warriors, Workers &amp; Settlers">
              <ul class="list-disc list-inside opacity-80">
                <li>
                  Lord — 150 HP, 2 movement. Your unique leader: grants +2
                  combat strength to friendly units fighting adjacent to it,
                  and if it ever falls, a fresh heir arrives at your capital
                  some turns later.
                </li>
                <li>Settler — 50 HP, 2 movement. Spend it once to found a city.</li>
                <li>Worker — 10 HP, 2 movement. Builds terrain improvements.</li>
                <li>
                  Warrior — 100 HP, 1 movement, 10 combat strength. Your basic
                  Stone Age soldier.
                </li>
                <li>
                  Bronze Spearman — 120 HP, 1 movement, 16 combat strength.
                  Unlocked once you reach the Bronze Age.
                </li>
              </ul>
            </.section>

            <.section test="help-section-healing" title="Unit Healing">
              <p>
                A unit that spends <strong>no movement</strong>
                this turn heals: <strong>15 HP</strong>
                if it's garrisoned on its own city's tile, <strong>10 HP</strong>
                anywhere else inside its owner's own territory, and <strong>0 HP</strong>
                outside its own territory. Moving even one tile in a turn
                skips healing that turn entirely.
              </p>
            </.section>

            <.section test="help-section-combat" title="Combat">
              <p>
                Damage follows a Civ-style curve: 30 base damage at equal
                strength, scaling roughly 4% per point of strength
                difference, with a ±25% random roll on top. A living, adjacent
                Lord gives friendly units +2 strength; a unit defending from
                inside its OWN city fights at 1.5× its strength (the
                "fighting from the walls" bonus).
              </p>
            </.section>

            <.section test="help-section-barbarians" title="Barbarians">
              <p>
                The first time you found a city, 1-2 nearby camps (plus a
                handful of farther ones, 8-15 hexes out) appear in the
                wilderness. Each camp holds up to 2 warriors, spawning a fresh
                one every 3 turns while under that cap; its warriors roam,
                raid, and pillage any completed improvement they walk onto.
              </p>
              <p>
                A camp itself has 100 HP. Any adjacent military unit can
                attack it for its own combat strength in flat damage — camps
                never counter-attack, so a siege costs the attacker nothing
                but time. Destroying one (0 HP) pays every player who struck
                it a share of a 30-gold bounty, split by contribution.
              </p>
            </.section>

            <.section test="help-section-city-defense" title="City Defense &amp; Garrison">
              <p>
                Every city has 100 HP and a defensive strength of <strong>20 + 5 × size</strong>
                plus the summed base strength of its garrisoned military units
                (up to 3 per city). A garrisoned unit that actually fights
                back does so at 1.5× its own strength. An unthreatened city
                regains 5 HP every turn boundary; a barbarian pillage instead
                drops it to 50 HP and freezes its production for 3 turns. Any
                hostile unit closing within 3 hexes of one of your cities
                raises an approach alert.
              </p>
            </.section>

            <.section test="help-section-tech" title="Tech Tree &amp; the Bronze Age">
              <p>
                Every city generates <strong>2 × its size</strong>
                science per turn, banked toward whichever tech is currently
                selected (switching never loses progress on the one you
                switch away from). Eleven Ancient-era techs, some gated
                behind a prerequisite — a locked tech's row names exactly
                which one it's waiting on:
              </p>
              <ul class="list-disc list-inside opacity-80">
                <li>
                  Pottery — 50 science, no prerequisite. Unlocks the Granary (+2 food storage/turn).
                </li>
                <li>
                  Animal Husbandry — 50 science, no prerequisite. Unlocks the Pasture improvement.
                </li>
                <li>Mining — 75 science, no prerequisite. Mines build in 3 turns instead of 5.</li>
                <li>Sailing — 90 science, no prerequisite.</li>
                <li>Astrology — 90 science, no prerequisite.</li>
                <li>Writing — 90 science. Needs Pottery.</li>
                <li>Irrigation — 90 science. Needs Pottery.</li>
                <li>Archery — 90 science. Needs Animal Husbandry.</li>
                <li>Masonry — 100 science. Needs Mining.</li>
                <li>The Wheel — 100 science. Needs Mining.</li>
                <li>
                  Bronze Working — 100 science. Needs Mining. Advances your
                  civilization to the Bronze Age, unlocking the Bronze
                  Spearman.
                </li>
              </ul>
            </.section>

            <.section test="help-section-progress" title="Progress &amp; Milestones">
              <p>
                The Progress panel (bottom-left of the board) tracks your
                current age, science/turn, Bronze Working's banked progress
                and a turns-remaining projection, and lifetime totals: cities
                founded, camps destroyed, barbarians killed, and players
                discovered — plus four first-time milestones (first city,
                first barbarian killed, first camp destroyed, first player
                discovered).
              </p>
            </.section>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :test, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <div data-test={@test}>
      <h4 class="font-semibold mb-1">{@title}</h4>
      <div class="opacity-80 flex flex-col gap-1">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end
