import React from 'react';
import { Button, Flex, Text } from '@radix-ui/themes';
import { FolderOpen, Sparkles, Code, MessageSquare } from 'lucide-react';
import { useStore, View } from '../store';

const NAV_ITEMS: { view: View; icon: React.ReactNode; label: string }[] = [
  { view: 'projects', icon: <FolderOpen size={18} />, label: 'Projects' },
  { view: 'canvas', icon: <Sparkles size={18} />, label: 'Canvas' },
  { view: 'serendipity', icon: <Sparkles size={18} />, label: 'Serendipity' },
  { view: 'editor', icon: <Code size={18} />, label: 'Editor' },
  { view: 'chat', icon: <MessageSquare size={18} />, label: 'Chat' },
];

export const Sidebar: React.FC = () => {
  const { currentView, setView } = useStore();

  return (
    <Flex direction="column" gap="2" className="sidebar">
      {NAV_ITEMS.map(({ view, icon, label }) => (
        <Button
          key={view}
          variant={currentView === view ? 'solid' : 'ghost'}
          color={currentView === view ? 'blue' : 'gray'}
          onClick={() => setView(view)}
        >
          <Flex align="center" gap="2">
            {icon}
            <Text size="2">{label}</Text>
          </Flex>
        </Button>
      ))}
    </Flex>
  );
};
