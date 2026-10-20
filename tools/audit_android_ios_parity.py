#!/usr/bin/env python3
"""Inventory local Android code without running the APK or reading app data.

The output is an index for manual behavioral review, not a parity certification.
Original bytecode and generated inventory remain in the ignored work directory.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]


def inventory(decoded: Path, output: Path):
    if not decoded.is_dir():
        raise FileNotFoundError("Supply the existing locally decoded Android project")
    classes, bindings, endpoints, native_events = [], [], [], []
    for dex in sorted(decoded.glob("smali*")):
        if not dex.is_dir():
            continue
        paths = list((dex / "mobi/ifunny").rglob("*.smali"))
        paths += list((dex / "revival").rglob("*.smali"))
        paths += list((dex / "bricks/views").rglob("*.smali"))
        for path in sorted(paths):
            text = path.read_text()
            relative = path.relative_to(decoded).as_posix()
            methods = re.findall(r"^\.method (.+)$", text, re.M)
            classes.append(dict(path=relative, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), methods=len(methods)))
            if "_ViewBinding" in path.stem:
                fields = re.findall(r"iput-object\s+[^\n]+->([^:]+):([^\n]+)", text)
                bindings.append(dict(path=relative, bound_fields=sorted({name for name, _ in fields}), click_listeners=text.count("setOnClickListener")))
            for method in re.finditer(r"^\.method ([^\n]+)\n(.*?)^\.end method", text, re.M | re.S):
                signature, body = method.groups()
                route = re.search(r"\.annotation runtime Lretrofit(?:2)?/http/(GET|POST|PUT|DELETE|PATCH);\s+value = \"([^\"]+)\"", body)
                if route:
                    endpoints.append(dict(path=relative, method=signature, http=route[1], route=route[2], parameters=re.findall(r"\.annotation runtime Lretrofit(?:2)?/http/(Path|Query|Field|Part);\s+value = \"([^\"]+)\"", body)))
                if any(event in signature for event in ("onClick(", "onLongClick(", "onTouch(", "onFling(", "onScroll(", "onBackPressed(", "onItemSelected(", "onOptionsItemSelected(", "onPageSelected(")):
                    native_events.append(dict(path=relative, method=signature))
    helpers = []
    for path in sorted((ROOT / "android-src/revival").glob("*.java")):
        helpers.append(dict(path=path.relative_to(ROOT).as_posix(), sha256=hashlib.sha256(path.read_bytes()).hexdigest(), lines=len(path.read_text().splitlines())))
    if not classes:
        raise ValueError("No iFunny classes found; this is not a decoded reference project")
    report = dict(decoded_directory=str(decoded), original_code_executed=False, account_data_read=False,
                  purpose="Structural index for behavioral audit; not all branches manually reviewed or parity verified",
                  summary=dict(classes=len(classes), binding_classes=len(bindings), rest_methods=len(endpoints), interaction_entrypoints=len(native_events), readable_helpers=len(helpers)),
                  classes=classes, bindings=bindings, endpoints=endpoints, interaction_entrypoints=native_events, readable_helpers=helpers)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise ValueError("Choose a new inventory filename")
    output.write_text(json.dumps(report, indent=2) + "\n")
    return report["summary"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decoded", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / ".ios-work/ios-port/parity/android-inventory.json")
    args = parser.parse_args()
    print(json.dumps(inventory(args.decoded, args.output), indent=2))
