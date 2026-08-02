# SOTA Supercomputing Research 2026

This note captures the current state of the art that matters for the sovereign
supercomputing playground direction.

It is intentionally product-facing:

- what the frontier systems are doing
- what the visualization stack is doing
- what data formats are stabilizing
- what that implies for our platform

Use it together with:

1. [SOVEREIGN_SUPERCOMPUTING_PLAYGROUND_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_SUPERCOMPUTING_PLAYGROUND_BLUEPRINT.md)
2. [SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_PROJECT_COCKPIT_BLUEPRINT.md)
3. [SOVEREIGN_VSIX_ARCHITECTURE.md](/home/devsounio/beagle/k8s/hpc-sota/SOVEREIGN_VSIX_ARCHITECTURE.md)

## Executive summary

The state of the art is converging on five truths:

1. Exascale is no longer hypothetical.
2. HPC and AI are now operationally fused.
3. Remote and parallel visualization remain first-class, not optional.
4. OME-Zarr/NGFF is maturing into a serious cloud-native scientific imaging substrate.
5. WebGPU is now real enough to be a strategic target across web, desktop, and Apple platforms, but it still requires explicit runtime truth instead of optimistic assumptions.

For us, that means the platform should not be designed as:

- a nicer dashboard
- a browser wrapper around notebooks
- a thin terminal launcher

It should be designed as:

- a sovereign supercomputing playground
- with mission control, runtime truth, dataset truth, scene truth, and job provenance all treated as first-class operational surfaces

## 1. Compute frontier: exascale is here

Recent official signals:

- TOP500 lists published in 2025 continue to place exascale systems at the top of the field.
- LLNL reports that El Capitan retained the No. 1 position on the November 2025 TOP500 list with a verified 1.809 exaFLOPS.
- Aurora is described by Argonne/ALCF as one of the first exascale systems and is explicitly positioned for both simulation and AI.

Implications:

- the frontier is not just raw FLOPS; it is integrated simulation + AI + data movement
- our product should not separate “HPC surface” from “AI surface” as if they were different worlds
- the mission control model should assume jobs, models, and visualization outputs are part of one workflow

## 2. HPC is now simulation + AI + provenance

Official system narratives from the national labs have shifted:

- El Capitan is framed not just as a simulation machine, but as an exascale platform that also supports AI-heavy workflows and mixed-precision benchmarks
- Aurora is explicitly presented as a machine for both simulation and AI-enabled science

Implications:

- our mission control cannot stop at:
  - branch
  - PR
  - cluster pod
- it must also surface:
  - dataset
  - producing run
  - model or analytical pipeline
  - provenance anchor

This is one of the reasons the viewer route matters:

- the browser is not just for control
- it is for seeing the output of supercomputing work in the same sovereign surface

## 3. Remote and parallel visualization remain canonical

ParaView and ParaViewWeb still model the world correctly for large data:

- remote and/or parallel data processing is normal
- the client is not the authority
- the heavy work can stay near the data and compute

Kitware documentation and tooling continue to emphasize:

- browser-delivered visualization
- remote rendering
- hybrid local/remote application models

Implications:

- our playground should not assume all visualization must happen fully in the browser
- instead, it should support:
  - browser-side rendering where possible
  - remote/preprocessed rendering or aggregation when needed
- “viewer truth” must remain explicit:
  - observed
  - remembered
  - declared

This aligns naturally with the existing sovereign model:

- browser shell is disposable
- habitat / backend / compute surface is authoritative

## 4. OME-Zarr is maturing into the right data substrate

The OME-NGFF/OME-Zarr ecosystem keeps moving in the direction we want:

- OME-Zarr 0.5 is now a published community report
- Zarr v3 is part of the active roadmap
- coordinate systems and transformations are being treated as first-class concerns
- zipped/single-file OME-Zarr remains an active area of work

This matters because it confirms the right long-term data shape:

- multiscale
- chunked
- cloud/object-store friendly
- transform-aware
- provenance-friendly

Implications:

- our dataset lane should treat OME-Zarr as a primary citizen
- our catalog should support:
  - real datasets
  - manifests
  - explicit stubs
- scene memory should eventually preserve:
  - dataset id
  - scale
  - camera
  - channels/layers
  - overlays
  - transform/provenance anchors

## 5. WebGPU is strategically right, but runtime truth matters

Current official signals:

- MDN still marks parts of WebGPU as limited availability, which is a reminder that runtime truth must be explicit
- WebKit now reports Safari support for WebGPU outside WebXR in Safari 26.0+
- VTK’s WebGPU work is clearly active and increasingly serious
- VTK documents WebGPU backends across D3D12, Metal, and Vulkan-family environments

Implications:

