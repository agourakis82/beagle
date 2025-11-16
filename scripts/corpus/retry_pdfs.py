#!/usr/bin/env python3
"""
BEAGLE - PDF Retry Worker
Lê failed_downloads.log e tenta rebaixar PDFs OA com retries e backoff.
Pode ser agendado via cron/systemd ou executado sob demanda.
"""

import os
import sys
import time
import requests
from pathlib import Path
from typing import Optional

OUTPUT_DIR = Path("/home/maria/beagle/data/corpus")
FAILED_LOG = OUTPUT_DIR / "raw" / "failed_downloads.log"
PDF_DIR = OUTPUT_DIR / "papers"
PDF_DIR.mkdir(parents=True, exist_ok=True)

UA = {"User-Agent": "BEAGLE-CorpusCollector/1.0 (+https://beagle.local)"}


def http_get_with_retries(url: str, max_retries: int = 5, base_backoff: float = 1.0) -> Optional[requests.Response]:
    backoff = base_backoff
    for attempt in range(max_retries):
        try:
            r = requests.get(url, stream=True, timeout=30, headers=UA)
            if r.status_code in (429, 503, 502, 504):
                time.sleep(backoff)
                backoff *= 2.0
                continue
            r.raise_for_status()
            return r
        except Exception:
            if attempt == max_retries - 1:
                return None
            time.sleep(backoff)
            backoff *= 2.0
    return None


def process_failed():
    if not FAILED_LOG.exists():
        print("No failed_downloads.log found. Nothing to retry.")
        return
    lines = FAILED_LOG.read_text(encoding="utf-8").splitlines()
    if not lines:
        print("failed_downloads.log is empty. Nothing to retry.")
        return
    remaining = []
    successes = 0
    for line in lines:
        try:
            paper_id, pdf_url, reason = line.split("\t", 2)
        except ValueError:
            continue
        dest = PDF_DIR / f"{paper_id}.pdf"
        if dest.exists() and dest.stat().st_size > 0:
            continue
        resp = http_get_with_retries(pdf_url)
        if resp is None:
            remaining.append(line)
            continue
        with resp:
            with open(dest, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
        successes += 1
        time.sleep(0.2)
    # rewrite remaining failures
    if remaining:
        FAILED_LOG.write_text("\n".join(remaining) + "\n", encoding="utf-8")
    else:
        # clear file
        FAILED_LOG.write_text("", encoding="utf-8")
    print(f"Retry complete. Downloaded: {successes}. Remaining failures: {len(remaining)}.")


if __name__ == "__main__":
    process_failed()


