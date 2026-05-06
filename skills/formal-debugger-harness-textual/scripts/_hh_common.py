"""Shared helpers for the formal-debugger-harness record scripts.

Talks to hashharness ONLY through the MCP API (JSON-RPC over HTTP transport).
Does NOT import hashharness.storage — the storage layer is the server's
private implementation detail; scripts on the harness side stay strictly
on the API boundary.

Setup:
    Run hashharness as an HTTP MCP server in a separate terminal:

        HASHHARNESS_MCP_TRANSPORT=http \
        HASHHARNESS_HTTP_PORT=8765 \
        HASHHARNESS_DATA_DIR=$HOME/workspace/hashharness/data \
        python3 -m hashharness.mcp_server

    Or set HASHHARNESS_HTTP_URL to point at any reachable hashharness HTTP
    endpoint (default: http://127.0.0.1:8765/mcp).

    Claude Code's stdio MCP config can stay as-is; this HTTP server is for
    the wrapper scripts. To avoid races on the data dir, point both at the
    same data directory and stop one transport before running the other.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

DEFAULT_HTTP_URL = "http://127.0.0.1:8765/mcp"


def http_url() -> str:
    return os.environ.get("HASHHARNESS_HTTP_URL", DEFAULT_HTTP_URL)


def now_iso() -> str:
    """Current UTC time as ISO 8601 with millisecond precision and trailing Z."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


_request_id = 0


def _next_id() -> int:
    global _request_id
    _request_id += 1
    return _request_id


def mcp_call(tool: str, arguments: dict) -> dict:
    """Invoke a hashharness MCP tool via HTTP JSON-RPC.

    Raises RuntimeError on transport or protocol errors. Returns the parsed
    `result` field of the JSON-RPC response (the tool's payload).
    """
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": _next_id(),
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }).encode("utf-8")

    req = urllib.request.Request(
        http_url(),
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as e:
        raise RuntimeError(
            f"hashharness HTTP server unreachable at {http_url()} "
            f"(set HASHHARNESS_HTTP_URL or run "
            f"`HASHHARNESS_MCP_TRANSPORT=http python3 -m hashharness.mcp_server`): {e}"
        ) from e

    if "error" in payload:
        err = payload["error"]
        raise RuntimeError(f"MCP error {err.get('code')}: {err.get('message')}")

    result = payload.get("result", {})
    return result


def first_text_content(result: dict) -> str:
    """Extract the text content from an MCP tool result.

    MCP tool results have shape `{"content": [{"type": "text", "text": "..."}, ...]}`.
    Most hashharness tool responses encode the JSON payload as one text item.
    """
    content = result.get("content", [])
    for piece in content:
        if piece.get("type") == "text":
            return piece.get("text", "")
    return ""


def parse_tool_json(result: dict) -> dict:
    """Parse the JSON-encoded payload that hashharness returns inside the
    text content of a tool result. Returns an empty dict if no content."""
    text = first_text_content(result)
    if not text:
        return {}
    return json.loads(text)


def create_item(
    *,
    item_type: str,
    work_package_id: str,
    title: str,
    text: str,
    links: dict | None = None,
    attributes: dict | None = None,
    return_minimal: bool = True,
) -> str:
    """Create one hashharness item and return only its `text_sha256`.

    Used by the record_*.py wrappers. Defaults to `return: minimal` so the
    server response is just the new identifying hash, not the full echoed
    item — saves tokens when the script's stdout flows back into a Bash
    tool result.
    """
    args: dict = {
        "type": item_type,
        "work_package_id": work_package_id,
        "title": title,
        "text": text,
        "created_at": now_iso(),
    }
    if links:
        args["links"] = links
    if attributes:
        args["attributes"] = attributes
    if return_minimal:
        args["return"] = "minimal"

    result = mcp_call("create_item", args)
    item = parse_tool_json(result)
    sha = item.get("text_sha256")
    if not sha:
        raise RuntimeError(f"create_item returned no text_sha256: {item}")
    return sha
