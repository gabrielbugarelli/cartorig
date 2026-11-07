#!/usr/bin/env python3
"""Reviewed Natural Earth publisher-outage exceptions for acquisition only.

A missing official ZIP can be bypassed during acquisition, never during
complete pack certification. The original 52-source inventory remains intact.
Do not import this module from the installed OpenFX runtime.
"""
from __future__ import annotations

import json
from pathlib import Path
from urllib.parse import urlsplit

from tools.natural_earth import source_lock

EXCEPTIONS_FILE = "data/natural-earth/source_exceptions_v2026-11-07.json"
FORMAT = "cartorig-ne-publisher-exceptions-v1"


class SourceExceptionError(ValueError):
    pass


def validate(inventory: dict, discovery: dict, exceptions: dict) -> dict[str, dict]:
    """Return publisher-unavailable records pinned to exact reviewed source IDs.

    Invalid or stale exceptions fail closed; this is not a new definition of
    source completeness, a certificate, or evidence that files were downloaded.
    """
    try:
        source_lock.verify_discovery(discovery, inventory)
    except (source_lock.SourceLockError, KeyError, TypeError) as exc:
        raise SourceExceptionError("reviewed publisher discovery identity is invalid") from exc
    if (exceptions.get("schema_version") != 1 or
            exceptions.get("format") != FORMAT or
            exceptions.get("discovery_sha256") != discovery.get("source_rows_sha256")):
        raise SourceExceptionError("exception list does not match frozen 52-source discovery")
    rows = exceptions.get("exceptions")
    if not isinstance(rows, list) or len(rows) != 1:
        raise SourceExceptionError("exactly one explicitly reviewed upstream exception is supported")
    discovered = {r["resource_id"]: r for r in inventory["resources"]
                  if r.get("theme") == "raster"}
    result = {}
    for row in rows:
        ident = row.get("resource_id")
        if not isinstance(ident, str) or ident in result or ident not in discovered:
            raise SourceExceptionError("unknown or duplicate publisher exception source")
        actual = discovered[ident]
        if any(row.get(field) != actual.get(field) for field in
               ("resource_id", "scale", "url", "source_page")):
            raise SourceExceptionError("publisher exception no longer matches original source")
        issue = urlsplit(str(row.get("issue", "")))
        if (issue.scheme != "https" or issue.hostname != "github.com" or
                issue.path != "/gabrielbugarelli/cartorig/issues/4" or
                row.get("observed_status") != "PUBLISHER_HTTP_404" or
                row.get("observed_utc") != "2026-11-07"):
            raise SourceExceptionError("publisher exception lacks verified status and audit evidence")
        result[ident] = row
    return result


def read_verified(project_root: Path, inventory: dict) -> dict[str, dict]:
    """Load the checked-in manifest with the checked-in discovery fingerprint."""
    root = project_root.resolve()
    discovery = json.loads((root / "data/natural-earth/raster_discovery_v2026-11-07.lock.json")
                           .read_text(encoding="utf-8"))
    exceptions = json.loads((root / EXCEPTIONS_FILE).read_text(encoding="utf-8"))
    return validate(inventory, discovery, exceptions)
