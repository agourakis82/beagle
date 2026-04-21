/**
 * useTitle — reactive document title management.
 *
 * Updates document.title whenever the title signal changes.
 * Cleans up on component unmount (restores previous title).
 */
import { createEffect, onCleanup } from "solid-js";

const BASE = "Cockpit";

export function useTitle(title) {
  createEffect(() => {
    const value = typeof title === "function" ? title() : title;
    const previous = document.title;
    document.title = value ? `${value} · ${BASE}` : BASE;
    onCleanup(() => {
      document.title = previous;
    });
  });
}

/**
 * Set a static title for a page.
 */
export function setTitle(title) {
  document.title = title ? `${title} · ${BASE}` : BASE;
}
