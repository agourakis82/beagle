# Project Cockpit File Ownership Contract

This contract exists to prevent parallel work from turning into collision.

## Purpose

The UI redesign may happen in parallel with platform and truth work.

That is safe only if file ownership remains explicit.

## Current recommended split

### Cloud Code / UI redesign lane

Own these by default:

- [/home/devsounio/beagle/apps/project-cockpit/src/App.jsx](/home/devsounio/beagle/apps/project-cockpit/src/App.jsx)
- [/home/devsounio/beagle/apps/project-cockpit/src/App.css](/home/devsounio/beagle/apps/project-cockpit/src/App.css)
- any new files under:
  - [/home/devsounio/beagle/apps/project-cockpit/src](/home/devsounio/beagle/apps/project-cockpit/src)
  - especially future `components/`, `layout/`, `theme/`, `hooks/`

May read but should avoid mutating unless coordinated:

- [/home/devsounio/beagle/apps/project-cockpit/public/project-catalog.json](/home/devsounio/beagle/apps/project-cockpit/public/project-catalog.json)
- [/home/devsounio/beagle/apps/project-cockpit/README.md](/home/devsounio/beagle/apps/project-cockpit/README.md)

### Backend/platform lane

Own these by default:

- [/home/devsounio/beagle/apps/project-cockpit/server/index.mjs](/home/devsounio/beagle/apps/project-cockpit/server/index.mjs)
- [/home/devsounio/beagle/k8s/project-cockpit](/home/devsounio/beagle/k8s/project-cockpit)
- cross-project policy docs under:
  - [/home/devsounio/projects](/home/devsounio/projects)
  - [/home/devsounio/PROJECTS.md](/home/devsounio/PROJECTS.md)

## Forbidden overlap

Do not both edit:

- `src/App.jsx`
- `src/App.css`
- `server/index.mjs`
- `public/project-catalog.json`
- `k8s/project-cockpit/deployment.yaml`

unless ownership is explicitly handed off for that round.

## Shared-file handoff rule

If a shared file becomes necessary:

1. the current owner declares the handoff
2. the other agent takes exclusive ownership for that round
3. the first owner stops touching that file

## Safe collaboration pattern

Frontend redesign lane:

- may assume existing APIs are stable
- should first redesign presentation and component structure
- should request backend changes as narrow contracts

Backend/platform lane:

- should avoid surprise shape changes
- should preserve semantic truth
- should communicate any packet additions clearly

## Done condition for parallel safety

Parallel work is considered safe when:

- the UI can evolve fast
- semantics stay stable
- no project job truth leaks into cluster truth
- no file ownership collisions happen
