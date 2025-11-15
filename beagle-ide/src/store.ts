import { create } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type { InvokeArgs } from '@tauri-apps/api/core';

export type View = 'projects' | 'canvas' | 'editor' | 'chat' | 'serendipity';

export interface FileNode {
  name: string;
  path: string;
  isDir: boolean;
  children?: FileNode[];
  expanded?: boolean;
}

interface FileEntry {
  name: string;
  path: string;
  is_dir: boolean;
  size: number;
}

interface BeagleStore {
  currentView: View;
  currentProject: string | null;
  files: FileNode[];
  loadingFiles: boolean;

  setView: (view: View) => void;
  setProject: (projectId: string) => Promise<void>;
  loadFiles: (projectPath: string) => Promise<void>;
  toggleNode: (path: string, expanded: boolean) => void;
  setFiles: (updater: (nodes: FileNode[]) => FileNode[]) => void;
}

import { invoke } from '@tauri-apps/api/core';

export const useStore = create<BeagleStore>()(
  immer((set, get) => ({
    currentView: 'projects',
    currentProject: null,
    files: [],
    loadingFiles: false,

    setView: (view) =>
      set((state) => {
        state.currentView = view;
      }),

    setProject: async (projectId: string) => {
      await invoke('set_current_project', { projectId });
      set((state) => {
        state.currentProject = projectId;
      });
    },

    loadFiles: async (projectPath: string) => {
      set((state) => {
        state.loadingFiles = true;
      });
      try {
        const entries = await invoke<FileEntry[]>('list_directory', { path: projectPath });
        const nodes: FileNode[] = entries
          .sort((a, b) => {
            if (a.is_dir === b.is_dir) {
              return a.name.localeCompare(b.name);
            }
            return a.is_dir ? -1 : 1;
          })
          .map((entry) => ({
            name: entry.name,
            path: entry.path,
            isDir: entry.is_dir,
            children: entry.is_dir ? [] : undefined,
            expanded: false,
          }));
        set((state) => {
          state.files = nodes;
        });
      } finally {
        set((state) => {
          state.loadingFiles = false;
        });
      }
    },

    toggleNode: (path, expanded) => {
      const updateNodes = (nodes: FileNode[]): FileNode[] =>
        nodes.map((node) => {
          if (node.path === path) {
            return { ...node, expanded };
          }
          if (node.children && node.children.length) {
            return { ...node, children: updateNodes(node.children) };
          }
          return node;
        });
      set((state) => {
        state.files = updateNodes(state.files);
      });
    },

    setFiles: (updater) =>
      set((state) => {
        state.files = updater(state.files);
      }),
  })),
);
