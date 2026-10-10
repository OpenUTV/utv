#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Command line interface: list, gen, path, check, corrupt, doctor."""

import argparse
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

from . import corrupt as corrupt_mod
from .core import (
    MANIFEST_FILE,
    META_FILE,
    REGISTRY,
    BuildError,
    Context,
    default_output_dir,
    select,
    tool_versions,
    write_manifest,
)

EXAMPLES = """
examples:
  %(prog)s list                              every recipe, its tags, and whether this machine can build it
  %(prog)s list -t exr                       recipes tagged exr
  %(prog)s gen exr-multilayer prores-4444-alpha-mov
  %(prog)s gen -t smoke                      a quick cross-section of codecs and formats
  %(prog)s gen 'exr-half-*' --res 3840x2160 --frames 48
  %(prog)s gen png-6k-grain-seq --set pattern=bars
  %(prog)s gen -t corrupt && %(prog)s check -t corrupt
  utv "$(%(prog)s path exr-multilayer)"      open a generated item in UTV
  %(prog)s corrupt in.mov out.mov --op bitflip --count 500 --seed 7
"""


def parse_overrides(args):
    overrides = {}
    if getattr(args, "res", None):
        w, h = args.res.lower().split("x")
        overrides.update(width=int(w), height=int(h))
    for key in ("fps", "frames", "start", "seed", "pattern", "audio"):
        value = getattr(args, key, None)
        if value is not None:
            overrides[key] = value
    for item in getattr(args, "set", None) or []:
        if "=" not in item:
            raise SystemExit(f"--set expects KEY=VALUE, got {item!r}")
        key, value = item.split("=", 1)
        overrides[key] = value
    return overrides


def chosen(args):
    recipes = select(args.names, args.tag, args.exclude_tag)
    if not recipes:
        raise SystemExit("no recipes match; see `list`")
    return recipes


def cmd_list(args):
    recipes = select(args.names, args.tag, args.exclude_tag)
    if args.json:
        print(json.dumps([recipe_info(r) for r in recipes], indent=2))
        return 0
    width = max((len(r.name) for r in recipes), default=10)
    for r in recipes:
        missing = r.missing()
        mark = " " if not missing else "-"
        print(f"{mark} {r.name:{width}}  {r.help}")
        if args.verbose:
            print(f"  {'':{width}}  tags: {', '.join(sorted(r.tags))}")
            if missing:
                print(f"  {'':{width}}  needs: {'; '.join(m.label + ' (' + m.hint + ')' for m in missing)}")
    unavailable = sum(1 for r in recipes if r.missing())
    print(
        f"\n{len(recipes)} recipes"
        + (f", {unavailable} unavailable here (marked -; use -v for why)" if unavailable else "")
    )
    if not args.names and not args.tag:
        tags = sorted({t for r in REGISTRY.values() for t in r.tags})
        print("tags: " + ", ".join(tags))
    return 0


def recipe_info(r):
    return {
        "name": r.name,
        "help": r.help,
        "tags": sorted(r.tags),
        "defaults": r.params(),
        "available": not r.missing(),
        "missing": [m.label for m in r.missing()],
    }


def cmd_gen(args):
    ctx = Context(args.out, verbose=args.verbose, force=args.force)
    overrides = parse_overrides(args)
    recipes = chosen(args)
    os.makedirs(ctx.out_root, exist_ok=True)

    lock = threading.Lock()
    failures = []

    def build(r):
        if r.missing():
            with lock:
                print(f"skip   {r.name}: needs " + ", ".join(m.label for m in r.missing()), flush=True)
            return
        try:
            outdir, meta = ctx.ensure(r, overrides)
        except (BuildError, OSError) as exc:
            with lock:
                failures.append(r.name)
                print(f"FAIL   {r.name}: {exc}", flush=True)
            return
        with lock:
            mb = meta["bytes"] / 1e6
            print(f"ok     {r.name:34} {mb:9.1f} MB  {os.path.join(outdir, meta['path'])}", flush=True)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(build, recipes))

    write_manifest(ctx.out_root)
    print(f"\nmanifest: {os.path.join(ctx.out_root, MANIFEST_FILE)}")
    if failures:
        print(f"{len(failures)} failed: {', '.join(failures)}")
    return 1 if failures else 0


def cmd_path(args):
    ctx = Context(args.out)
    overrides = parse_overrides(args)
    for r in chosen(args):
        outdir = ctx.item_dir(r, r.params(overrides))
        meta_path = os.path.join(outdir, META_FILE)
        if not os.path.isfile(meta_path):
            if not args.build:
                print(f"{r.name} has not been generated; run `gen {r.name}` or pass --build", file=sys.stderr)
                return 1
            outdir, meta = ctx.ensure(r, overrides)
        else:
            with open(meta_path) as f:
                meta = json.load(f)
        print(os.path.join(outdir, meta["path"]))
    return 0


