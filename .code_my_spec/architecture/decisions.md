# Architecture Decision Records

Index of every ADR in `.code_my_spec/architecture/decisions/`.

## Project-specific decisions

| ADR | Status | Decision |
|---|---|---|
| [hex-globe-geometry](decisions/hex-globe-geometry.md) | Accepted (implemented) | Custom Goldberg polyhedron GP(f,0) mesh in Elixir — no library; gameplay is graph traversal over per-tile neighbor lists |
| [canvas-globe-rendering](decisions/canvas-globe-rendering.md) | Accepted (implemented) | Canvas impostor-first globe renderer, no WebGL; JS owns camera/pixels only, all game state server-side and LiveView-testable |
| [world-process-architecture](decisions/world-process-architecture.md) | Accepted | One GenServer per world (Registry + DynamicSupervisor) with in-process 60s turn tick; no job framework for MVP |
| [game-state-persistence](decisions/game-state-persistence.md) | Accepted | Persist the mutable delta (players/units/cities/orders/fog) over the seed; never store derived terrain or geometry |

## Standard-stack decisions (pre-made)

| ADR | Status | Decision |
|---|---|---|
| [elixir](decisions/elixir.md) | Accepted (pre-made) | Elixir as the application language |
| [phoenix](decisions/phoenix.md) | Accepted (pre-made) | Phoenix web framework |
| [liveview](decisions/liveview.md) | Accepted (pre-made) | Phoenix LiveView for interactive UI |
| [tailwind](decisions/tailwind.md) | Accepted (pre-made) | Tailwind CSS for styling |
| [daisyui](decisions/daisyui.md) | Accepted (pre-made) | DaisyUI component library |
| [phx-gen-auth](decisions/phx-gen-auth.md) | Accepted (pre-made) | phx.gen.auth for authentication (already implemented in this project) |
| [pow-assent-integrations](decisions/pow-assent-integrations.md) | Accepted (pre-made) | PowAssent + CodeMySpec generators for OAuth/integrations when needed (no MVP requirement yet) |
| [bdd-testing](decisions/bdd-testing.md) | Accepted (pre-made) | SexySpex BDD executable specifications |
| [wallaby](decisions/wallaby.md) | Accepted (pre-made) | Wallaby for browser E2E testing |
| [req_cassette](decisions/req_cassette.md) | Accepted (pre-made) | ReqCassette for HTTP fixture recording |
| [dotenvy](decisions/dotenvy.md) | Accepted (pre-made) | Dotenvy for environment configuration |
| [resend](decisions/resend.md) | Accepted (pre-made) | Resend for transactional email |
| [hetzner-deployment](decisions/hetzner-deployment.md) | Accepted (pre-made) | Hetzner for deployment |
