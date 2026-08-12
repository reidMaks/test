#!/usr/bin/env python3
"""MCP server: read-only access to Open WebUI knowledge bases (list + vector search)."""

import json
import os
import urllib.request

from mcp.server.fastmcp import FastMCP

OPENWEBUI_BASE_URL = os.environ.get("OPENWEBUI_BASE_URL", "https://openui.kms-lab.in.ua")


def _read_secret(env_value_name: str, env_file_name: str) -> str:
    file_path = os.environ.get(env_file_name)
    if file_path:
        with open(file_path) as f:
            return f.read().strip()
    value = os.environ.get(env_value_name)
    if not value:
        raise RuntimeError(f"Neither {env_file_name} nor {env_value_name} is set")
    return value


def _request(method: str, path: str, api_key: str, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(
        f"{OPENWEBUI_BASE_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


mcp = FastMCP("openwebui-knowledge")


@mcp.tool()
def list_knowledge_bases() -> str:
    """List all Open WebUI knowledge bases accessible to this API key: id, name,
    description and file count. Use the id with search_knowledge_base to query one."""
    api_key = _read_secret("OPENWEBUI_API_KEY", "OPENWEBUI_API_KEY_FILE")
    result = _request("GET", "/api/v1/knowledge/", api_key)
    items = result.get("items", [])

    if not items:
        return "No knowledge bases found."

    lines = []
    for kb in items:
        lines.append(
            f"- id={kb.get('id')} name={kb.get('name')!r} "
            f"files={kb.get('file_count')} description={kb.get('description')!r}"
        )
    return "\n".join(lines)


@mcp.tool()
def search_knowledge_base(kb_id: str, query: str, k: int = 20) -> str:
    """Vector search a single Open WebUI knowledge base. Pure vector search, no LLM/reranker
    involved (results may need more manual filtering than the chat RAG pipeline would give).

    Args:
        kb_id: Knowledge base id, from list_knowledge_bases().
        query: Search text.
        k: Number of chunks to return (default 20, max 50).
    """
    api_key = _read_secret("OPENWEBUI_API_KEY", "OPENWEBUI_API_KEY_FILE")
    k = max(1, min(k, 50))

    result = _request(
        "POST",
        "/api/v1/retrieval/query/collection",
        api_key,
        {"collection_names": [kb_id], "query": query, "k": k},
    )

    distances = result.get("distances", [[]])[0]
    documents = result.get("documents", [[]])[0]
    metadatas = result.get("metadatas", [[]])[0]

    if not documents:
        return "No results found."

    parts = []
    for distance, document, metadata in zip(distances, documents, metadatas):
        doc_id = metadata.get("name", "unknown")
        parts.append(f"--- {doc_id} (distance={distance:.4f}) ---\n{document}")

    return "\n\n".join(parts)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
