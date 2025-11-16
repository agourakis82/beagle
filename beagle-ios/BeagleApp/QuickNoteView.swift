import SwiftUI

struct QuickNoteView: View {
    @EnvironmentObject private var store: NodeStore
    @State private var noteText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("Nota Rápida").font(.largeTitle).bold()
            TextEditor(text: $noteText)
                .frame(height: 200)
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .focused($isFocused)

            HStack {
                Button("Cancelar") {
                    noteText = ""
                    isFocused = false
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Salvar") {
                    Task {
                        await store.createNode(noteText, type: .text)
                        noteText = ""
                        isFocused = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Spacer()
        }
        .padding()
        .onAppear { isFocused = true }
    }
}


