//! BEAGLE IDE - 4 Painéis Fixos: North Star Map, Paper Canvas, Agent Console, Quantum View

import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import CodeMirror from '@uiw/react-codemirror';
import { rust } from '@codemirror/lang-rust';
import { StreamLanguage } from '@codemirror/language';
import { julia } from '@codemirror/legacy-modes/mode/julia';
import { oneDark } from '@codemirror/theme-one-dark';
import './App.css';

const fallbackGraph = {
  nodes: [
    { id: 'thought', label: 'Thought Capture' },
    { id: 'memory', label: 'Living Memory' },
    { id: 'serendipity', label: 'Fertile Collision' },
    { id: 'review', label: 'Adversarial Review' },
    { id: 'artifact', label: 'Draft Artifact' },
  ],
  edges: [
    { from: 'thought', to: 'memory' },
    { from: 'memory', to: 'serendipity' },
    { from: 'serendipity', to: 'review' },
    { from: 'review', to: 'artifact' },
  ],
};

const fallbackLogs = [
  { timestamp: 'dev', level: 'north', message: 'North Star loaded: preserve the research mind' },
  { timestamp: 'dev', level: 'ok', message: 'Rescue baseline ready; next action stays visible' },
];

const northStarLoop = 'thought -> memory -> serendipity -> review -> artifact -> feedback';

const hasTauriRuntime = () =>
  typeof window !== 'undefined' && Boolean(window.__TAURI_INTERNALS__?.invoke);

const invokeBeagle = async (command, args) => {
  if (hasTauriRuntime()) {
    return invoke(command, args);
  }

  switch (command) {
    case 'get_knowledge_graph_nodes':
      return fallbackGraph.nodes;
    case 'get_knowledge_graph_edges':
      return fallbackGraph.edges;
    case 'get_agent_logs':
      return fallbackLogs;
    case 'process_voice_command':
      return `Preserved thought: ${args.command}`;
    default:
      return null;
  }
};

function App() {
  const [knowledgeGraph, setKnowledgeGraph] = useState(null);
  const [paperContent, setPaperContent] = useState(
    `# BEAGLE Living Draft\n\nNorth Star loop: ${northStarLoop}\n`
  );
  const [agentLogs, setAgentLogs] = useState([]);
  const [quantumState, setQuantumState] = useState({ superposition: 0.5, entanglement: 0.3 });

  useEffect(() => {
    // Inicializa Knowledge Graph
    const initGraph = async () => {
      const nodes = await invokeBeagle('get_knowledge_graph_nodes');
      const edges = await invokeBeagle('get_knowledge_graph_edges');
      setKnowledgeGraph({ nodes, edges });
    };
    initGraph();

    // Inicia loop de logs do agente
    const interval = setInterval(async () => {
      const logs = await invokeBeagle('get_agent_logs');
      setAgentLogs(logs);
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const handleVoiceCommand = async (command) => {
    const response = await invokeBeagle('process_voice_command', { command });
    setPaperContent(prev => prev + `\n\n${response}`);
  };

  return (
    <div className="beagle-ide">
      <div className="panel knowledge-graph">
        <h2>North Star Map</h2>
        <p className="north-star-line">Personal scientific exocortex, not a generic dashboard.</p>
        <div id="graph-container" className="graph-summary">
          <span>{knowledgeGraph?.nodes?.length ?? 0} nodes</span>
          <span>{knowledgeGraph?.edges?.length ?? 0} edges</span>
        </div>
        <ol className="north-star-loop">
          {(knowledgeGraph?.nodes ?? fallbackGraph.nodes).map((node) => (
            <li key={node.id}>{node.label}</li>
          ))}
        </ol>
      </div>

      <div className="panel paper-canvas">
        <h2>Paper Canvas</h2>
        <button className="voice-command" onClick={() => handleVoiceCommand('follow the North Star')}>
          Preserve Thought
        </button>
        <CodeMirror
          value={paperContent}
          height="400px"
          extensions={[rust(), StreamLanguage.define(julia)]}
          theme={oneDark}
          onChange={(value) => setPaperContent(value)}
        />
      </div>

      <div className="panel agent-console">
        <h2>Agent Console</h2>
        <div className="logs">
          {agentLogs.map((log, i) => (
            <div key={i} className="log-entry">
              <span className="timestamp">{log.timestamp}</span>
              <span className="level">{log.level}</span>
              <span className="message">{log.message}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="panel quantum-view">
        <h2>Quantum View</h2>
        <div className="quantum-visualization">
          <div className="superposition">
            <div className="bar" style={{ width: `${quantumState.superposition * 100}%` }}></div>
            <span>Superposition: {quantumState.superposition.toFixed(2)}</span>
          </div>
          <div className="entanglement">
            <div className="bar" style={{ width: `${quantumState.entanglement * 100}%` }}></div>
            <span>Entanglement: {quantumState.entanglement.toFixed(2)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
