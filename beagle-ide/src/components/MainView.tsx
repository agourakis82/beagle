import React from 'react';
import { View, useStore } from '../store';
import { ProjectsView } from './ProjectsView';
import { CanvasView } from './CanvasView';
import { EditorView } from './EditorView';
import { ChatView } from './ChatView';
import { SerendipityPanel } from './Darwin/SerendipityPanel';

interface MainViewProps {
  view: View;
}

export const MainView: React.FC<MainViewProps> = ({ view }) => {
  const { currentProject } = useStore();
  switch (view) {
    case 'projects':
      return <ProjectsView />;
    case 'canvas':
      return <CanvasView />;
    case 'editor':
      return <EditorView />;
    case 'chat':
      return <ChatView />;
    case 'serendipity':
      return <SerendipityPanel currentProject={currentProject ?? ''} />;
    default:
      return <div style={{ padding: '32px' }}>Unknown view: {view}</div>;
  }
};