def cmd_check(args):
    from .check import default_bin_dir, run_checks

    manifest = write_manifest(os.path.abspath(args.out))
    items = manifest["items"]
    if args.names or args.tag or args.exclude_tag:
        wanted = {r.name for r in select(args.names, args.tag, args.exclude_tag)}
        items = [m for m in items if m["recipe"] in wanted]
    if not items:
        raise SystemExit("nothing generated matches; run `gen` first")
    failures = run_checks(items, os.path.abspath(args.out), args.bin_dir or default_bin_dir(), args.timeout, args.jobs)
    return 1 if failures else 0


def cmd_corrupt(args):
    fn, _ = corrupt_mod.OPS[args.op]
    if os.path.abspath(args.input) == os.path.abspath(args.output):
        raise SystemExit("output must differ from input; the input file is never modified")
    import shutil

    shutil.copyfile(args.input, args.output)
    kwargs = {}
    if args.op == "truncate" and args.fraction is not None:
        kwargs["fraction"] = args.fraction
    if args.op == "zero":
        if args.fraction is not None:
            kwargs["at"] = args.fraction
        if args.length is not None:
            kwargs["length"] = args.length
    if args.op == "bitflip":
        kwargs.update(seed=args.seed)
        if args.count is not None:
            kwargs["count"] = args.count
    if args.op == "garbage":
        kwargs.update(seed=args.seed)
        if args.offset is not None:
            kwargs["offset"] = args.offset
        if args.length is not None:
            kwargs["length"] = args.length
    fn(os.path.abspath(args.output), **kwargs)
    print(f"wrote {args.output} ({args.op} {kwargs})")
    return 0


def cmd_doctor(args):
    for name, version in tool_versions().items():
        print(f"{name:18} {version or 'not found'}")
    total = len(REGISTRY)
    ok = sum(1 for r in REGISTRY.values() if not r.missing())
    print(f"\n{ok} of {total} recipes can be built here")
    missing = {}
    for r in REGISTRY.values():
        for m in r.missing():
            missing.setdefault((m.label, m.hint), []).append(r.name)
    for (label, hint), names in sorted(missing.items()):
        print(f"  missing {label}: {hint}  ({len(names)} recipes)")
    print(f"\noutput directory: {args.out}")
    return 0


def add_selection(p):
    p.add_argument("names", nargs="*", help="recipe names or globs (e.g. 'exr-*'); all when omitted")
    p.add_argument("-t", "--tag", action="append", default=[], help="only recipes with this tag (repeatable: all)")
    p.add_argument("-x", "--exclude-tag", action="append", default=[], help="skip recipes with this tag")


def add_overrides(p):
    p.add_argument("--res", help="resolution as WIDTHxHEIGHT")
    p.add_argument("--fps", type=float)
    p.add_argument("--frames", type=int)
    p.add_argument("--start", type=int, help="first frame number for sequences (default 1001)")
    p.add_argument("--seed", type=int)
    p.add_argument("--pattern", help="counter, motion, bars, grain or gradient")
    p.add_argument("--audio", help="none, mono, stereo, 5.1 or 7.1")
    p.add_argument("--set", action="append", metavar="KEY=VALUE", help="override any recipe parameter")


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="utv_testmedia.py",
        description="Generate synthetic test media for UTV on demand.",
        epilog=EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-o", "--out", default=default_output_dir(), help="output root (default: %(default)s)")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("list", help="list recipes")
    add_selection(p)
    p.add_argument("-v", "--verbose", action="store_true", help="show tags and missing requirements")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("gen", help="generate media (cached: unchanged recipes are not rebuilt)")
    add_selection(p)
    add_overrides(p)
    p.add_argument("-f", "--force", action="store_true", help="rebuild even if cached")
    p.add_argument("-j", "--jobs", type=int, default=2, help="recipes built in parallel (default 2)")
    p.add_argument("-v", "--verbose", action="store_true", help="print every command")
    p.set_defaults(fn=cmd_gen)

    p = sub.add_parser("path", help="print the path to hand to UTV for generated items")
    add_selection(p)
    add_overrides(p)
    p.add_argument("--build", action="store_true", help="generate the item first if needed")
    p.set_defaults(fn=cmd_path, verbose=False, force=False)

    p = sub.add_parser("check", help="decode generated items with utvio; fail on crashes, hangs and bad decodes")
    add_selection(p)
    p.add_argument("--bin-dir", help="folder containing utvio (default: the installed UTV)")
    p.add_argument("--timeout", type=int, default=300, help="seconds per item (default 300)")
    p.add_argument("-j", "--jobs", type=int, default=2)
    p.set_defaults(fn=cmd_check)

    ops = "\n".join(f"  {name:9} {desc}" for name, (_fn, desc) in corrupt_mod.OPS.items())
    p = sub.add_parser(
        "corrupt",
        help="write a damaged copy of any file",
        epilog="operations:\n" + ops,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--op", choices=sorted(corrupt_mod.OPS), required=True)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--count", type=int)
    p.add_argument("--fraction", type=float)
    p.add_argument("--offset", type=int)
    p.add_argument("--length", type=int)
    p.set_defaults(fn=cmd_corrupt)

    p = sub.add_parser("doctor", help="show tool versions and which recipes this machine can build")
    p.set_defaults(fn=cmd_doctor)

    args = parser.parse_args(argv)
    return args.fn(args)
