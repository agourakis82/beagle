#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;

#[derive(Serialize)]
struct GraphNode {
    id: &'static str,
    label: &'static str,
}

#[derive(Serialize)]
struct GraphEdge {
    from: &'static str,
    to: &'static str,
}

#[derive(Serialize)]
struct AgentLog {
    timestamp: &'static str,
    level: &'static str,
    message: &'static str,
}

#[tauri::command]
fn get_knowledge_graph_nodes() -> Vec<GraphNode> {
    vec![
        GraphNode {
            id: "thought",
            label: "Thought Capture",
        },
        GraphNode {
            id: "memory",
            label: "Living Memory",
        },
        GraphNode {
            id: "serendipity",
            label: "Fertile Collision",
        },
        GraphNode {
            id: "review",
            label: "Adversarial Review",
        },
        GraphNode {
            id: "artifact",
            label: "Draft Artifact",
        },
    ]
}

#[tauri::command]
fn get_knowledge_graph_edges() -> Vec<GraphEdge> {
    vec![
        GraphEdge {
            from: "thought",
            to: "memory",
        },
        GraphEdge {
            from: "memory",
            to: "serendipity",
        },
        GraphEdge {
            from: "serendipity",
            to: "review",
        },
        GraphEdge {
            from: "review",
            to: "artifact",
        },
    ]
}

#[tauri::command]
fn get_agent_logs() -> Vec<AgentLog> {
    vec![
        AgentLog {
            timestamp: "tauri",
            level: "north",
            message: "North Star loaded: preserve the research mind",
        },
        AgentLog {
            timestamp: "tauri",
            level: "ok",
            message: "Rescue baseline ready; next action stays visible",
        },
    ]
}

#[tauri::command]
fn process_voice_command(command: String) -> String {
    format!("Preserved thought: {command}")
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_knowledge_graph_nodes,
            get_knowledge_graph_edges,
            get_agent_logs,
            process_voice_command,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run BEAGLE IDE");
}
