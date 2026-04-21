# Project Cockpit Frontend/Backend Contract

This file exists to keep UI redesign work from drifting into model breakage.

## Core contract

The backend is currently the semantic authority.

The frontend may radically redesign layout and interaction, but should preserve
the meaning of these packets.

## Canonical API surfaces

### Project catalog

- `GET /api/catalog/executive`
- `GET /api/catalog/project-posture-policy`

These are used by `/projects`.

Important fields:

- `projectPosturePolicy`
- `projects[].operatingPosture`
- `projects[].goWorkNow`

### Per-project sovereign surfaces

- `GET /api/projects/:slug/mission-control`
- `GET /api/projects/:slug/cluster/lane-truth`
- `GET /api/projects/:slug/research/operations`
- `GET /api/projects/:slug/go-work-now`

These are different surfaces, not alternate names for the same thing.

### Habitat mutation route

- `POST /api/projects/:slug/go-work-now/actions/:actionId`

Supported action ids today:

- `activate-habitat`
- `standby-habitat`

These are real mutations.

They should be rendered with explicit operator intent, loading states, and
honest post-action feedback.

## Semantic packets

### `project posture`

Meaning:

- what kind of sovereign surface the project is

Current values:

- `always-on`
- `warm`
- `cold`

Current assignments:

- `sounio = always-on`
- `hyperbolic-semantic-networks = warm`

### `clusterLaneTruth`

Meaning:

- infrastructure truth only

Examples:

- admitted nodes
- autoheal status
- worker health
- lane selector / admission scope

Must not be treated as:

- latest job state
- latest benchmark state

### `researchOperations`

Meaning:

- observed runs/jobs/campaigns

Examples:

- latest observed operation
- recent observed operations
- run id
- job id
- payload mode
- persist mode

Must not be treated as:

- stable cluster fact

### `workspaceState`

Meaning:

- the observed continuity state of the sovereign habitat

Typical values:

- `live`
- `recovering`
- `standby`-like semantics through `NotFound`

Important nuance:

- for warm projects, `NotFound` can be a healthy intentional standby state

## UI expectations

The frontend should expose these distinctions clearly:

- project posture explains the house
- workspace state explains whether the house is currently occupied
- cluster truth explains the road/power/wiring
- research operations explain what work recently ran through the house

## Mutation behavior

The UI should assume these action properties:

- actions are asynchronous
- the server returns updated packets, but observation may still converge over a
  few seconds
- a successful action does not always mean the final observed state is already
  reflected in the same frame

So the UI should:

- show loading state
- show returned mutation output
- allow refresh/re-poll patterns
- avoid pretending that mutation is instant if observation is still catching up

## File boundaries

Cloud Code or frontend ownership should prefer:

- `/home/devsounio/beagle/apps/project-cockpit/src/**`

Backend/platform ownership should prefer:

- `/home/devsounio/beagle/apps/project-cockpit/server/index.mjs`
- `/home/devsounio/beagle/k8s/project-cockpit/**`

If the redesign needs a backend addition:

- ask for a narrow packet or route change
- do not silently repurpose existing semantics
