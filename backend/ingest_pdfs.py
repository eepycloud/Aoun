"""
ingest_pdfs.py - PDF ingestion pipeline for Aoun RAG.

Scans ./knowledge_pdfs/ for *.pdf files, extracts text, splits into
semantic chunks, embeds each chunk, and inserts into the ChromaDB
'knowledge' collection with rich source metadata.

Idempotent: re-running skips already-ingested files. Delete the
chroma_store/ folder to force full re-ingestion.

Run once after adding new PDFs:
    python ingest_pdfs.py
"""

import os
import re
import sys
from pathlib import Path

from pypdf import PdfReader

# Make sure we can import aoun_rag from the same folder
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import aoun_rag

PDF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "knowledge_pdfs")

# Chunking parameters
CHUNK_SIZE_CHARS = 900     # ~200 tokens - small enough for precise retrieval
CHUNK_OVERLAP_CHARS = 150  # keep context across chunk boundaries


def extract_text_by_page(pdf_path: str) -> list:
    """Extract text from each page. Returns list of (page_num, text)."""
    reader = PdfReader(pdf_path)
    pages = []
    for i, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        # Collapse whitespace but keep paragraph breaks
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        pages.append((i, text.strip()))
    return pages


def chunk_text(text: str,
               chunk_size: int = CHUNK_SIZE_CHARS,
               overlap: int = CHUNK_OVERLAP_CHARS) -> list:
    """Split text into overlapping chunks, preferring paragraph boundaries."""
    if not text:
        return []

    # First try: split on blank lines (paragraphs)
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks = []
    buf = ""

    for p in paragraphs:
        # If a single paragraph exceeds chunk size, hard-split it
        if len(p) > chunk_size:
            # Flush buffer first
            if buf:
                chunks.append(buf.strip())
                buf = ""
            # Hard-split long paragraph on sentence-like boundaries
            sentences = re.split(r"(?<=[.!?])\s+", p)
            sub_buf = ""
            for s in sentences:
                if len(sub_buf) + len(s) + 1 > chunk_size and sub_buf:
                    chunks.append(sub_buf.strip())
                    sub_buf = s
                else:
                    sub_buf = (sub_buf + " " + s).strip() if sub_buf else s
            if sub_buf:
                chunks.append(sub_buf.strip())
            continue

        # Normal case: try to add paragraph to buffer
        if len(buf) + len(p) + 2 > chunk_size and buf:
            chunks.append(buf.strip())
            # Start next chunk with overlap from end of previous
            tail = buf[-overlap:] if overlap > 0 else ""
            buf = (tail + "\n\n" + p) if tail else p
        else:
            buf = (buf + "\n\n" + p).strip() if buf else p

    if buf.strip():
        chunks.append(buf.strip())

    # Filter out tiny chunks (likely just headers)
    return [c for c in chunks if len(c) >= 100]


def _already_ingested(filename: str) -> bool:
    """Check if any chunks from this filename exist in ChromaDB."""
    try:
        col = aoun_rag._knowledge_col
        if col is None:
            return False
        # Query metadata for this source file
        result = col.get(where={"source_file": filename}, limit=1)
        return len(result.get("ids", [])) > 0
    except Exception:
        return False


def ingest_pdf(pdf_path: str) -> int:
    """Ingest a single PDF. Returns number of chunks added."""
    filename = os.path.basename(pdf_path)

    if _already_ingested(filename):
        print(f"  [SKIP] {filename} - already ingested")
        return 0

    print(f"  [READ] {filename}")
    pages = extract_text_by_page(pdf_path)
    if not pages:
        print(f"  [WARN] {filename} - no extractable text")
        return 0

    # Chunk each page separately so we can track page numbers
    chunk_payload = []
    for page_num, page_text in pages:
        page_chunks = chunk_text(page_text)
        for ci, chunk in enumerate(page_chunks):
            chunk_id = f"pdf_{filename}_p{page_num}_c{ci}".replace(" ", "_")
            chunk_payload.append({
                "id": chunk_id,
                "text": chunk,
                "metadata": {
                    "source_type": "pdf",
                    "source_file": filename,
                    "source_title": os.path.splitext(filename)[0]
                                      .replace("_", " ").title(),
                    "page": page_num,
                    "chunk_in_page": ci,
                },
            })

    if not chunk_payload:
        print(f"  [WARN] {filename} - no chunks produced")
        return 0

    # Embed all chunks at once
    texts = [c["text"] for c in chunk_payload]
    print(f"  [EMBED] {filename} - embedding {len(texts)} chunks...")
    embeddings = aoun_rag._embed(texts)

    # Insert into ChromaDB
    aoun_rag._knowledge_col.add(
        ids=[c["id"] for c in chunk_payload],
        documents=texts,
        embeddings=embeddings,
        metadatas=[c["metadata"] for c in chunk_payload],
    )
    print(f"  [OK] {filename} - {len(chunk_payload)} chunks added")
    return len(chunk_payload)


def main():
    print("=" * 60)
    print("Aoun PDF Ingestion Pipeline")
    print("=" * 60)

    # Initialize RAG (loads embedder, opens ChromaDB)
    aoun_rag.init()

    if not os.path.isdir(PDF_DIR):
        print(f"\nERROR: PDF directory not found: {PDF_DIR}")
        print(f"Create it and drop PDFs inside, then re-run this script.")
        return 1

    pdf_files = sorted([
        f for f in os.listdir(PDF_DIR)
        if f.lower().endswith(".pdf")
    ])

    if not pdf_files:
        print(f"\nNo PDF files found in {PDF_DIR}")
        print("Drop some PDFs in that folder and re-run.")
        return 0

    print(f"\nFound {len(pdf_files)} PDF file(s):\n")

    total_chunks = 0
    for pdf_name in pdf_files:
        pdf_path = os.path.join(PDF_DIR, pdf_name)
        try:
            added = ingest_pdf(pdf_path)
            total_chunks += added
        except Exception as e:
            print(f"  [ERROR] {pdf_name}: {type(e).__name__}: {e}")

    print("\n" + "=" * 60)
    print(f"Ingestion complete. Added {total_chunks} new chunk(s).")
    stats = aoun_rag.stats()
    print(f"Current knowledge collection: {stats['knowledge_entries']} total entries")
    print(f"Current conversation collection: {stats['conversation_turns']} turns")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    sys.exit(main())
