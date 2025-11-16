#!/usr/bin/env python3
"""
BEAGLE Interactive Chat
Chat with context from your papers and research
"""

from beagle_client import BeagleClient
import psycopg2
from datetime import datetime
from pathlib import Path


class BeagleChat:
    """Interactive chat with research context"""

    def __init__(self):
        self.client = BeagleClient()
        self.conversation_history = []
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.beagle_root = Path("/home/maria/beagle")
        self.kb_root = self.beagle_root / "data" / "knowledge"

    def get_kb_snippet(self, topic: str = "clima_espacial_saude_mental", max_lines: int = 80) -> str:
        """Load a snippet from the knowledge base markdown file."""
        # Try reviews first, then protocols, then hypotheses
        for subdir in ["reviews", "protocols", "hypotheses"]:
            kb_file = self.kb_root / subdir / f"{topic}.md"
            if kb_file.exists():
                lines = kb_file.read_text(encoding="utf-8").splitlines()
                snippet = "\n".join(lines[:max_lines])
                return snippet
        return "Knowledge base entry not found."
    
    def search_kb(self, query: str) -> str:
        """Search knowledge base files for relevant content"""
        results = []
        query_lower = query.lower()
        for subdir in ["reviews", "protocols", "hypotheses"]:
            kb_dir = self.kb_root / subdir
            if not kb_dir.exists():
                continue
            for kb_file in kb_dir.glob("*.md"):
                content = kb_file.read_text(encoding="utf-8").lower()
                if query_lower in content:
                    title = kb_file.stem.replace("_", " ").title()
                    snippet = "\n".join(kb_file.read_text(encoding="utf-8").splitlines()[:50])
                    results.append(f"**{title}** ({subdir}):\n{snippet}\n")
        return "\n---\n".join(results) if results else "No relevant KB entries found."

    def get_papers_context(self, query: str | None = None, limit: int = 3) -> str:
        """Get relevant papers as context from PostgreSQL"""
        conn = psycopg2.connect(self.client.postgres_dsn)
        cur = conn.cursor()
        if query:
            cur.execute(
                """
                SELECT title, abstract, authors
                FROM papers
                WHERE abstract ILIKE %s OR title ILIKE %s
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (f"%{query}%", f"%{query}%", limit),
            )
        else:
            cur.execute(
                """
                SELECT title, abstract, authors
                FROM papers
                ORDER BY created_at DESC
                LIMIT %s
                """,
                (limit,),
            )
        papers = cur.fetchall()
        conn.close()
        context_lines: list[str] = []
        for title, abstract, authors in papers:
            author_str = ", ".join(authors[:2]) if authors else "Unknown"
            context_lines.append(f"• {title} ({author_str})")
            if abstract:
                context_lines.append(f"  {abstract[:200]}...")
        return "\n".join(context_lines) if context_lines else "No papers found in database."

    def chat(self, user_message: str, use_context: bool = True) -> str:
        """Send message and get response"""
        # Decide if we should pull paper context and/or KB context
        context_prompt = ""
        if use_context:
            text = user_message.lower()
            keywords = [
                "paper",
                "research",
                "study",
                "biomaterial",
                "scaffold",
                "pharmacokinetic",
                "psychiatric",
                "neuroscience",
            ]
            clima_keywords = ["clima espacial", "climaespacial", "geomagn", "geomagnético", "geomagnetico", "geomagnetismo", "space weather", "solar activity", "kp index", "ap index"]
            if any(kw in text for kw in keywords):
                papers_context = self.get_papers_context(user_message)
                context_prompt += f"\nRelevant papers from your research:\n{papers_context}\n\n"
            if any(kw in text for kw in clima_keywords):
                kb_snippet = self.get_kb_snippet("clima_espacial_saude_mental")
                context_prompt += (
                    "\nKnowledge base entry: Clima espacial e saúde mental\n"
                    f"{kb_snippet}\n\n"
                )
            # Generic KB search for other topics
            elif any(kw in text for kw in ["protocolo", "protocol", "hipótese", "hypothesis", "revisão", "review"]):
                kb_results = self.search_kb(user_message)
                if kb_results and "not found" not in kb_results:
                    context_prompt += f"\nRelevant knowledge base entries:\n{kb_results}\n\n"

        history = ""
        for msg in self.conversation_history[-4:]:
            history += f"{msg['role']}: {msg['content']}\n"

        full_prompt = f"""You are BEAGLE, an advanced AI research assistant for Dr. Demetrios Chiuratto,
an interdisciplinary researcher in biomaterials, pharmacokinetics, computational psychiatry, neuroscience,
medical law, chemical engineering, and philosophy of mind.

Your tasks:
- Provide rigorous, technical, and well-structured answers.
- When appropriate, integrate biomaterials, PBPK, psychiatry, neuroscience, and legal/ethical dimensions.
- Maintain high-level academic tone (Q1-level journals).

{context_prompt}
{history}
User: {user_message}
Assistant:"""

        response = self.client.generate_text(
            prompt=full_prompt,
            max_tokens=768,
            temperature=0.7,
        )
        reply = response.strip()
        self.conversation_history.append({"role": "User", "content": user_message})
        self.conversation_history.append({"role": "Assistant", "content": reply})
        return reply


def main():
    chat = BeagleChat()
    print("🧠 BEAGLE Interactive Chat - Mistral-7B backend")
    print("Digite sua pergunta (ou 'exit', 'quit', 'sair' para encerrar).")
    print("Comando especial: '/kb clima' para exibir a revisão de clima espacial e saúde mental.")
    while True:
        try:
            user_message = input("\nVocê: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nEncerrando chat.")
            break
        if user_message.lower() in {"exit", "quit", "sair"}:
            print("Encerrando chat.")
            break
        if user_message.lower().startswith("/kb"):
            snippet = chat.get_kb_snippet()
            print("\n[KB: Clima espacial e saúde mental]\n")
            print(snippet)
            continue
        if not user_message:
            continue
        reply = chat.chat(user_message=user_message, use_context=True)
        print("\nBEAGLE:\n" + reply)


if __name__ == "__main__":
    main()


