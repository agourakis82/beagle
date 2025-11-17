import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-dialog";

interface Props {
  onUpload: () => void;
}

export default function VoiceUpload({ onUpload }: Props) {
  const [uploading, setUploading] = useState(false);
  const [dragActive, setDragActive] = useState(false);

  const handleFileSelect = async (filePath: string) => {
    try {
      setUploading(true);
      await invoke("upload_voice_note", { filePath });
      onUpload();
    } catch (error) {
      console.error("Failed to upload voice note:", error);
      alert("Failed to upload voice note");
    } finally {
      setUploading(false);
    }
  };

  const handleClick = async () => {
    const selected = await open({
      multiple: false,
      filters: [
        {
          name: "Audio",
          extensions: ["wav", "mp3", "m4a", "ogg"],
        },
      ],
    });

    if (selected && typeof selected === "string") {
      handleFileSelect(selected);
    }
  };

  const handleDrag = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.type === "dragenter" || e.type === "dragover") {
      setDragActive(true);
    } else if (e.type === "dragleave") {
      setDragActive(false);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setDragActive(false);

    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      const file = e.dataTransfer.files[0];
      // Tauri will handle file path differently, so we use dialog for now
      handleClick();
    }
  };

  return (
    <div className="voice-upload mb-6">
      <h2 className="text-lg font-semibold mb-3">Capture Insight</h2>
      <div
        className={`border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-colors ${
          dragActive
            ? "border-primary-500 bg-primary-50"
            : "border-gray-300 hover:border-primary-400"
        } ${uploading ? "opacity-50" : ""}`}
        onDragEnter={handleDrag}
        onDragLeave={handleDrag}
        onDragOver={handleDrag}
        onDrop={handleDrop}
        onClick={handleClick}
      >
        {uploading ? (
          <p className="text-gray-600">Uploading...</p>
        ) : (
          <>
            <svg
              className="mx-auto h-12 w-12 text-gray-400"
              stroke="currentColor"
              fill="none"
              viewBox="0 0 48 48"
            >
              <path
                d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
                strokeWidth={2}
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            <p className="mt-2 text-sm text-gray-600">
              Click to upload or drag and drop
            </p>
            <p className="text-xs text-gray-500 mt-1">Voice note (WAV, MP3, M4A, OGG)</p>
          </>
        )}
      </div>
    </div>
  );
}

