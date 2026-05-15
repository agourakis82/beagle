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

const workflowSteps = [
  'Thought captured',
  'Memory anchor created',
  'Fertile connection proposed',
  'Adversarial review drafted',
  'Draft artifact updated',
];

const buildWorkflowArtifact = (rawThought) => {
  const thought = rawThought.trim() || 'Follow the North Star without flattening the research voice.';
  const timestamp = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

  return {
    thought,
    timestamp,
    memory: `Memory anchor: ${thought}`,
    connection:
      'Fertile connection: relate this thought to living memory, scientific evidence, and the current draft.',
    review:
      'Adversarial review: what would make this claim false, overfit, generic, or unsupported?',
    draft: `Draft move: preserve the original thought, then turn it into one testable research paragraph.`,
  };
};

const formatArtifactForDraft = (artifact) => `## Preserved Thought (${artifact.timestamp})

${artifact.thought}

- ${artifact.memory}
- ${artifact.connection}
- ${artifact.review}
- ${artifact.draft}`;

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
  const [currentThought, setCurrentThought] = useState('');
  const [workflowArtifacts, setWorkflowArtifacts] = useState([]);
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
    const artifact = buildWorkflowArtifact(command);
    setWorkflowArtifacts(prev => [artifact, ...prev].slice(0, 5));
    setPaperContent(prev => `${prev}\n\n${response}\n\n${formatArtifactForDraft(artifact)}`);
    setCurrentThought('');
    setQuantumState(prev => ({
      superposition: Math.min(1, prev.superposition + 0.08),
      entanglement: Math.min(1, prev.entanglement + 0.12),
    }));
  };

  const visibleLogs = [
    ...agentLogs,
    ...workflowArtifacts.map((artifact) => ({
      timestamp: artifact.timestamp,
      level: 'flow',
      message: `Preserved thought moved to draft: ${artifact.thought}`,
    })),
  ];

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
        <div className="thought-capture">
          <label htmlFor="thought-input">Thought Capture</label>
          <textarea
            id="thought-input"
            value={currentThought}
            onChange={(event) => setCurrentThought(event.target.value)}
            placeholder="Drop the live thought here before it evaporates."
          />
          <button
            className="voice-command"
            onClick={() => handleVoiceCommand(currentThought || 'follow the North Star')}
          >
            Preserve Thought
          </button>
        </div>
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
          {visibleLogs.map((log, i) => (
            <div key={i} className="log-entry">
              <span className="timestamp">{log.timestamp}</span>
              <span className="level">{log.level}</span>
              <span className="message">{log.message}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="panel quantum-view">
        <h2>Living Workflow</h2>
        <div className="workflow-steps">
          {workflowSteps.map((step, index) => (
            <div
              key={step}
              className={`workflow-step ${workflowArtifacts.length > 0 ? 'active' : ''}`}
            >
              <span>{index + 1}</span>
              <p>{step}</p>
            </div>
          ))}
        </div>
        <div className="quantum-visualization research-state">
          <div className="superposition">
            <div className="bar" style={{ width: `${quantumState.superposition * 100}%` }}></div>
            <span>Possibility: {quantumState.superposition.toFixed(2)}</span>
          </div>
          <div className="entanglement">
            <div className="bar" style={{ width: `${quantumState.entanglement * 100}%` }}></div>
            <span>Connection: {quantumState.entanglement.toFixed(2)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
