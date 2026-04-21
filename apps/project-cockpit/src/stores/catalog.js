/**
 * Catalog Store — SolidJS reactive store for project catalog + posture.
 *
 * Fetches from /api/catalog/executive and /api/catalog/project-posture-policy.
 * Each data point carries its truth mode.
 */
import { createSignal, createResource } from "solid-js";

async function fetchJson(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error(`${url}: ${res.status}`);
  return res.json();
}

const [catalogData, { refetch: refetchCatalog }] = createResource(
  () => fetchJson("/api/catalog/executive").catch(() => null)
);

const [posturePolicy, { refetch: refetchPosture }] = createResource(
  () => fetchJson("/api/catalog/project-posture-policy").catch(() => null)
);

export function useCatalog() {
  return {
    catalog: catalogData,
    posturePolicy,
    refetchCatalog,
    refetchPosture,

    projects: () => {
      const data = catalogData();
      return data?.projects || data?.projectPosturePolicy?.assignments || [];
    },

    postureCounts: () => {
      const policy = posturePolicy() || catalogData()?.projectPosturePolicy;
      return policy?.counts || { totalProjects: 0, alwaysOn: 0, warm: 0, cold: 0 };
    },

    postureDefinitions: () => {
      const policy = posturePolicy() || catalogData()?.projectPosturePolicy;
      return policy?.postureDefinitions || [];
    },
  };
}
