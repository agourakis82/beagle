# Cloud Code UI Redesign Prompt

Use this prompt to hand the frontend redesign to another coding agent or Cloud
Code lane.

```text
You are redesigning the UI/UX of /home/devsounio/beagle/apps/project-cockpit.

Read first:
- /home/devsounio/README.md
- /home/devsounio/PROJECTS.md
- /home/devsounio/projects/PROJECT_POSTURE_POLICY.md
- /home/devsounio/beagle/apps/project-cockpit/README.md
- /home/devsounio/beagle/apps/project-cockpit/docs/UI_HANDOFF_BRIEF.md
- /home/devsounio/beagle/apps/project-cockpit/docs/FRONTEND_BACKEND_CONTRACT.md
- /home/devsounio/beagle/apps/project-cockpit/docs/FILE_OWNERSHIP_CONTRACT.md

Critical truth:
- this product is a sovereign research + supercomputing control surface
- it is not a generic admin dashboard
- cluster truth != research operations != project posture != workspace habitat continuity
- Sounio = always-on
- Hyperbolic Semantic Networks = warm
- ABIDE is a research operation, not a cluster property

Your lane:
- own the frontend redesign
- focus on /projects first, then /projects/:slug
- improve visual hierarchy, layout, interaction design, and component structure
- make the UI feel like a command bridge, not a card pile

Do not do these:
- do not rewrite backend semantics without coordination
- do not flatten cluster truth and research operations together
- do not invent new project posture meanings
- do not touch K8S/deployment files unless explicitly handed off

Preferred files to own:
- /home/devsounio/beagle/apps/project-cockpit/src/App.jsx
- /home/devsounio/beagle/apps/project-cockpit/src/App.css
- new files under /home/devsounio/beagle/apps/project-cockpit/src/

Existing APIs you should design around:
- GET /api/catalog/executive
- GET /api/catalog/project-posture-policy
- GET /api/projects/:slug/mission-control
- GET /api/projects/:slug/cluster/lane-truth
- GET /api/projects/:slug/research/operations
- GET /api/projects/:slug/go-work-now
- POST /api/projects/:slug/go-work-now/actions/:actionId

Priority outcomes:
1. /projects becomes a compelling daily entrypoint
2. warm vs always-on becomes instantly legible
3. the user can safely activate/standby a habitat without confusion
4. the product feels worthy of sovereign project work

Report back with:
- files changed
- assumptions made
- any API gaps you hit
- what backend/platform files must stay untouched
```
