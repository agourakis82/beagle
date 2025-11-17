import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

interface SectionStatus {
  section_type: string;
  completion: number;
  word_count: number;
  has_new_draft: boolean;
}

interface ManuscriptStatus {
  paper_id: string;
  title: string;
  sections: SectionStatus[];
  overall_completion: number;
  last_updated: string;
}

interface Props {
  paperId: string;
}

export default function DraftPreview({ paperId }: Props) {
  const [status, setStatus] = useState<ManuscriptStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedSection, setSelectedSection] = useState<string | null>(null);

  useEffect(() => {
    loadManuscriptStatus();
  }, [paperId]);

  const loadManuscriptStatus = async () => {
    try {
      setLoading(true);
      const data = await invoke<ManuscriptStatus>("get_manuscript_status", { paperId });
      setStatus(data);
      if (data.sections.length > 0) {
        setSelectedSection(data.sections[0].section_type);
      }
    } catch (error) {
      console.error("Failed to load manuscript status:", error);
    } finally {
      setLoading(false);
    }
  };

  const triggerSynthesis = async () => {
    try {
      await invoke("trigger_synthesis", { paperId });
      loadManuscriptStatus();
    } catch (error) {
      console.error("Failed to trigger synthesis:", error);
    }
  };

  if (loading) {
    return (
      <div className="p-8">
        <p className="text-gray-500">Loading manuscript details...</p>
      </div>
    );
  }

  if (!status) {
    return (
      <div className="p-8">
        <p className="text-red-500">Failed to load manuscript</p>
      </div>
    );
  }

  return (
    <div className="draft-preview">
      <div className="preview-header">
        <div>
          <h2 className="text-xl font-bold">{status.title}</h2>
          <p className="text-sm text-gray-600">Paper ID: {status.paper_id}</p>
        </div>
        <button
          onClick={triggerSynthesis}
          className="px-4 py-2 bg-primary-600 text-white rounded hover:bg-primary-700"
        >
          Trigger Synthesis
        </button>
      </div>

      <div className="completion-bar mb-6">
        <div className="flex justify-between mb-2">
          <span className="text-sm font-medium">Overall Completion</span>
          <span className="text-sm text-gray-600">{Math.round(status.overall_completion * 100)}%</span>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-3">
          <div
            className="bg-primary-500 h-3 rounded-full transition-all"
            style={{ width: `${status.overall_completion * 100}%` }}
          />
        </div>
      </div>

      <div className="sections-grid">
        <div className="sections-list">
          <h3 className="font-semibold mb-3">Sections</h3>
          {status.sections.map((section) => (
            <div
              key={section.section_type}
              onClick={() => setSelectedSection(section.section_type)}
              className={`p-3 border rounded mb-2 cursor-pointer ${
                selectedSection === section.section_type
                  ? "border-primary-500 bg-primary-50"
                  : "border-gray-200"
              }`}
            >
              <div className="flex justify-between items-center">
                <span className="font-medium">{section.section_type}</span>
                {section.has_new_draft && (
                  <span className="px-2 py-1 bg-green-100 text-green-800 text-xs rounded">New</span>
                )}
              </div>
              <div className="mt-2 flex items-center gap-2">
                <div className="flex-1 bg-gray-200 rounded-full h-1.5">
                  <div
                    className="bg-primary-500 h-1.5 rounded-full"
                    style={{ width: `${section.completion * 100}%` }}
                  />
                </div>
                <span className="text-xs text-gray-600">{section.word_count} words</span>
              </div>
            </div>
          ))}
        </div>

        <div className="section-preview">
          {selectedSection && (
            <div>
              <h3 className="font-semibold mb-3">{selectedSection} Preview</h3>
              <div className="p-4 bg-gray-50 rounded border">
                <p className="text-gray-600">
                  Draft content for {selectedSection} will appear here once synthesis is triggered.
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