- WebGPU-first is the right strategic bet
- but “WebGPU-first” must not mean “pretend success”
- the platform must tell the truth about renderer state:
  - ready
  - unavailable
  - failed

For runtime design:

- web can target WebGPU directly
- macOS and iOS naturally align with Metal-backed WebGPU paths
- Windows aligns with D3D-backed WebGPU paths

This supports the multi-runtime plan:

- Web
- Windows native
- macOS native
- iOS native

## 6. What this means for our platform

The product should be decomposed into these first-class surfaces:

### 1. Mission control

- next safe move
- publication stage
- review state
- cluster state
- truth summary

### 2. Dataset lane

- dataset catalog
- source kind
- truth source/mode
- provenance pointer

### 3. Visualization lane

- WebGPU renderer state
- scene state
- runtime capability
- browser shell status

### 4. Provenance lane

- producing project
- artifact or job reference
- generation path
- remembered vs observed provenance

### 5. Runtime capability lane

- web
- desktop
- iOS
- shell constraints and rendering target

## 7. Product decisions that follow from the research

These are the working decisions this research supports:

1. `Sounio` should remain the first deep proof surface.
2. `/projects` should remain mission control, not the full playground.
3. `/projects/sounio/viewer` is the correct first full-page viewer route.
4. WebGPU-first is the right renderer stance.
5. OME-Zarr should be treated as the default target data model for imaging-centric lanes.
6. iOS must remain first-class in the contract, not a responsive-web afterthought.

## Source anchors

Primary references we should keep revisiting:

- TOP500 lists:
  - https://top500.org/lists/top500/
- LLNL El Capitan:
  - https://www.llnl.gov/article/53596/el-capitan-retains-title-worlds-fastest-supercomputer-latest-top500
  - https://www.llnl.gov/sites/www/files/2024-12/llnl-el-capitan-fact-sheet.pdf
- OME-NGFF / OME-Zarr:
  - https://ngff.openmicroscopy.org/
  - https://ome-zarr.readthedocs.io/en/stable/
- WebGPU:
  - https://www.w3.org/TR/webgpu/
  - https://developer.chrome.com/docs/web-platform/webgpu
7. Truth surfaces are not UX fluff; they are required because runtime and data capability differ by shell.

## 8. Near-term implications for implementation

Near-term platform work should keep moving toward:

- stronger scene memory
- richer dataset catalogs
- explicit provenance payloads
- real OME-Zarr dataset binding where available
- runtime-capability-aware shells
- remote/parallel visualization escape hatches when browser-side rendering is insufficient

## Sources

- TOP500 lists:
  - https://top500.org/lists/top500/
- LLNL on El Capitan:
  - https://www.llnl.gov/article/53596/el-capitan-retains-title-worlds-fastest-supercomputer-latest-top500
  - https://www.llnl.gov/article/52061/lawrence-livermore-national-laboratorys-el-capitan-verified-worlds-fastest-supercomputer
- LLNL fact sheet on El Capitan:
  - https://www.llnl.gov/sites/www/files/2024-12/llnl-el-capitan-fact-sheet.pdf
- Argonne / ALCF on Aurora and exascale AI-science positioning:
  - https://www.alcf.anl.gov/files/Jennings_SDL_Oct_2019.pdf
- OME-NGFF / OME-Zarr:
  - https://ngff.openmicroscopy.org/
  - https://ome-zarr.readthedocs.io/en/stable/
- WebGPU:
  - https://www.w3.org/TR/webgpu/
  - https://developer.chrome.com/docs/web-platform/webgpu
- Argonne / Aurora:
  - https://www.alcf.anl.gov/aurora
  - https://www.anl.gov/aurora
- OME-Zarr / NGFF:
  - https://ngff.openmicroscopy.org/0.5/
  - https://ngff.openmicroscopy.org/rfc/2/
  - https://ngff.openmicroscopy.org/rfc/5/
  - https://ngff.openmicroscopy.org/rfc/
- WebGPU:
  - https://developer.mozilla.org/en-US/docs/Web/API/GPU/wgslLanguageFeatures
  - https://webkit.org/blog/17640/webkit-features-for-safari-26-2/
- ParaView / remote visualization:
  - https://docs.paraview.org/en/latest/ReferenceManual/parallelDataVisualization.html
  - https://kitware.github.io/paraviewweb/docs/index.html
  - https://kitware.github.io/visualizer/docs/index.html
- VTK / WebGPU:
  - https://docs.vtk.org/en/v9.4.2/modules/vtk-modules/Rendering/WebGPU/README.html
  - https://docs.vtk.org/en/latest/release_details/9.4/add-graphics-backend-preference-for-webgpu-rendering.html
