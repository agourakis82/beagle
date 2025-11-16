#!/usr/bin/env python3
"""
BEAGLE Corpus Collector - Semantic Scholar (S2)
Coleta papers do autor via Semantic Scholar Graph API v1
"""

import os
import requests
import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional
import time
from urllib.parse import urlparse

# Config
AUTHOR_NAME_VARIANTS = [
    "Demetrios Chiuratto Agourakis",
    "Agourakis, D. C.",
    "Agourakis D",
    "Demetrios C. Agourakis",
]
AUTHOR_ORCID = "0009-0001-8671-8878"  # preferencial, conforme fornecido
SEMANTIC_SCHOLAR_API = "https://api.semanticscholar.org/graph/v1"
OUTPUT_DIR = Path("/home/maria/beagle/data/corpus")
RESULT_LIMIT = 100
REQUEST_TIMEOUT = 20


def get_s2_headers() -> Dict[str, str]:
    api_key = os.environ.get("S2_API_KEY", "").strip()
    headers: Dict[str, str] = {"Accept": "application/json"}
    if api_key:
        headers["x-api-key"] = api_key
    headers["User-Agent"] = "BEAGLE-CorpusCollector/1.0 (+https://beagle.local)"
    return headers


def pick_best_author(candidates: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not candidates:
        return None
    # Prefer highest paperCount, then citationCount if present, then HIndex if present
    def score(a: Dict[str, Any]) -> tuple:
        return (
            int(a.get("paperCount") or 0),
            int(a.get("citationCount") or 0),
            int(a.get("hIndex") or 0),
        )

    return sorted(candidates, key=score, reverse=True)[0]


def search_author_candidates(name: str) -> List[Dict[str, Any]]:
    url = f"{SEMANTIC_SCHOLAR_API}/author/search"
    params = {"query": name, "limit": 5, "fields": "name,authorId,paperCount,hIndex,citationCount,aliases,url,externalIds"}
    # simple retry/backoff
    for attempt in range(4):
        try:
            resp = requests.get(url, params=params, headers=get_s2_headers(), timeout=REQUEST_TIMEOUT)
            if resp.status_code == 429:
                wait = 2 ** attempt
                print(f"⏳ Rate limit (429) ao buscar '{name}'. Aguardando {wait}s...")
                time.sleep(wait)
                continue
            # if 400, try fallback without fields
            if resp.status_code == 400 and attempt == 0:
                params_fallback = {"query": name, "limit": 3}
                resp = requests.get(url, params=params_fallback, headers=get_s2_headers(), timeout=REQUEST_TIMEOUT)
            resp.raise_for_status()
            data = resp.json()
            return data.get("data", []) or []
        except Exception as e:
            if attempt == 3:
                print(f"❌ Author search error for '{name}': {e}")
            time.sleep(1.0 * (attempt + 1))
    return []


def resolve_author() -> Optional[Dict[str, Any]]:
    all_candidates: List[Dict[str, Any]] = []
    seen_ids = set()
    # 1) tentar ORCID diretamente
    if AUTHOR_ORCID:
        # tentar search com a string do ORCID e filtrar externalIds
        candidates = search_author_candidates(AUTHOR_ORCID)
        for c in candidates:
            ext = c.get("externalIds") or {}
            orcid = (ext.get("ORCID") or "").replace("https://orcid.org/", "")
            if orcid == AUTHOR_ORCID:
                print(f"✅ Autor (ORCID) identificado: {c.get('name')} (ID: {c.get('authorId')})")
                return c
        # caso não retorne, seguir para variantes de nome
    for variant in AUTHOR_NAME_VARIANTS:
        candidates = search_author_candidates(variant)
        # gentle pacing for rate limits
        time.sleep(0.5)
        for c in candidates:
            aid = c.get("authorId")
            if aid and aid not in seen_ids:
                seen_ids.add(aid)
                all_candidates.append(c)
    # se temos ORCID, preferir candidato compatível
    if AUTHOR_ORCID:
        for c in all_candidates:
            ext = c.get("externalIds") or {}
            orcid = (ext.get("ORCID") or "").replace("https://orcid.org/", "")
            if orcid == AUTHOR_ORCID:
                print(f"✅ Autor (ORCID via variantes) identificado: {c.get('name')} (ID: {c.get('authorId')})")
                return c
    best = pick_best_author(all_candidates)
    if best:
        print(f"✅ Autor selecionado: {best.get('name')} (ID: {best.get('authorId')}, papers: {best.get('paperCount')}, citations: {best.get('citationCount')})")
    else:
        print("❌ Nenhum autor encontrado para as variantes fornecidas.")
    return best


def fetch_author_papers(author_id: str, limit: int = RESULT_LIMIT) -> List[Dict[str, Any]]:
    url = f"{SEMANTIC_SCHOLAR_API}/author/{author_id}/papers"
    fields = "paperId,title,abstract,year,authors,venue,citationCount,publicationDate,externalIds,publicationTypes,openAccessPdf"
    page_limit = min(100, limit) if limit else 100
    offset = 0
    collected: List[Dict[str, Any]] = []
    try:
        while True:
            params = {
                "fields": fields,
                "limit": page_limit,
                "offset": offset,
                "sort": "year:desc",
            }
            resp = requests.get(url, params=params, headers=get_s2_headers(), timeout=REQUEST_TIMEOUT)
            if resp.status_code == 429:
                print("⏳ Rate limit ao buscar papers. Aguardando 2s...")
                time.sleep(2)
                continue
            resp.raise_for_status()
            data = resp.json()
            page = data.get("data", []) or []
            if not page:
                break
            collected.extend(page)
            if limit and len(collected) >= limit:
                collected = collected[:limit]
                break
            if len(page) < page_limit:
                break
            offset += page_limit
            time.sleep(0.3)
        print(f"📥 Recuperados {len(collected)} registros de papers (paginação).")
        return collected
    except Exception as e:
        print(f"❌ Erro ao buscar papers para autor {author_id}: {e}")
        return []


def download_open_access_pdfs(papers: List[Dict[str, Any]]):
    target_dir = OUTPUT_DIR / "papers"
    target_dir.mkdir(parents=True, exist_ok=True)
    downloaded = 0
    failed_log = OUTPUT_DIR / "raw" / "failed_downloads.log"
    failed_log.parent.mkdir(parents=True, exist_ok=True)

    def log_fail(paper_id: str, pdf_url: str, reason: str):
        with open(failed_log, "a", encoding="utf-8") as f:
            f.write(f"{paper_id}\t{pdf_url}\t{reason}\n")

    def http_get_with_retries(url: str, max_retries: int = 4) -> Optional[requests.Response]:
        backoff = 1.0
        for attempt in range(max_retries):
            try:
                r = requests.get(
                    url,
                    stream=True,
                    timeout=30,
                    headers={"User-Agent": "BEAGLE-CorpusCollector/1.0 (+https://beagle.local)"},
                )
                if r.status_code in (429, 503, 502, 504):
                    time.sleep(backoff)
                    backoff *= 2
                    continue
                r.raise_for_status()
                return r
            except Exception as e:
                if attempt == max_retries - 1:
                    return None
                time.sleep(backoff)
                backoff *= 2
        return None

    for p in papers:
        pdf_info = p.get("openAccessPdf") or {}
        pdf_url = pdf_info.get("url")
        paper_id = p.get("paperId")
        if not pdf_url or not paper_id:
            continue
        dest = target_dir / f"{paper_id}.pdf"
        if dest.exists() and dest.stat().st_size > 0:
            continue
        try:
            r = http_get_with_retries(pdf_url, max_retries=4)
            if r is None:
                log_fail(paper_id, pdf_url, "max_retries_exceeded")
                continue
            with r:
                with open(dest, "wb") as f:
                    for chunk in r.iter_content(chunk_size=8192):
                        if chunk:
                            f.write(chunk)
            downloaded += 1
            time.sleep(0.2)
        except Exception as e:
            print(f"⚠️ Falha ao baixar PDF {paper_id}: {e}")
            log_fail(paper_id, pdf_url, str(e))
    print(f"📄 PDFs OA baixados: {downloaded}")


def save_corpus(papers: List[Dict[str, Any]]):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    # Full JSON
    json_path = OUTPUT_DIR / f"raw/corpus_{timestamp}.json"
    json_path.parent.mkdir(parents=True, exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(papers, f, indent=2, ensure_ascii=False)
    print(f"✅ Saved {len(papers)} papers to {json_path}")
    # Abstracts
    abstracts_path = OUTPUT_DIR / f"abstracts/abstracts_{timestamp}.txt"
    abstracts_path.parent.mkdir(parents=True, exist_ok=True)
    with open(abstracts_path, "w", encoding="utf-8") as f:
        for p in papers:
            title = p.get("title") or "Untitled"
            abstract = p.get("abstract")
            if abstract:
                f.write(f"### {title}\n")
                f.write(f"{abstract}\n\n")
    print(f"✅ Saved abstracts to {abstracts_path}")
    # Stats
    with_abstract = sum(1 for p in papers if p.get("abstract"))
    total_citations = sum(int(p.get("citationCount") or 0) for p in papers)
    years = [int(p.get("year")) for p in papers if p.get("year")]
    year_min = min(years) if years else None
    year_max = max(years) if years else None
    print("\n📊 Corpus Statistics:")
    print(f"  Total papers: {len(papers)}")
    print(f"  With abstracts: {with_abstract}")
    print(f"  Total citations: {total_citations}")
    if year_min is not None and year_max is not None:
        print(f"  Year range: {year_min} - {year_max}")
    return json_path, abstracts_path


def main():
    print("🔍 BEAGLE Corpus Collector - Starting...")
    print(f"🔑 S2 API Key present: {'YES' if os.environ.get('S2_API_KEY') else 'NO'}")
    author = resolve_author()
    if not author:
        print("❌ No author resolved. Abort.")
        return
    papers = fetch_author_papers(str(author.get("authorId")), limit=RESULT_LIMIT)
    if papers:
        json_path, abstracts_path = save_corpus(papers)
        # baixar PDFs OA
        download_open_access_pdfs(papers)
        print(f"\n✅ SUCCESS - Corpus collected!")
        print(f"📁 JSON: {json_path}")
        print(f"📁 Abstracts: {abstracts_path}")
    else:
        print("❌ No papers found for resolved author.")


if __name__ == "__main__":
    main()


