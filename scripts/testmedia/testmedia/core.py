#
# Copyright (C) 2026  Contributors to the OpenUTV Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Recipe registry, requirements, parameters and the build cache."""

import fnmatch
import functools
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field

# Common parameters every recipe accepts. Recipes override the defaults they care about and may add their own keys.
COMMON_DEFAULTS = {
    "width": 1920,
    "height": 1080,
    "fps": 24.0,
    "frames": 24,
    "start": 1001,
    "seed": 1,
}

META_FILE = "meta.json"
MANIFEST_FILE = "manifest.json"


def default_output_dir():
    if os.environ.get("UTV_TESTMEDIA_DIR"):
        return os.environ["UTV_TESTMEDIA_DIR"]
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
        return os.path.join(base, "utv-testmedia")
    return os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "utv-testmedia")


# --------------------------------------------------------------------------------------------------------------------
# External tools and requirements
# --------------------------------------------------------------------------------------------------------------------


@functools.cache
def which(tool):
    return shutil.which(tool)


@functools.cache
def _capture(*cmd):
    if not which(cmd[0]):
        return ""
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, check=False)
    return proc.stdout.decode("utf-8", errors="replace")


@functools.cache
def ffmpeg_encoders():
    names = set()
    for line in _capture("ffmpeg", "-hide_banner", "-encoders").splitlines():
        parts = line.split()
        # Encoder lines look like " V....D libx264  description"; the flag column is six characters.
        if len(parts) >= 2 and len(parts[0]) == 6 and parts[0][0] in "VAS":
            names.add(parts[1])
    return names


@functools.cache
def ffmpeg_filters():
    names = set()
    for line in _capture("ffmpeg", "-hide_banner", "-filters").splitlines():
        parts = line.split()
        if len(parts) >= 3 and "->" in parts[2]:
            names.add(parts[1])
    return names


@functools.cache
def oiio_output_formats():
    for line in _capture("oiiotool", "--help").splitlines():
        if line.startswith("Output formats supported:"):
            return {f.strip() for f in line.split(":", 1)[1].split(",")}
    return set()


def tool_versions():
    versions = {}
    first = _capture("ffmpeg", "-hide_banner", "-version").splitlines()
    versions["ffmpeg"] = first[0] if first else None
    versions["oiiotool"] = _capture("oiiotool", "--version").strip() or None
    if importlib.util.find_spec("OpenEXR"):
        import OpenEXR

        versions["OpenEXR (python)"] = getattr(OpenEXR, "__version__", "installed")
    else:
        versions["OpenEXR (python)"] = None
    return versions


@dataclass(frozen=True)
class Requirement:
    label: str
    check: object  # callable() -> bool
    hint: str = ""

    def satisfied(self):
        return bool(self.check())


def tool(name, hint=""):
    return Requirement(name, lambda: which(name) is not None, hint or f"install {name} and put it on PATH")


def ffmpeg_encoder(name):
    return Requirement(f"ffmpeg:{name}", lambda: name in ffmpeg_encoders(), f"ffmpeg built with the {name} encoder")


def ffmpeg_filter(name):
    return Requirement(
        f"ffmpeg-filter:{name}", lambda: name in ffmpeg_filters(), f"ffmpeg built with the {name} filter"
    )


def oiio_format(name):
    return Requirement(f"oiio:{name}", lambda: name in oiio_output_formats(), f"oiiotool built with {name} output")


def py_module(name):
    return Requirement(
        f"python:{name}",
        lambda: importlib.util.find_spec(name) is not None,
        f"`pip install {name}` into the Python that runs this tool",
    )


FFMPEG = tool("ffmpeg", "install ffmpeg (brew install ffmpeg / apt install ffmpeg / winget install ffmpeg)")
OIIOTOOL = tool("oiiotool", "install OpenImageIO tools (brew install openimageio / apt install openimageio-tools)")


# --------------------------------------------------------------------------------------------------------------------
# Recipes
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Result:
    """What a recipe produced.

    `path` is relative to the recipe's output directory and is what you hand to UTV: a file name, or for sequences an
    RV-style pattern such as ``beauty.1001-1024#.exr``. `expect` records the properties a reader should see, and
    `corrupt` marks media that is deliberately broken (a reader may refuse it, but must not crash or hang).
    """

    path: str
    expect: dict = field(default_factory=dict)
    corrupt: bool = False
    notes: str = ""


@dataclass
class Recipe:
    name: str
    help: str
    tags: frozenset
    needs: tuple
    defaults: dict
    build: object  # callable(ctx, params, outdir) -> Result
    rev: int = 1  # bump to invalidate cached outputs when the recipe's output changes

    def missing(self):
        return [r for r in self.needs if not r.satisfied()]

    def params(self, overrides=None):
        p = dict(COMMON_DEFAULTS)
        p.update(self.defaults)
        for key, value in (overrides or {}).items():
            if key in p and p[key] is not None and not isinstance(value, type(p[key])):
                value = coerce(value, type(p[key]))
            p[key] = value
        return p


REGISTRY = {}


def recipe(name, help, tags=(), needs=(), rev=1, **defaults):
    """Register a build function as a recipe. Keyword arguments become the recipe's default parameters."""

    def wrap(fn):
        register(Recipe(name, help, frozenset(tags), tuple(needs), defaults, fn, rev))
        return fn

    return wrap


def register(r):
    if r.name in REGISTRY:
        raise ValueError(f"duplicate recipe name: {r.name}")
    REGISTRY[r.name] = r
    return r


def coerce(value, kind):
    if kind is bool:
        return str(value).lower() in ("1", "true", "yes", "on")
    return kind(value)


