#!/usr/bin/env python3
"""Validate Full_Roadmap sources and emit a non-executable import plan.

This utility deliberately has no Supabase connection code and never writes to a
database.  It is a guardrail for the eventual owner-scoped insert-only import,
not an operational-data reset.  In particular, it does not accept an owner UUID, does not
generate database UUIDs, and does not turn the source's 392 Hsoub videos into
392 scheduled task occurrences.

Examples
--------
python tool/plan_full_roadmap_import.py \
  --json "C:\\Users\\yasse\\Downloads\\New folder\\Full_Roadmap.json" \
  --docx "C:\\Users\\yasse\\Downloads\\New folder\\Full_Roadmap.docx" \
  --summary

python tool/plan_full_roadmap_import.py \
  --json "...\\Full_Roadmap.json" --docx "...\\Full_Roadmap.docx" \
  --emit-plan > roadmap-import-plan.json

python tool/plan_full_roadmap_import.py \
  --json "...\\Full_Roadmap.json" --docx "...\\Full_Roadmap.docx" \
  --emit-rpc-request > roadmap-import-request.json

The emitted JSON is intentionally a *plan*.  A future authenticated import
command must acquire the caller from auth.uid(), record the source hash in an
owner-scoped import ledger, and run the insert-only import atomically.  The
RPC request emitted here deliberately has no owner ID, device ID, credentials,
or database URL.  A signed-in, registered installation supplies its own
device ID only when the user explicitly approves the import.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Iterable
from xml.etree import ElementTree


PLAN_FORMAT = "taskmaster-pro-roadmap-import-plan/v1"
RPC_REQUEST_FORMAT = "taskmaster-pro-roadmap-import-request/v1"
TARGET_PROJECT_REF = "tmvarulrujkmibqpqoeo"
IMPORT_KIND = "full_roadmap_initial"
IMPORT_RPC = "import_full_roadmap_v0028"
DOCX_NAMESPACE = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


class PlanValidationError(ValueError):
    """Raised when a source cannot safely become an import plan."""


@dataclass(frozen=True)
class SourceStats:
    programming_phases: int
    programming_tasks: int
    german_phases: int
    german_tasks: int
    english_phases: int
    english_tasks: int
    hsoub_modules: int
    hsoub_videos: int
    hsoub_weeks: int

    @property
    def roadmap_count(self) -> int:
        return 3

    @property
    def phase_count(self) -> int:
        return self.programming_phases + self.german_phases + self.english_phases

    @property
    def task_count(self) -> int:
        return self.programming_tasks + self.german_tasks + self.english_tasks


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _source_fingerprint(json_sha256: str, docx_sha256: str) -> str:
    """Return the stable source identity also recomputed by the database RPC."""

    material = f"{PLAN_FORMAT}\n{json_sha256}\n{docx_sha256}".encode("ascii")
    return hashlib.sha256(material).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise PlanValidationError(f"JSON source does not exist: {path}")
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise PlanValidationError(f"Could not read JSON source: {error}") from error
    if not isinstance(payload, dict):
        raise PlanValidationError("JSON root must be an object")
    return payload


def _docx_text(path: Path) -> str:
    if not path.is_file():
        raise PlanValidationError(f"DOCX source does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            document = archive.read("word/document.xml")
        root = ElementTree.fromstring(document)
    except (OSError, KeyError, zipfile.BadZipFile, ElementTree.ParseError) as error:
        raise PlanValidationError(f"Could not read DOCX source: {error}") from error
    paragraphs = []
    for paragraph in root.findall(".//w:p", DOCX_NAMESPACE):
        text = "".join(
            node.text or "" for node in paragraph.findall(".//w:t", DOCX_NAMESPACE)
        ).strip()
        if text:
            paragraphs.append(text)
    return "\n".join(paragraphs)


def _required_list(payload: dict[str, Any], key: str) -> list[Any]:
    value = payload.get(key)
    if not isinstance(value, list):
        raise PlanValidationError(f"{key} must be a list")
    return value


def _safe_key(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-")
    return slug or "item"


def _validate_task_pair(value: Any, location: str) -> tuple[str, str]:
    if not isinstance(value, list) or len(value) != 2:
        raise PlanValidationError(f"{location} must be a [title, https_url] pair")
    title, url = value
    if not isinstance(title, str) or not title.strip():
        raise PlanValidationError(f"{location} has no task title")
    if not isinstance(url, str) or not url.startswith("https://"):
        raise PlanValidationError(f"{location} must use an https URL")
    return title.strip(), url.strip()


def _validate_phase_section(
    payload: dict[str, Any],
    key: str,
    expected_phase_count: int,
) -> tuple[list[dict[str, Any]], int]:
    phases = _required_list(payload, key)
    if len(phases) != expected_phase_count:
        raise PlanValidationError(
            f"{key} must contain {expected_phase_count} phases, found {len(phases)}"
        )
    task_count = 0
    validated: list[dict[str, Any]] = []
    for phase_index, phase in enumerate(phases, start=1):
        if not isinstance(phase, dict):
            raise PlanValidationError(f"{key}[{phase_index}] must be an object")
        title = phase.get("phase")
        if not isinstance(title, str) or not title.strip():
            raise PlanValidationError(f"{key}[{phase_index}] needs a phase title")
        tasks = _required_list(phase, "tasks")
        if not tasks:
            raise PlanValidationError(f"{key}[{phase_index}] must contain at least one task")
        normalized_tasks = []
        for task_index, task in enumerate(tasks, start=1):
            task_title, url = _validate_task_pair(
                task, f"{key}[{phase_index}].tasks[{task_index}]"
            )
            normalized_tasks.append({"title": task_title, "url": url})
        task_count += len(normalized_tasks)
        timebox = phase.get("weeks", phase.get("duration", ""))
        if not isinstance(timebox, str):
            raise PlanValidationError(f"{key}[{phase_index}] timebox must be text")
        validated.append(
            {
                "title": title.strip(),
                "source_timebox": timebox.strip(),
                "tasks": normalized_tasks,
            }
        )
    return validated, task_count


def _parse_iso_date(value: Any, location: str) -> str:
    if not isinstance(value, str):
        raise PlanValidationError(f"{location} must be an ISO date")
    try:
        return date.fromisoformat(value).isoformat()
    except ValueError as error:
        raise PlanValidationError(f"{location} must be an ISO date") from error


def _validate_hsoub(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], int, int]:
    modules = _required_list(payload, "hsoub_modules")
    videos = _required_list(payload, "hsoub_videos")
    weekly = _required_list(payload, "hsoub_weekly_checklist")
    if len(modules) != 50:
        raise PlanValidationError(f"hsoub_modules must contain 50 modules, found {len(modules)}")
    if len(videos) != 392:
        raise PlanValidationError(f"hsoub_videos must contain 392 videos, found {len(videos)}")
    if len(weekly) != 49:
        raise PlanValidationError(
            f"hsoub_weekly_checklist must contain 49 weeks, found {len(weekly)}"
        )

    known_video_indices: set[int] = set()
    for video_index, video in enumerate(videos, start=1):
        if not isinstance(video, dict):
            raise PlanValidationError(f"hsoub_videos[{video_index}] must be an object")
        remaining_index = video.get("remaining_index")
        title = video.get("title")
        url = video.get("source_url")
        if not isinstance(remaining_index, int) or remaining_index <= 0:
            raise PlanValidationError(
                f"hsoub_videos[{video_index}].remaining_index must be a positive integer"
            )
        if remaining_index in known_video_indices:
            raise PlanValidationError(
                f"hsoub_videos contains duplicate remaining_index {remaining_index}"
            )
        if not isinstance(title, str) or not title.strip():
            raise PlanValidationError(f"hsoub_videos[{video_index}] has no title")
        if not isinstance(url, str) or not url.startswith("https://"):
            raise PlanValidationError(f"hsoub_videos[{video_index}] must use an https source_url")
        known_video_indices.add(remaining_index)

    weeks: list[dict[str, Any]] = []
    scheduled_indices: set[int] = set()
    for expected_week, entry in enumerate(weekly, start=1):
        if not isinstance(entry, dict):
            raise PlanValidationError(f"hsoub_weekly_checklist[{expected_week}] must be an object")
        if entry.get("week") != expected_week:
            raise PlanValidationError(
                "hsoub_weekly_checklist must be ordered and numbered continuously 1-49"
            )
        start = _parse_iso_date(
            entry.get("start_date"), f"hsoub_weekly_checklist[{expected_week}].start_date"
        )
        end = _parse_iso_date(
            entry.get("end_date"), f"hsoub_weekly_checklist[{expected_week}].end_date"
        )
        if date.fromisoformat(end) < date.fromisoformat(start):
            raise PlanValidationError(
                f"hsoub_weekly_checklist[{expected_week}] ends before it starts"
            )
        weekly_videos = _required_list(entry, "videos")
        if len(weekly_videos) != 8:
            raise PlanValidationError(
                f"hsoub_weekly_checklist[{expected_week}] must contain exactly 8 videos"
            )
        checkpoints: list[dict[str, Any]] = []
        for video_position, video in enumerate(weekly_videos, start=1):
            if not isinstance(video, dict):
                raise PlanValidationError(
                    f"hsoub_weekly_checklist[{expected_week}].videos[{video_position}] must be an object"
                )
            remaining_index = video.get("remaining_index")
            if remaining_index not in known_video_indices:
                raise PlanValidationError(
                    f"Hsoub week {expected_week} references an unknown video {remaining_index}"
                )
            if remaining_index in scheduled_indices:
                raise PlanValidationError(
                    f"Hsoub video {remaining_index} appears in more than one weekly checkpoint"
                )
            scheduled_indices.add(remaining_index)
            title = video.get("title")
            url = video.get("source_url")
            if not isinstance(title, str) or not title.strip():
                raise PlanValidationError(
                    f"Hsoub week {expected_week} video {video_position} has no title"
                )
            if not isinstance(url, str) or not url.startswith("https://"):
                raise PlanValidationError(
                    f"Hsoub week {expected_week} video {video_position} must use https"
                )
            checkpoints.append(
                {
                    "remaining_index": remaining_index,
                    "course_video_number": video.get("course_video_number"),
                    "category": video.get("category"),
                    "module": video.get("module"),
                    "title": title.strip(),
                    "source_url": url.strip(),
                }
            )
        weeks.append(
            {
                "week": expected_week,
                "start_date": start,
                "end_date": end,
                "videos": checkpoints,
            }
        )
    if scheduled_indices != known_video_indices:
        missing = sorted(known_video_indices - scheduled_indices)
        unexpected = sorted(scheduled_indices - known_video_indices)
        raise PlanValidationError(
            "Hsoub weekly checklist must cover every remaining video exactly once "
            f"(missing={missing[:5]}, unexpected={unexpected[:5]})"
        )
    return weeks, len(modules), len(videos)


def _validate_docx_against_source(docx_text: str) -> None:
    required_signals = (
        "INTEGRATED LEARNING ROADMAP",
        "Full-Stack Development + German + English",
        "392 videos",
        "49 weeks",
    )
    absent = [signal for signal in required_signals if signal not in docx_text]
    if absent:
        raise PlanValidationError(
            "DOCX does not match the supplied roadmap source; missing signals: "
            + ", ".join(absent)
        )


def _to_phase_plan(roadmap_key: str, phases: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    planned_phases: list[dict[str, Any]] = []
    for phase_position, source_phase in enumerate(phases):
        phase_key = f"{roadmap_key}:{_safe_key(source_phase['title'])}"
        tasks = []
        for task_position, task in enumerate(source_phase["tasks"], start=1):
            tasks.append(
                {
                    "external_key": f"{phase_key}:task:{task_position:03d}",
                    "title": task["title"],
                    "initial_status": "ready",
                    "progress": 0,
                    "execution_mode": "manual",
                    "scheduled_at": None,
                    "estimated_duration_ms": None,
                    "resource": {
                        "type": "website",
                        "url": task["url"],
                        # The database's canonical vocabulary is page,
                        # section, host, or site.  "page" is the exact-page
                        # relationship required for an imported learning URL.
                        "matching_scope": "page",
                    },
                }
            )
        planned_phases.append(
            {
                "external_key": phase_key,
                "position": phase_position,
                "title": source_phase["title"],
                "source_timebox": source_phase["source_timebox"],
                "planned_start": None,
                "planned_finish": None,
                "tasks": tasks,
            }
        )
    return planned_phases


def build_import_plan(json_path: Path, docx_path: Path) -> dict[str, Any]:
    """Build a deterministic, non-executable import mapping from the sources."""

    payload = _load_json(json_path)
    programming, programming_task_count = _validate_phase_section(
        payload, "programming_phases", 8
    )
    german, german_task_count = _validate_phase_section(payload, "german_phases", 6)
    english, english_task_count = _validate_phase_section(payload, "english_phases", 5)
    hsoub_weeks, hsoub_modules, hsoub_videos = _validate_hsoub(payload)
    _validate_docx_against_source(_docx_text(docx_path))

    stats = SourceStats(
        programming_phases=len(programming),
        programming_tasks=programming_task_count,
        german_phases=len(german),
        german_tasks=german_task_count,
        english_phases=len(english),
        english_tasks=english_task_count,
        hsoub_modules=hsoub_modules,
        hsoub_videos=hsoub_videos,
        hsoub_weeks=len(hsoub_weeks),
    )
    sources = {
        "json": {
            "path": str(json_path.resolve()),
            "sha256": _sha256(json_path),
        },
        "docx": {
            "path": str(docx_path.resolve()),
            "sha256": _sha256(docx_path),
        },
    }

    full_stack = {
        "external_key": "full_stack_development",
        "title": "Full-Stack Development",
        "source_section": "programming_phases",
        "initial_progress": 0,
        "initial_completed_effort_ms": 0,
        "forecast": {
            "state": "not_enough_data_yet",
            "forecast_target_date": None,
            "confidence": "insufficient",
        },
        "phases": _to_phase_plan("full_stack_development", programming),
        "checkpoints": [
            {
                "external_key": f"full_stack_development:hsoub-week:{entry['week']:02d}",
                "title": f"Hsoub Academy — week {entry['week']} ({len(entry['videos'])} videos)",
                "target_date": entry["end_date"],
                "data": {
                    "start_date": entry["start_date"],
                    "end_date": entry["end_date"],
                    "videos": entry["videos"],
                    "source_mapping": "weekly_checkpoint_not_task_occurrences",
                },
            }
            for entry in hsoub_weeks
        ],
    }
    german_roadmap = {
        "external_key": "german_professional_fluency",
        "title": "German Professional Fluency",
        "source_section": "german_phases",
        "initial_progress": 0,
        "initial_completed_effort_ms": 0,
        "forecast": {
            "state": "not_enough_data_yet",
            "forecast_target_date": None,
            "confidence": "insufficient",
        },
        "phases": _to_phase_plan("german_professional_fluency", german),
        "checkpoints": [],
    }
    english_roadmap = {
        "external_key": "english_professional_fluency",
        "title": "English Professional Fluency",
        "source_section": "english_phases",
        "initial_progress": 0,
        "initial_completed_effort_ms": 0,
        "forecast": {
            "state": "not_enough_data_yet",
            "forecast_target_date": None,
            "confidence": "insufficient",
        },
        "phases": _to_phase_plan("english_professional_fluency", english),
        "checkpoints": [],
    }

    return {
        "format": PLAN_FORMAT,
        "mode": "dry_run_only",
        "remote_mutations": False,
        "source": sources,
        "collection": {
            "title": "Integrated Learning Roadmap",
            "implementation_note": (
                "A user-facing collection label only. The current schema has no "
                "canonical roadmap-group table, so this must not be invented as a "
                "fourth roadmap."
            ),
        },
        "mapping": {
            "roadmaps": [full_stack, german_roadmap, english_roadmap],
            "unapplied_source_metadata": payload.get("metadata", {}),
        },
        "counts": {
            "roadmaps": stats.roadmap_count,
            "phases": stats.phase_count,
            "task_occurrences": stats.task_count,
            "website_resources": stats.task_count,
            "hsoub_weekly_checkpoints": stats.hsoub_weeks,
            "hsoub_videos_represented_as_checkpoints": stats.hsoub_videos,
            "hsoub_modules": stats.hsoub_modules,
        },
        "import_invariants": {
            "no_fake_history": True,
            "no_fake_durations": True,
            "no_fake_task_dates": True,
            "no_forecast_until_real_completed_work_exists": True,
            "hsoub_videos_are_not_individual_scheduled_task_occurrences": True,
            "website_matching_scope_is_page_until_user_changes_it": True,
            "idempotency_key": (
                "authenticated_owner_id + json.sha256 + "
                "taskmaster-pro-roadmap-import-plan/v1"
            ),
        },
        "future_import_contract": {
            "this_utility_does_not_execute_it": True,
            "operation": "insert_only_owner_scoped_import",
            "preserves_existing_owner_settings": True,
            "owner_scope": "derive owner only from auth.uid() in the authenticated RPC",
            "required_server_preconditions": [
                "An atomic, owner-scoped transaction protected by an advisory lock",
                "A registered device bound to the caller's active Auth session",
                "A source-hash import ledger that rejects duplicate imports",
                "The clean-project target-ref guard accepts only tmvarulrujkmibqpqoeo",
            ],
            "explicitly_forbidden": [
                "hard-coded owner UUIDs",
                "session_replication_role changes",
                "delete or truncate of owner data",
                "deleting auth users",
                "using the legacy project as an import target",
            ],
        },
        "decisions_confirmed_for_initial_import": [
            "Import only for the authenticated owner; do not reset every project user.",
            "Do not delete or change existing profile, settings, Areas, browser, health, or vault data.",
            "Keep Hsoub as 49 weekly checkpoints rather than 392 individual task occurrences.",
        ],
    }


def build_rpc_request(
    plan: dict[str, Any],
    *,
    target_project_ref: str = TARGET_PROJECT_REF,
) -> dict[str, Any]:
    """Create a deferred, credential-free request for the owner-bound RPC.

    This deliberately cannot execute the import.  It removes local filesystem
    paths, contains no owner identity, and refuses a target other than the new
    clean project.  The database RPC revalidates the same target/source identity
    and derives the owner from the authenticated session.
    """

    if target_project_ref != TARGET_PROJECT_REF:
        raise PlanValidationError(
            "The roadmap importer is guarded for "
            f"{TARGET_PROJECT_REF}; refusing target {target_project_ref!r}"
        )
    if plan.get("format") != PLAN_FORMAT:
        raise PlanValidationError("Unsupported roadmap import plan format")
    source = plan.get("source")
    mapping = plan.get("mapping")
    counts = plan.get("counts")
    if not isinstance(source, dict) or not isinstance(mapping, dict) or not isinstance(counts, dict):
        raise PlanValidationError("Plan has no complete source, mapping, or counts")
    json_source = source.get("json")
    docx_source = source.get("docx")
    if not isinstance(json_source, dict) or not isinstance(docx_source, dict):
        raise PlanValidationError("Plan has no complete JSON/DOCX source hashes")
    json_sha256 = json_source.get("sha256")
    docx_sha256 = docx_source.get("sha256")
    if not isinstance(json_sha256, str) or not isinstance(docx_sha256, str):
        raise PlanValidationError("Plan source hashes are invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", json_sha256) or not re.fullmatch(
        r"[0-9a-f]{64}", docx_sha256
    ):
        raise PlanValidationError("Plan source hashes must be lowercase SHA-256 values")

    # The database-side implementation must carry its own immutable manifest.
    # This deferred request carries only the fingerprint and compact counts,
    # never the 143-task mapping or local source paths.  That keeps the real
    # import to one small owner-bound command instead of a bulk client upload.
    return {
        "format": RPC_REQUEST_FORMAT,
        "remote_mutations": False,
        "rpc": {
            "name": IMPORT_RPC,
            "target_project_ref": TARGET_PROJECT_REF,
            "required_runtime_inputs": [
                "p_device_id from the signed-in installation registered to the active Auth session",
                "explicit user approval at execution time",
            ],
        },
        "p_request": {
            "format": RPC_REQUEST_FORMAT,
            "target_project_ref": TARGET_PROJECT_REF,
            "import_kind": IMPORT_KIND,
            "plan_format": PLAN_FORMAT,
            "source": {
                "json_sha256": json_sha256,
                "docx_sha256": docx_sha256,
                "source_fingerprint": _source_fingerprint(json_sha256, docx_sha256),
            },
            "counts": {
                key: counts[key]
                for key in (
                    "roadmaps",
                    "phases",
                    "task_occurrences",
                    "website_resources",
                    "hsoub_weekly_checkpoints",
                    "hsoub_videos_represented_as_checkpoints",
                    "hsoub_modules",
                )
            },
            "behavior": {
                "operation": "insert_only",
                "preserve_existing_owner_data": True,
                "hsoub_mapping": "weekly_checkpoints_not_task_occurrences",
            },
        },
    }


def _summary(plan: dict[str, Any]) -> dict[str, Any]:
    return {
        "format": plan["format"],
        "mode": plan["mode"],
        "remote_mutations": plan["remote_mutations"],
        "source": plan["source"],
        "counts": plan["counts"],
        "roadmaps": [
            {
                "external_key": roadmap["external_key"],
                "title": roadmap["title"],
                "phases": len(roadmap["phases"]),
                "tasks": sum(len(phase["tasks"]) for phase in roadmap["phases"]),
                "checkpoints": len(roadmap["checkpoints"]),
            }
            for roadmap in plan["mapping"]["roadmaps"]
        ],
        "decisions_confirmed_for_initial_import": plan[
            "decisions_confirmed_for_initial_import"
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, required=True, help="Full_Roadmap.json")
    parser.add_argument("--docx", type=Path, required=True, help="Full_Roadmap.docx")
    output = parser.add_mutually_exclusive_group()
    output.add_argument(
        "--summary",
        action="store_true",
        help="emit concise validation/count evidence (the default)",
    )
    output.add_argument(
        "--emit-plan",
        action="store_true",
        help="emit the complete non-executable JSON mapping to stdout",
    )
    output.add_argument(
        "--emit-rpc-request",
        action="store_true",
        help=(
            "emit a deferred, credential-free request for the owner-bound "
            "clean-project import RPC; does not call Supabase"
        ),
    )
    args = parser.parse_args(argv)
    try:
        plan = build_import_plan(args.json, args.docx)
    except PlanValidationError as error:
        print(f"Roadmap import plan validation failed: {error}", file=sys.stderr)
        return 2
    value = (
        build_rpc_request(plan)
        if args.emit_rpc_request
        else plan
        if args.emit_plan
        else _summary(plan)
    )
    print(json.dumps(value, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
