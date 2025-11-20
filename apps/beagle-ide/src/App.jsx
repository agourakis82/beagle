//! BEAGLE IDE - 4 Painéis Fixos: Knowledge Graph, Paper Canvas, Agent Console, Quantum View

import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import CodeMirror from '@uiw/react-codemirror';
import { rust } from '@codemirror/lang-rust';
import { julia } from '@codemirror/lang-julia';
import { oneDark } from '@codemirror/theme-one-dark';
import './App.css';

function App() {
  const [knowledgeGraph, setKnowledgeGraph] = useState(null);
  const [paperContent, setPaperContent] = useState('# BEAGLE Paper\n\n');
  const [agentLogs, setAgentLogs] = useState([]);
  const [quantumState, setQuantumState] = useState({ superposition: 0.5, entanglement: 0.3 });

  useEffect(() => {
    // Inicializa Knowledge Graph
    const initGraph = async () => {
      const nodes = await invoke('get_knowledge_graph_nodes');
      const edges = await invoke('get_knowledge_graph_edges');
      setKnowledgeGraph({ nodes, edges });
    };
    initGraph();

    // Inicia loop de logs do agente
    const interval = setInterval(async () => {
      const logs = await invoke('get_agent_logs');
      setAgentLogs(logs);
    }, 1000);

    return () => clearInterval(interval);
  }, []);

  const handleVoiceCommand = async (command) => {
    const response = await invoke('process_voice_command', { command });
    setPaperContent(prev => prev + `\n\n${response}`);
  };

  return (
    <div className="beagle-ide">
      <div className="panel knowledge-graph">
        <h2>Knowledge Graph</h2>
        <div id="graph-container" style={{ width: '100%', height: '400px' }}></div>
      </div>

      <div className="panel paper-canvas">
        <h2>Paper Canvas</h2>
        <CodeMirror
          value={paperContent}
          height="400px"
          extensions={[rust(), julia()]}
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

