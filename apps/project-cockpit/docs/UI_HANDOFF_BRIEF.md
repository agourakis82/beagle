# Project Cockpit UI Handoff Brief

This brief exists because the current UI/UX is not good enough.

The user feedback was direct and correct:

- the interface feels terrible
- the experience is far below the intended standard
- the product is being dragged down by a weak visual and interaction layer

This handoff is the reset point for a frontend redesign.

## What this product actually is

`project-cockpit` is not a generic admin dashboard.

It is the machine-facing and human-facing control surface for:

- sovereign project posture
- research operations
- cluster truth
- workspace habitat continuity
- public-to-private mission control crossings

The product should feel like:

- a research and supercomputing command bridge
- a sovereign project switchboard
- a serious operator environment

It should not feel like:

- a CRUD console
- a metrics wall
- a bootstrap dashboard
- a random pile of cards

## Non-negotiable modeling rules

The redesign must preserve these layers:

- `project posture`
- `cluster truth`
- `research operations`
- `workspace habitat continuity`

These are different things.

Examples:

- `ABIDE` is a research operation
- it is not cluster truth
- `Sounio = always-on`
- `Hyperbolic Semantic Networks = warm`
- a warm project is still sovereign and first-class

The UI must make these distinctions clearer, not flatter them away.

## Current product truth

Machine-level source of truth:

- [/home/devsounio/README.md](/home/devsounio/README.md)
- [/home/devsounio/PROJECTS.md](/home/devsounio/PROJECTS.md)
- [/home/devsounio/projects/PROJECT_POSTURE_POLICY.md](/home/devsounio/projects/PROJECT_POSTURE_POLICY.md)
- [/home/devsounio/projects/PARALLEL_WORK_CONTRACT_PROMPT.md](/home/devsounio/projects/PARALLEL_WORK_CONTRACT_PROMPT.md)

Cockpit app source of truth:

- [/home/devsounio/beagle/apps/project-cockpit/README.md](/home/devsounio/beagle/apps/project-cockpit/README.md)
- [/home/devsounio/beagle/apps/project-cockpit/server/index.mjs](/home/devsounio/beagle/apps/project-cockpit/server/index.mjs)
- [/home/devsounio/beagle/apps/project-cockpit/src/App.jsx](/home/devsounio/beagle/apps/project-cockpit/src/App.jsx)
- [/home/devsounio/beagle/apps/project-cockpit/src/App.css](/home/devsounio/beagle/apps/project-cockpit/src/App.css)
- [/home/devsounio/beagle/apps/project-cockpit/public/project-catalog.json](/home/devsounio/beagle/apps/project-cockpit/public/project-catalog.json)

## Current functional scope that must remain

The redesign must preserve these real behaviors:

- `/projects` is the sovereign project index
- `Go work now` packet exists per project
- warm habitats can be activated from the cockpit
- warm habitats can be returned to standby from the cockpit
- `cluster truth` is observed infrastructure truth
- `research operations` are observed job/run truth
- `mission control` is a separate project surface

## Highest-priority pages

### 1. `/projects`

This should become the true entrypoint.

It needs to answer, fast:

- what projects exist
- what posture each one has
- whether I can enter now
- whether I need to activate habitat first
- where mission control lives
- where the viewer lives
- what the latest observed research operation is

### 2. `/projects/:slug`

This should feel like the private control room for one sovereign project.

It should clearly stage:

- project identity
- posture
- live habitat state
- cluster lane truth
- research lane truth
- mission control routes

### 3. Public-to-private bridge surfaces

These should remain legible, but they are secondary to fixing the operator path.

## Interaction goals

The redesign should prioritize:

- immediate orientation
- ruthless reduction of noise
- strong information hierarchy
- obvious operator actions
- beautiful but serious visual tone

The user should be able to glance and know:

- what is live
- what is warm
- what is degraded
- what is the next safe move

## Visual direction

The redesign should feel:

- sovereign
- premium
- technical
- intentional
- spatial enough to imply a control room without becoming gimmicky

Avoid:

- generic KPI card walls
- flat bootstrap admin aesthetics
- visual clutter
- too many equal-weight panels
- random badge spam

Prefer:

- stronger typography
- clearer section framing
- more cinematic spacing
- fewer, more meaningful surfaces
- visible route hierarchy

## Engineering constraints

Do not break:

- existing API contracts unless coordinated
- existing action routes for habitat activation/standby
- project posture semantics
- the distinction between infra truth and job truth

The backend is allowed to stay ugly for a moment if the frontend redesign needs
to move first, but the semantics must remain correct.

## Definition of a successful redesign

The redesign is successful if:

- `/projects` feels like a command bridge, not a debug page
- `Sounio` and `HSN` feel like sovereign project surfaces
- warm vs always-on is immediately legible
- the user can activate a habitat and understand what happened
- cluster truth and research operations are no longer visually conflated
- the UI feels worthy of being the place where daily dev can start
