import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import ManuscriptList from "./components/ManuscriptList";
import DraftPreview from "./components/DraftPreview";
import VoiceUpload from "./components/VoiceUpload";
import "./styles/App.css";

interface Manuscript {
  id: string;
  title: string;
  state: string;
  completion: number;
  last_updated: string;
}

function App() {
  const [manuscripts, setManuscripts] = useState<Manuscript[]>([]);
  const [selectedManuscript, setSelectedManuscript] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadManuscripts();
  }, []);

  const loadManuscripts = async () => {
    try {
      setLoading(true);
      const data = await invoke<Manuscript[]>("list_manuscripts");
      setManuscripts(data);
    } catch (error) {
      console.error("Failed to load manuscripts:", error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app-container">
      <header className="app-header">
        <h1 className="text-2xl font-bold text-primary-700">HERMES BPSE</h1>
        <p className="text-sm text-gray-600">Background Paper Synthesis Engine</p>
      </header>

      <div className="app-content">
        <aside className="sidebar">
          <VoiceUpload onUpload={loadManuscripts} />
          <ManuscriptList
            manuscripts={manuscripts}
            selectedId={selectedManuscript}
            onSelect={setSelectedManuscript}
            loading={loading}
          />
        </aside>

        <main className="main-content">
          {selectedManuscript ? (
            <DraftPreview paperId={selectedManuscript} />
          ) : (
            <div className="empty-state">
              <p className="text-gray-500">Select a manuscript to view details</p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}

export default App;

