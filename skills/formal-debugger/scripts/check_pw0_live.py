#!/usr/bin/env python3
"""
check_pw0_live.py — TC30 enforcement: structured hash integrity + filesystem provenance.

Investigation layout:
    investigations/<slug>/
      investigation-report.md      (chain anchor)
      evidence/        E<N>_<timestamp>.md
      hypothesis/      H<id>-<N>_<timestamp>.md
      model-changes/   M<N>_<timestamp>.md

Record dependencies are structured, not flat:

1. Hypothesis records form a single chain sorted by Timestamp.
   Each H has PrevHypHash = sha256(previous-H-file).
   First H (H0-1 at Step 0b) has PrevHypHash = sha256(investigation-report.md).

2. Evidence records attach to a hypothesis event.
   Each E has ParentHypEvent: H<id>-<N> and ParentHypHash = sha256(parent-H-file).
   Evidence does not chain to other evidence.

3. Model-change records both chain AND attach.
   Each M has PrevModelHash = sha256(previous-M-file) or sha256(report) for first,
   AND ParentHypEvent + ParentHypHash pointing to the triggering H event.

4. Hypothesis state-change events freeze their evidence.
   H records with Event: status-changed or accepted carry:
     Evidence: [E<N>, E<M>, ...]
     EvidenceHash = sha256(sorted_concat_of_individual_evidence_file_hashes))
   Any later edit to cited evidence invalidates this hash.

5. Filesystem provenance: in-field Timestamp must match file ctime within 60s.

Exit 0 = pass, 1 = fail, 2 = usage error.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

FS_TOLERANCE_SECONDS = 60

# --- Field regexes ---
TIMESTAMP_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Timestamp\*{0,2}\s*:\s*(\S+)", re.IGNORECASE)
PREVHYPHASH_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}PrevHypHash\*{0,2}\s*:\s*([0-9a-fA-F]{64})", re.IGNORECASE)
PREVMODELHASH_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}PrevModelHash\*{0,2}\s*:\s*([0-9a-fA-F]{64})", re.IGNORECASE)
PREVREPORTHASH_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}PrevReportHash\*{0,2}\s*:\s*([0-9a-fA-F]{64})", re.IGNORECASE)
PARENT_EVENT_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}ParentHypEvent\*{0,2}\s*:\s*(H\d+-\d+)", re.IGNORECASE)
PARENT_HASH_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}ParentHypHash\*{0,2}\s*:\s*([0-9a-fA-F]{64})", re.IGNORECASE)
EVENT_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Event\*{0,2}\s*:\s*(\S+)", re.IGNORECASE)
EVIDENCE_LIST_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Evidence\*{0,2}\s*:\s*\[([^\]]*)\]", re.IGNORECASE)
EVIDENCE_SINGLE_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Evidence\*{0,2}\s*:\s*(E\d+)", re.IGNORECASE)
EVIDENCE_HASH_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}EvidenceHash\*{0,2}\s*:\s*([0-9a-fA-F]{64})", re.IGNORECASE)

H_FN_RE = re.compile(r"^(H\d+-\d+)_")
E_FN_RE = re.compile(r"^(E\d+)_")
M_FN_RE = re.compile(r"^(M\d+)_")
REPORT_FN_RE = re.compile(r"^investigation-report-(\d+)_.*\.md$")

STATE_CHANGE_EVENTS = {"status-changed", "accepted"}


def rel(p):
    try:
        return os.path.relpath(str(p))
    except ValueError:
        return str(p)


def parse_iso(text):
    try:
        return datetime.fromisoformat(text.strip().replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_records(base):
    """Return dict: {'hypothesis': [...], 'evidence': [...], 'model-changes': [...]}.

    Each record has: label, file, in_field_ts, ctime, prev_hyp_hash, prev_model_hash,
    parent_hyp_event, parent_hyp_hash, event, evidence_list, evidence_hash.
    """
    recs = {"hypothesis": [], "evidence": [], "model-changes": []}
    patterns = {"hypothesis": H_FN_RE, "evidence": E_FN_RE, "model-changes": M_FN_RE}
    for subdir, fn_re in patterns.items():
        d = base / subdir
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if not f.is_file() or not f.name.endswith(".md"):
                continue
            m = fn_re.match(f.name)
            if not m:
                continue
            rec = {
                "label": m.group(1),
                "file": f,
                "subdir": subdir,
                "in_field_ts": None,
                "ctime": None,
                "prev_hyp_hash": None,
                "prev_model_hash": None,
                "parent_hyp_event": None,
                "parent_hyp_hash": None,
                "event": None,
                "evidence_list": None,
                "evidence_hash": None,
            }
            try:
                for line in f.read_text().splitlines():
                    if rec["in_field_ts"] is None:
                        t = TIMESTAMP_RE.match(line)
                        if t:
                            rec["in_field_ts"] = parse_iso(t.group(1))
                            continue
                    if rec["prev_hyp_hash"] is None:
                        g = PREVHYPHASH_RE.match(line)
                        if g:
                            rec["prev_hyp_hash"] = g.group(1).lower()
                            continue
                    if rec["prev_model_hash"] is None:
                        g = PREVMODELHASH_RE.match(line)
                        if g:
                            rec["prev_model_hash"] = g.group(1).lower()
                            continue
                    if rec["parent_hyp_event"] is None:
                        g = PARENT_EVENT_RE.match(line)
                        if g:
                            rec["parent_hyp_event"] = g.group(1)
                            continue
                    if rec["parent_hyp_hash"] is None:
                        g = PARENT_HASH_RE.match(line)
                        if g:
                            rec["parent_hyp_hash"] = g.group(1).lower()
                            continue
                    if rec["event"] is None:
                        g = EVENT_RE.match(line)
                        if g:
                            rec["event"] = g.group(1).strip().rstrip(".,").lower()
                            continue
                    if rec["evidence_list"] is None:
                        g = EVIDENCE_LIST_RE.match(line)
                        if g:
                            items = [s.strip() for s in g.group(1).split(",") if s.strip()]
                            rec["evidence_list"] = items
                            continue
                    if rec["evidence_hash"] is None:
                        g = EVIDENCE_HASH_RE.match(line)
                        if g:
                            rec["evidence_hash"] = g.group(1).lower()
                            continue
            except Exception:
                pass
            try:
                rec["ctime"] = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
            except OSError:
                pass
            recs[subdir].append(rec)
    return recs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("investigation_dir")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    base = Path(args.investigation_dir)
    if not base.is_dir():
        print(f"error: {rel(base)} is not a directory", file=sys.stderr); return 2

    # Collect all investigation-report-<N>_<ts>.md files
    reports = []
    for f in sorted(base.iterdir()) if base.is_dir() else []:
        m = REPORT_FN_RE.match(f.name)
        if m:
            reports.append((int(m.group(1)), f))
    reports.sort()

    if not reports:
        # Backward compat: allow investigation-report.md (un-versioned)
        legacy = base / "investigation-report.md"
        if legacy.is_file():
            reports = [(1, legacy)]
        else:
            print(f"TC30 FAIL: no investigation-report-<N>_*.md files under {rel(base)} — chain cannot be anchored")
            return 1

    # Validate report chain: report 1 has no PrevReportHash, reports N>=2 chain to N-1
    prev_hash = None
    for idx, (n, f) in enumerate(reports):
        declared = None
        for line in f.read_text().splitlines():
            g = PREVREPORTHASH_RE.match(line)
            if g:
                declared = g.group(1).lower()
                break
        if idx == 0:
            # first report: no PrevReportHash expected (but allowed for robustness)
            pass
        else:
            if declared is None:
                print(f"TC30 FAIL: {rel(f)} is report #{n} but missing PrevReportHash: field")
                return 1
            expected = sha256_file(reports[idx - 1][1])
            if declared != expected:
                print(f"TC30 FAIL: {rel(f)} PrevReportHash mismatch: declared {declared[:12]}..., expected {expected[:12]}... from {reports[idx-1][1].name}")
                return 1
        prev_hash = sha256_file(f)

    anchor = sha256_file(reports[0][1])  # anchor is always the FIRST report

    recs = load_records(base)
    all_records = recs["hypothesis"] + recs["evidence"] + recs["model-changes"]
    if not all_records:
        if not args.quiet:
            print(f"TC30 SKIP: no records under {rel(base)} — nothing to check")
        return 0

    # --- Check 1: all records have Timestamp ---
    no_ts = [r for r in all_records if r["in_field_ts"] is None]
    if no_ts:
        print(f"TC30 FAIL: {len(no_ts)} record(s) missing Timestamp: field")
        for r in no_ts:
            print(f"  {rel(r['file'])}")
        return 1

    # --- Check 5: filesystem provenance (in-field vs ctime within 60s) ---
    fs_mismatch = []
    for r in all_records:
        if r["ctime"] is None:
            continue
        delta = abs((r["in_field_ts"] - r["ctime"]).total_seconds())
        if delta > FS_TOLERANCE_SECONDS:
            fs_mismatch.append((r, delta))
    if fs_mismatch:
        print(f"TC30 FAIL: {len(fs_mismatch)} record(s) with filesystem-vs-field timestamp mismatch > {FS_TOLERANCE_SECONDS}s (backdated)")
        for r, d in fs_mismatch:
            print(f"  {rel(r['file'])}: in-field {r['in_field_ts'].isoformat()}, ctime {r['ctime'].isoformat()}, delta {d:.0f}s")
        return 1

    # --- Check 2: hypothesis chain ---
    hyps = sorted(recs["hypothesis"], key=lambda r: (r["in_field_ts"], r["file"].name))
    hyp_errors = []
    hyp_hash_by_label = {}  # label -> current sha256 of its file
    hyp_hash_by_file = {}   # label -> latest sha256 computed
    expected_prev = anchor
    expected_src = "investigation-report.md"
    for h in hyps:
        declared = h["prev_hyp_hash"]
        if declared is None:
            hyp_errors.append((h, f"missing PrevHypHash: (expected {expected_prev[:12]}... from {expected_src})"))
        elif declared != expected_prev:
            hyp_errors.append((h, f"PrevHypHash mismatch: declared {declared[:12]}..., expected {expected_prev[:12]}... from {expected_src}"))
        cur_hash = sha256_file(h["file"])
        hyp_hash_by_label[h["label"]] = cur_hash
        hyp_hash_by_file[h["label"]] = h["file"]
        expected_prev = cur_hash
        expected_src = h["file"].name

    if hyp_errors:
        print(f"TC30 FAIL: {len(hyp_errors)} hypothesis chain violation(s)")
        for r, msg in hyp_errors:
            print(f"  {r['label']} ({rel(r['file'])}): {msg}")
        return 1

    # --- Check 3a: evidence parent links valid ---
    ev_errors = []
    for e in recs["evidence"]:
        if e["parent_hyp_event"] is None:
            ev_errors.append((e, "missing ParentHypEvent:"))
            continue
        if e["parent_hyp_event"] not in hyp_hash_by_label:
            ev_errors.append((e, f"ParentHypEvent: {e['parent_hyp_event']} does not exist in hypothesis/"))
            continue
        if e["parent_hyp_hash"] is None:
            ev_errors.append((e, "missing ParentHypHash:"))
            continue
        expected_parent_hash = hyp_hash_by_label[e["parent_hyp_event"]]
        if e["parent_hyp_hash"] != expected_parent_hash:
            ev_errors.append((e, f"ParentHypHash mismatch for {e['parent_hyp_event']}: declared {e['parent_hyp_hash'][:12]}..., current {expected_parent_hash[:12]}... — parent was edited after evidence was attached, OR evidence was attached to wrong parent"))
    if ev_errors:
        print(f"TC30 FAIL: {len(ev_errors)} evidence parent-link violation(s)")
        for r, msg in ev_errors:
            print(f"  {r['label']} ({rel(r['file'])}): {msg}")
        return 1

    # --- Check 3b: model-change chain + parent links ---
    models = sorted(recs["model-changes"], key=lambda r: (r["in_field_ts"], r["file"].name))
    m_errors = []
    expected_prev_m = anchor
    expected_src_m = "investigation-report.md"
    for m in models:
        # chain
        if m["prev_model_hash"] is None:
            m_errors.append((m, f"missing PrevModelHash: (expected {expected_prev_m[:12]}... from {expected_src_m})"))
        elif m["prev_model_hash"] != expected_prev_m:
            m_errors.append((m, f"PrevModelHash mismatch: declared {m['prev_model_hash'][:12]}..., expected {expected_prev_m[:12]}... from {expected_src_m}"))
        # parent
        if m["parent_hyp_event"] is None:
            m_errors.append((m, "missing ParentHypEvent:"))
        elif m["parent_hyp_event"] not in hyp_hash_by_label:
            m_errors.append((m, f"ParentHypEvent: {m['parent_hyp_event']} does not exist"))
        elif m["parent_hyp_hash"] is None:
            m_errors.append((m, "missing ParentHypHash:"))
        elif m["parent_hyp_hash"] != hyp_hash_by_label[m["parent_hyp_event"]]:
            m_errors.append((m, f"ParentHypHash mismatch for {m['parent_hyp_event']}"))
        expected_prev_m = sha256_file(m["file"])
        expected_src_m = m["file"].name
    if m_errors:
        print(f"TC30 FAIL: {len(m_errors)} model-change link/chain violation(s)")
        for r, msg in m_errors:
            print(f"  {r['label']} ({rel(r['file'])}): {msg}")
        return 1

    # --- Check 4: state-change EvidenceHash ---
    ev_by_label = {e["label"]: e for e in recs["evidence"]}
    sc_errors = []
    for h in hyps:
        if h["event"] not in STATE_CHANGE_EVENTS:
            continue
        if h["evidence_list"] is None:
            sc_errors.append((h, f"{h['event']} event missing Evidence: [...] list"))
            continue
        if h["evidence_hash"] is None:
            sc_errors.append((h, f"{h['event']} event missing EvidenceHash:"))
            continue
        # compute expected EvidenceHash
        missing = [lbl for lbl in h["evidence_list"] if lbl not in ev_by_label]
        if missing:
            sc_errors.append((h, f"Evidence list references non-existent: {missing}"))
            continue
        ev_hashes = sorted(sha256_file(ev_by_label[lbl]["file"]) for lbl in h["evidence_list"])
        expected = hashlib.sha256("".join(ev_hashes).encode("ascii")).hexdigest()
        if h["evidence_hash"] != expected:
            sc_errors.append((h, f"EvidenceHash mismatch: declared {h['evidence_hash'][:12]}..., expected {expected[:12]}... (cited evidence was edited after citation, or hash was computed wrong)"))
    if sc_errors:
        print(f"TC30 FAIL: {len(sc_errors)} state-change EvidenceHash violation(s)")
        for r, msg in sc_errors:
            print(f"  {r['label']} ({rel(r['file'])}): {msg}")
        return 1

    if not args.quiet:
        total_span = max(r["in_field_ts"] for r in all_records) - min(r["in_field_ts"] for r in all_records)
        print(
            f"TC30 PASS: {len(all_records)} records "
            f"({len(hyps)} H, {len(recs['evidence'])} E, {len(models)} M) "
            f"spanning {total_span.total_seconds():.3f}s; "
            f"H chain valid, E parent-links valid, M chain+links valid, "
            f"EvidenceHash valid, filesystem provenance clean"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