def select(patterns=(), tags=(), exclude_tags=()):
    """Recipes matching any name glob in `patterns` and every tag in `tags` (all recipes when both are empty)."""
    chosen = []
    for r in REGISTRY.values():
        if patterns and not any(fnmatch.fnmatchcase(r.name, p) for p in patterns):
            continue
        if tags and not set(tags) <= r.tags:
            continue
        if set(exclude_tags) & r.tags:
            continue
        chosen.append(r)
    return chosen


# --------------------------------------------------------------------------------------------------------------------
# Build context and cache
# --------------------------------------------------------------------------------------------------------------------


class BuildError(RuntimeError):
    pass


class Context:
    def __init__(self, out_root, verbose=False, force=False):
        self.out_root = os.path.abspath(out_root)
        self.verbose = verbose
        self.force = force
        self._locks = {}
        self._locks_guard = threading.Lock()
        self._built = set()  # items rebuilt by this run, so --force rebuilds each one once

    def log(self, msg):
        print(msg, flush=True)

    def run(self, cmd, **kwargs):
        cmd = [str(c) for c in cmd]
        if self.verbose:
            self.log("  $ " + " ".join(_quote(c) for c in cmd))
        proc = subprocess.run(
            cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False, **kwargs
        )
        if proc.returncode != 0:
            out = proc.stdout.decode("utf-8", errors="replace").strip().splitlines()
            tail = "\n".join(out[-15:])
            raise BuildError(f"{os.path.basename(cmd[0])} exited {proc.returncode}:\n{tail}")
        return proc.stdout.decode("utf-8", errors="replace")

    def item_dir(self, r, params):
        return os.path.join(self.out_root, item_name(r, params))

    def ensure(self, r, overrides=None):
        """Build recipe `r` unless an up-to-date copy is cached. Returns (outdir, meta dict)."""
        params = r.params(overrides)
        outdir = self.item_dir(r, params)
        with self._locks_guard:
            lock = self._locks.setdefault(outdir, threading.Lock())
        # Corrupt recipes build their clean base through ensure(), possibly while another worker builds it too.
        with lock:
            return self._ensure_locked(r, params, outdir)

    def _ensure_locked(self, r, params, outdir):
        meta_path = os.path.join(outdir, META_FILE)
        stamp = {"recipe": r.name, "rev": r.rev, "params": params}

        if (not self.force or outdir in self._built) and os.path.isfile(meta_path):
            with open(meta_path) as f:
                meta = json.load(f)
            if all(meta.get(k) == v for k, v in stamp.items()):
                return outdir, meta

        missing = r.missing()
        if missing:
            raise BuildError("missing " + ", ".join(f"{m.label} ({m.hint})" for m in missing))

        # Build into a sibling staging directory and swap it in, so an interrupted build never looks cached.
        staging = outdir + ".partial"
        _remove_tree(staging)
        os.makedirs(staging)
        started = time.time()
        result = r.build(self, params, staging)
        if not isinstance(result, Result):
            raise BuildError(f"recipe {r.name} returned {type(result).__name__}, expected Result")

        meta = dict(stamp)
        meta.update(
            {
                "path": result.path,
                "expect": result.expect,
                "corrupt": result.corrupt,
                "notes": result.notes,
                "tags": sorted(r.tags),
                "help": r.help,
                "seconds": round(time.time() - started, 2),
                "bytes": _tree_size(staging),
            }
        )
        with open(os.path.join(staging, META_FILE), "w") as f:
            json.dump(meta, f, indent=2)

        _remove_tree(outdir)
        os.replace(staging, outdir)
        self._built.add(outdir)
        return outdir, meta


def item_name(r, params):
    base = r.params()
    changed = {k: v for k, v in params.items() if base.get(k) != v}
    if not changed:
        return r.name
    digest = hashlib.sha1(json.dumps(changed, sort_keys=True).encode()).hexdigest()[:8]
    return f"{r.name}--{digest}"


def write_manifest(out_root):
    """Collect every cached item's meta.json into one manifest for test harnesses to consume."""
    items = []
    if os.path.isdir(out_root):
        for entry in sorted(os.listdir(out_root)):
            meta_path = os.path.join(out_root, entry, META_FILE)
            if os.path.isfile(meta_path):
                with open(meta_path) as f:
                    meta = json.load(f)
                meta["dir"] = entry
                items.append(meta)
    manifest = {"generated": time.strftime("%Y-%m-%dT%H:%M:%S"), "tools": tool_versions(), "items": items}
    with open(os.path.join(out_root, MANIFEST_FILE), "w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def _remove_tree(path):
    # Only ever removes a recipe output directory (or its staging copy) that this tool created: refuse anything else.
    if not os.path.exists(path):
        return
    if not (os.path.isfile(os.path.join(path, META_FILE)) or path.endswith(".partial")):
        raise BuildError(f"refusing to replace {path}: it is not a utv-testmedia output directory")
    shutil.rmtree(path)


def _tree_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        total += sum(os.path.getsize(os.path.join(root, f)) for f in files)
    return total


def _quote(arg):
    return f'"{arg}"' if (" " in arg or not arg) else arg


def seq_pattern(prefix, ext, start, frames, pad=4):
    """RV-style sequence spec, e.g. ``name.1001-1024#.exr`` (``#`` is four-digit padding, ``@`` one digit)."""
    marker = "#" if pad == 4 else "@" * pad
    return f"{prefix}.{start}-{start + frames - 1}{marker}.{ext}"


def frame_file(prefix, ext, frame, pad=4):
    return f"{prefix}.{frame:0{pad}d}.{ext}"
