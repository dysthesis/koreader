#!/usr/bin/env python3
"""Collect KP measurements from shaped text; optionally invoke saved-data analysis."""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import posixpath
import random
import re
import shlex
import shutil
import subprocess
import unicodedata
from urllib.parse import unquote, urlsplit
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "base/thirdparty/kpvcrlib/crengine"


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def read_paragraphs(path, excluded):
    if path.suffix.lower() != ".epub":
        return list(enumerate(re.split(r"\n\s*\n", path.read_text(encoding="utf-8"))))
    paragraphs = []
    with zipfile.ZipFile(path) as archive:
        def xml(name):
            if archive.getinfo(name).file_size > 16 * 1024 * 1024:
                raise ValueError(f"EPUB member too large: {name}")
            return ET.fromstring(archive.read(name))
        container = xml("META-INF/container.xml")
        rootfile = container.find(".//{*}rootfile")
        if rootfile is None:
            raise ValueError("EPUB has no rootfile")
        opf_name = rootfile.attrib["full-path"]
        opf = xml(opf_name)
        manifest = {item.attrib["id"]: item.attrib["href"] for item in opf.findall("./{*}manifest/{*}item")}
        for ref in opf.findall("./{*}spine/{*}itemref"):
            if ref.get("linear") == "no":
                continue
            href = urlsplit(manifest[ref.attrib["idref"]])
            if href.scheme or href.netloc:
                raise ValueError("remote EPUB spine item")
            member = posixpath.normpath(posixpath.join(posixpath.dirname(opf_name), unquote(href.path)))
            try:
                page = xml(member)
            except ET.ParseError:
                excluded["invalid_xml_spine_items"] += 1
                continue
            for index, node in enumerate(page.findall(".//{*}p")):
                if any(child.tag.rsplit("}", 1)[-1] in ("img", "svg", "math", "br", "script", "style") for child in node.iter()):
                    excluded["non_prose_markup"] += 1
                    continue
                paragraphs.append((f"{member}:{index}", "".join(node.itertext())))
    return paragraphs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("corpus", type=Path, help="EPUB prose or UTF-8 text with blank-separated paragraphs")
    parser.add_argument("--output", type=Path, required=True, help="new directory; existing data is never overwritten")
    parser.add_argument("--font", type=Path, help="font file; defaults to installed Literata Regular via fontconfig")
    parser.add_argument("--collect-only", action="store_true", help="save measurements without importing or running analysis")
    parser.add_argument("--size", type=int, default=24)
    parser.add_argument("--widths", default="240:720:8", help="inclusive MIN:MAX:STEP in pixels")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--min-words", type=int, default=40)
    parser.add_argument("--max-words", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1729)
    parser.add_argument("--sanitize", action="store_true", help="ASan/UBSan correctness run; not performance comparable")
    parser.add_argument("--gprof", action="store_true", help="instrumented call profile; requires gprof; not performance comparable")
    args = parser.parse_args()
    try:
        low, high, step = map(int, args.widths.split(":"))
    except ValueError:
        parser.error("--widths must be MIN:MAX:STEP")
    if not (1 <= low <= high <= 10000 and 1 <= step <= 10000 and 1 <= args.size <= 256
            and 1 <= args.repeats <= 100 and 1 <= args.min_words <= args.max_words <= 2000 and args.limit > 0):
        parser.error("invalid range or count")
    if args.font is None:
        try:
            family, style, filename = command("fc-match", "-f", "%{family}\n%{style}\n%{file}", "Literata:style=Regular").splitlines()
        except (OSError, subprocess.CalledProcessError, ValueError):
            parser.error("cannot locate Literata Regular; supply --font /path/to/Literata-Regular.ttf")
        if "Literata" not in family.split(",") or style != "Regular":
            parser.error("Literata Regular is not installed; supply --font explicitly (no font substitution)")
        args.font = Path(filename)
    args.font = args.font.resolve()
    candidates = []
    excluded = defaultdict(int)
    for index, paragraph in read_paragraphs(args.corpus, excluded):
        text = " ".join(paragraph.split())
        if not args.min_words <= len(text.split()) <= args.max_words:
            excluded["word_count"] += 1
            continue
        # simplification: prose-only space breaks; use formatter item traces for CSS,
        # discretionary hyphenation, non-breaking spaces, bidi and contextual shaping.
        if any(unicodedata.bidirectional(c) in ("R", "AL", "AN")
               or unicodedata.category(c) in ("Cc", "Cf") or c in "\u00a0\u202f"
               for c in paragraph if c not in "\n\r\t"):
            excluded["unsupported_controls_or_spacing"] += 1
            continue
        candidates.append({"source_paragraph": index, "text": text})
    random.Random(args.seed).shuffle(candidates)
    selected = candidates[:args.limit]
    if not selected:
        parser.error("no eligible paragraphs")
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    paragraphs = "".join(p["text"] + "\n" for p in selected)
    (args.output / "paragraphs.txt").write_text(paragraphs, encoding="utf-8")
    flags = shlex.split(command("pkg-config", "--cflags", "--libs", "harfbuzz", "freetype2"))
    sources = [ROOT / "tools/kp-benchmark.cpp", ENGINE / "crengine/src/lvkplinebreak.cpp"]
    compiler = shutil.which("g++")
    if compiler is None:
        parser.error("g++ is required")
    build_flags = ["-std=c++17", "-O2", "-g", "-Wall", "-Wextra", "-Werror"]
    if args.sanitize:
        build_flags += ["-fsanitize=address,undefined", "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
    if args.gprof:
        build_flags += ["-pg"]
    binary = str(args.output.resolve() / "kp-benchmark")
    build = [compiler, *build_flags, *map(str, sources), *flags, "-o", binary]
    manifest = {
        "schema_version": 2,
        "adapter": "word-shaped-ltr-no-hyphenation-v1", "arguments": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.platform(), "compiler": command("g++", "--version"),
        "libraries": command("pkg-config", "--modversion", "harfbuzz", "freetype2"),
        "revision": command("git", "-C", str(ROOT), "rev-parse", "HEAD"),
        "engine_revision": command("git", "-C", str(ENGINE), "rev-parse", "HEAD"),
        "build": build, "eligible": len(candidates), "selected": len(selected), "excluded": dict(excluded),
        "selection": [{"source_paragraph": p["source_paragraph"], "sha256": hashlib.sha256(p["text"].encode()).hexdigest()} for p in selected],
        "sha256": {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.corpus, args.font, *sources, Path(__file__), ENGINE / "crengine/include/lvkplinebreak.h"]},
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (args.output / "compile_commands.json").write_text(json.dumps([
        {"directory": str(ROOT), "file": str(source),
         "arguments": [compiler, *build_flags, *[f for f in flags if f.startswith("-I")], "-c", str(source)]}
        for source in sources], indent=2) + "\n")
    subprocess.run(build, check=True)
    subprocess.run([binary, "--selfcheck"], cwd=args.output, check=True)
    with (args.output / "lines.jsonl").open("w") as out:
        subprocess.run([binary, str(args.font.resolve()), str(args.size), str(low), str(high), str(step), str(args.repeats)],
                       input=paragraphs, text=True, stdout=out, cwd=args.output, check=True, timeout=600)
    if args.gprof:
        (args.output / "gprof.txt").write_text(command("gprof", "-b", binary, str(args.output / "gmon.out")) + "\n")
    records = [json.loads(line) for line in (args.output / "lines.jsonl").read_text().splitlines()]
    manifest["shaping_exclusions"] = [r for r in records if "exclusion" in r]
    rows = [r for r in records if "algorithm" in r]
    manifest["measured_paragraphs"] = len(selected) - len(manifest["shaping_exclusions"])
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    assert len(rows) == manifest["measured_paragraphs"] * len(range(low, high + 1, step)) * 3
    if not rows:
        parser.error("all selected paragraphs failed shaping; see manifest.json")
    print("Collected", manifest["measured_paragraphs"], "paragraphs:", args.output)
    if not args.collect_only:
        from kp_benchmark_analysis import analyse
        analyse(args.output)


if __name__ == "__main__":
    main()
