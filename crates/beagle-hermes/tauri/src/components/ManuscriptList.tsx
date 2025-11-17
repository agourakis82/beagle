import { invoke } from "@tauri-apps/api/core";

interface Manuscript {
  id: string;
  title: string;
  state: string;
  completion: number;
  last_updated: string;
}

interface Props {
  manuscripts: Manuscript[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  loading: boolean;
}

export default function ManuscriptList({ manuscripts, selectedId, onSelect, loading }: Props) {
  const getStateColor = (state: string) => {
    switch (state.toLowerCase()) {
      case "drafting":
        return "bg-blue-100 text-blue-800";
      case "review":
        return "bg-yellow-100 text-yellow-800";
      case "ready":
        return "bg-green-100 text-green-800";
      case "published":
        return "bg-gray-100 text-gray-800";
      default:
        return "bg-gray-100 text-gray-800";
    }
  };

  if (loading) {
    return (
      <div className="p-4">
        <p className="text-gray-500">Loading manuscripts...</p>
      </div>
    );
  }

  if (manuscripts.length === 0) {
    return (
      <div className="p-4">
        <p className="text-gray-500">No manuscripts yet. Capture some insights to get started!</p>
      </div>
    );
  }

  return (
    <div className="manuscript-list">
      <h2 className="text-lg font-semibold mb-4">Manuscripts</h2>
      <div className="space-y-2">
        {manuscripts.map((manuscript) => (
          <div
            key={manuscript.id}
            onClick={() => onSelect(manuscript.id)}
            className={`p-4 border rounded-lg cursor-pointer transition-colors ${
              selectedId === manuscript.id
                ? "border-primary-500 bg-primary-50"
                : "border-gray-200 hover:border-primary-300"
            }`}
          >
            <div className="flex justify-between items-start mb-2">
              <h3 className="font-medium text-sm">{manuscript.title}</h3>
              <span className={`px-2 py-1 rounded text-xs ${getStateColor(manuscript.state)}`}>
                {manuscript.state}
              </span>
            </div>
            <div className="flex items-center gap-2">
              <div className="flex-1 bg-gray-200 rounded-full h-2">
                <div
                  className="bg-primary-500 h-2 rounded-full transition-all"
                  style={{ width: `${manuscript.completion * 100}%` }}
                />
              </div>
              <span className="text-xs text-gray-600">{Math.round(manuscript.completion * 100)}%</span>
            </div>
            <p className="text-xs text-gray-500 mt-2">
              Updated: {new Date(manuscript.last_updated).toLocaleDateString()}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

