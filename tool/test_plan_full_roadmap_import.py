"""Self-contained tests for the non-destructive roadmap import planner."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("plan_full_roadmap_import.py")
SPEC = importlib.util.spec_from_file_location("roadmap_import_planner", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
PLANNER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PLANNER
SPEC.loader.exec_module(PLANNER)


def _phase(prefix: str, number: int) -> dict[str, object]:
    return {
        "phase": f"{prefix}{number} - Test phase",
        "weeks" if prefix == "P" else "duration": "Week 1",
        "tasks": [[f"{prefix}{number} task", "https://example.test/lesson"]],
    }


def _payload() -> dict[str, object]:
    videos = [
        {
            "remaining_index": index,
            "course_video_number": index + 48,
            "category": "Test",
            "module": "Test module",
            "title": f"Video {index}",
            "source_url": "https://academy.example.test/",
        }
        for index in range(1, 393)
    ]
    weekly = []
    for week in range(1, 50):
        first = (week - 1) * 8
        weekly.append(
            {
                "week": week,
                "start_date": "2026-08-08",
                "end_date": "2026-08-14",
                "videos": videos[first : first + 8],
            }
        )
    return {
        "metadata": {"title": "Test roadmap"},
        "programming_phases": [_phase("P", index) for index in range(8)],
        "german_phases": [_phase("G", index) for index in range(6)],
        "english_phases": [_phase("E", index) for index in range(5)],
        "hsoub_modules": [{"module": f"Module {index}"} for index in range(50)],
        "hsoub_videos": videos,
        "hsoub_weekly_checklist": weekly,
    }


def _write_minimal_docx(path: Path) -> None:
    body = "".join(
        f"<w:p><w:r><w:t>{signal}</w:t></w:r></w:p>"
        for signal in (
            "INTEGRATED LEARNING ROADMAP",
            "Full-Stack Development + German + English",
            "392 videos",
            "49 weeks",
        )
    )
    xml = (
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        f"<w:body>{body}</w:body></w:document>"
    )
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("word/document.xml", xml)


class ImportPlanTests(unittest.TestCase):
    def _sources(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        json_path = root / "Full_Roadmap.json"
        docx_path = root / "Full_Roadmap.docx"
        json_path.write_text(json.dumps(_payload()), encoding="utf-8")
        _write_minimal_docx(docx_path)
        return temp, json_path, docx_path

    def test_plan_preserves_three_roadmaps_without_fake_schedule_or_history(self) -> None:
        temp, json_path, docx_path = self._sources()
        with temp:
            plan = PLANNER.build_import_plan(json_path, docx_path)
        self.assertEqual("dry_run_only", plan["mode"])
        self.assertFalse(plan["remote_mutations"])
        self.assertEqual(3, plan["counts"]["roadmaps"])
        self.assertEqual(19, plan["counts"]["phases"])
        self.assertEqual(19, plan["counts"]["task_occurrences"])
        self.assertEqual(49, plan["counts"]["hsoub_weekly_checkpoints"])
        self.assertEqual(
            392, plan["counts"]["hsoub_videos_represented_as_checkpoints"]
        )
        serialized = json.dumps(plan)
        # The plan describes a future authenticated owner lookup, but it must
        # never smuggle the legacy production owner UUID or executable SQL in.
        self.assertNotIn("4bd3e32d-1dcd-48ed-9f64-9099675047f1", serialized)
        self.assertNotIn("delete from", serialized.casefold())
        self.assertNotIn("set local session_replication_role", serialized.casefold())
        first_task = plan["mapping"]["roadmaps"][0]["phases"][0]["tasks"][0]
        self.assertIsNone(first_task["scheduled_at"])
        self.assertIsNone(first_task["estimated_duration_ms"])
        self.assertEqual("page", first_task["resource"]["matching_scope"])

    def test_deferred_rpc_request_is_clean_target_only_and_has_no_owner_or_paths(self) -> None:
        temp, json_path, docx_path = self._sources()
        with temp:
            plan = PLANNER.build_import_plan(json_path, docx_path)
            request = PLANNER.build_rpc_request(plan)

        self.assertFalse(request["remote_mutations"])
        self.assertEqual("import_full_roadmap_v0028", request["rpc"]["name"])
        self.assertEqual("tmvarulrujkmibqpqoeo", request["rpc"]["target_project_ref"])
        payload = request["p_request"]
        self.assertEqual("full_roadmap_initial", payload["import_kind"])
        self.assertEqual(3, payload["counts"]["roadmaps"])
        self.assertEqual(49, payload["counts"]["hsoub_weekly_checkpoints"])
        self.assertEqual(392, payload["counts"]["hsoub_videos_represented_as_checkpoints"])
        self.assertNotIn("mapping", payload)
        self.assertEqual(
            PLANNER._source_fingerprint(
                payload["source"]["json_sha256"], payload["source"]["docx_sha256"]
            ),
            payload["source"]["source_fingerprint"],
        )
        serialized = json.dumps(request)
        self.assertNotIn("owner_id", serialized)
        self.assertNotIn(str(json_path.parent), serialized)
        self.assertNotIn("delete from", serialized.casefold())

    def test_deferred_rpc_request_rejects_any_other_project(self) -> None:
        temp, json_path, docx_path = self._sources()
        with temp:
            plan = PLANNER.build_import_plan(json_path, docx_path)
            with self.assertRaises(PLANNER.PlanValidationError):
                PLANNER.build_rpc_request(plan, target_project_ref="iejbogkqknldxoyepvun")

    def test_duplicate_hsoub_video_is_rejected(self) -> None:
        temp, json_path, docx_path = self._sources()
        with temp:
            data = json.loads(json_path.read_text(encoding="utf-8"))
            data["hsoub_weekly_checklist"][1]["videos"][0] = data[
                "hsoub_weekly_checklist"
            ][0]["videos"][0]
            json_path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaises(PLANNER.PlanValidationError):
                PLANNER.build_import_plan(json_path, docx_path)


if __name__ == "__main__":
    unittest.main()
