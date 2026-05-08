#!/usr/bin/env python3
# bundle_dylibs.py <exe> <frameworks_dir>
# Discovers all non-system Homebrew dylibs the binary (transitively) depends on,
# copies them into frameworks_dir, and rewrites all load commands to use
# @executable_path/../Frameworks (for the exe) or @loader_path (for dylibs).

import os
import shutil
import subprocess
import sys
from collections import deque


def otool_deps(path, skip_id=False):
    out = subprocess.check_output(["otool", "-L", path], text=True)
    lines = out.splitlines()[1:]  # drop the object name line
    if skip_id and lines:
        lines = lines[1:]  # first entry is the dylib's own install name
    deps = []
    for line in lines:
        dep = line.strip().split(" (")[0]
        if dep:
            deps.append(dep)
    return deps


def original_install_name(path):
    out = subprocess.check_output(["otool", "-L", path], text=True)
    lines = out.splitlines()
    if len(lines) < 2:
        return None
    return lines[1].strip().split(" (")[0]


def resolve_dep(dep, obj, skip_id=False):
    if dep.startswith("@loader_path/"):
        suffix = dep[len("@loader_path/"):]
        candidate = os.path.join(os.path.dirname(obj), suffix)
        if os.path.isfile(candidate):
            return candidate
        if skip_id:
            install_name = original_install_name(obj)
            if install_name and install_name.startswith("/"):
                candidate = os.path.join(os.path.dirname(install_name), suffix)
                if os.path.isfile(candidate):
                    return candidate
        return None
    if dep.startswith("/"):
        return dep
    return None


def should_bundle(path):
    if path is None:
        return False
    skip_prefixes = ("/usr/lib/", "/System/Library/")
    if any(path.startswith(p) for p in skip_prefixes):
        return False
    return os.path.isfile(path)


def bundle(exe, frameworks_dir):
    os.makedirs(frameworks_dir, exist_ok=True)

    queue = deque([exe])
    copied = []

    while queue:
        cur = queue.popleft()
        is_dylib = cur.startswith(frameworks_dir + os.sep)
        for dep in otool_deps(cur, skip_id=is_dylib):
            resolved = resolve_dep(dep, cur, skip_id=is_dylib)
            if resolved is None or not should_bundle(resolved):
                continue
            dst = os.path.join(frameworks_dir, os.path.basename(dep))
            if not os.path.exists(dst):
                shutil.copy2(resolved, dst)
                os.chmod(dst, os.stat(dst).st_mode | 0o200)
                copied.append(dst)
                queue.append(dst)

    def rewrite_refs(obj, ref_prefix, skip_id=False):
        for dep in otool_deps(obj, skip_id=skip_id):
            resolved = resolve_dep(dep, obj, skip_id=skip_id)
            if resolved is None or not should_bundle(resolved):
                continue
            name = os.path.basename(dep)
            new_dep = f"{ref_prefix}/{name}"
            if dep != new_dep and os.path.exists(os.path.join(frameworks_dir, name)):
                subprocess.check_call([
                    "install_name_tool", "-change", dep,
                    new_dep, obj
                ])

    rewrite_refs(exe, "@executable_path/../Frameworks", skip_id=False)
    for dylib in copied:
        rewrite_refs(dylib, "@loader_path", skip_id=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <exe> <frameworks_dir>", file=sys.stderr)
        sys.exit(1)
    bundle(sys.argv[1], sys.argv[2])
