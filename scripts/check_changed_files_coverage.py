#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys
from typing import Dict, List, Optional, Tuple


def run_command(args: List[str]) -> str:
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    return result.stdout


def load_coverage_report(result_bundle_path: str) -> Dict:
    output = run_command(
        ["xcrun", "xccov", "view", "--report", "--json", result_bundle_path]
    )
    return json.loads(output)


def find_app_target(report: Dict) -> Dict:
    for target in report.get("targets", []):
        name = target.get("name", "")
        build_product_path = target.get("buildProductPath", "")
        if name in {"LifeAdvisorApp", "LifeAdvisorApp.app"}:
            return target
        if build_product_path.endswith("/LifeAdvisorApp"):
            return target
    raise RuntimeError("Could not find LifeAdvisorApp target in coverage report")


def repo_root() -> str:
    return run_command(["git", "rev-parse", "--show-toplevel"]).strip()


def changed_files_from_git(base_sha: str, head_sha: str) -> List[str]:
    diff_output = run_command(["git", "diff", "--name-only", f"{base_sha}...{head_sha}"])
    return [line.strip() for line in diff_output.splitlines() if line.strip()]


def is_production_swift_file(path: str) -> bool:
    if not path.endswith(".swift"):
        return False
    if not path.startswith("LifeAdvisorApp/LifeAdvisorApp/"):
        return False
    if "/Tests/" in path or path.endswith("Tests.swift"):
        return False
    return True


def build_coverage_index(app_target: Dict) -> Dict[str, Dict]:
    index: Dict[str, Dict] = {}
    for file_entry in app_target.get("files", []):
        coverage_path = file_entry.get("path")
        if coverage_path:
            index[coverage_path] = file_entry
    return index


def match_coverage_entry(relative_path: str, coverage_index: Dict[str, Dict]) -> Optional[Dict]:
    normalized_suffix = relative_path.replace("\\", "/")
    for absolute_path, entry in coverage_index.items():
        if absolute_path.replace("\\", "/").endswith(normalized_suffix):
            return entry
    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check code coverage for changed production Swift files."
    )
    parser.add_argument("--result-bundle", required=True, help="Path to .xcresult bundle")
    parser.add_argument("--threshold", type=float, default=80.0, help="Coverage threshold percent")
    parser.add_argument("--base-sha", help="Base commit SHA for PR diff")
    parser.add_argument("--head-sha", help="Head commit SHA for PR diff")
    parser.add_argument(
        "--files",
        nargs="*",
        default=None,
        help="Optional explicit repo-relative file list for local validation",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = load_coverage_report(args.result_bundle)
    app_target = find_app_target(report)
    coverage_index = build_coverage_index(app_target)

    changed_files = args.files
    if changed_files is None:
        if not args.base_sha or not args.head_sha:
            print("No changed-file input provided; skipping coverage gate.")
            return 0
        changed_files = changed_files_from_git(args.base_sha, args.head_sha)

    production_files = [path for path in changed_files if is_production_swift_file(path)]

    if not production_files:
        print("No changed production Swift files found; coverage gate skipped.")
        return 0

    total_covered = 0
    total_executable = 0
    missing_files: List[str] = []
    file_summaries: List[Tuple[str, int, int, float]] = []

    for path in production_files:
        entry = match_coverage_entry(path, coverage_index)
        if entry is None:
            missing_files.append(path)
            continue

        covered = int(entry.get("coveredLines", 0))
        executable = int(entry.get("executableLines", 0))
        coverage = float(entry.get("lineCoverage", 0.0)) * 100.0
        file_summaries.append((path, covered, executable, coverage))

        total_covered += covered
        total_executable += executable

    print("Changed production Swift files coverage:")
    for path, covered, executable, coverage in sorted(file_summaries):
        print(f"- {path}: {coverage:.1f}% ({covered}/{executable})")

    if missing_files:
        print("\nFiles missing from coverage report:")
        for path in sorted(missing_files):
            print(f"- {path}")
        print("\nFailing because changed production files must be part of the tested target.")
        return 1

    if total_executable == 0:
        print("\nChanged production files have no executable lines; coverage gate skipped.")
        return 0

    aggregate = (total_covered / total_executable) * 100.0
    print(f"\nAggregate changed-files coverage: {aggregate:.1f}% ({total_covered}/{total_executable})")
    print(f"Required threshold: {args.threshold:.1f}%")

    if aggregate + 1e-9 < args.threshold:
        print("\nCoverage gate failed.")
        return 1

    print("\nCoverage gate passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
