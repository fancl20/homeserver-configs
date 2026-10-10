"""Prepare a build context from a Flux source artifact.

Runs as the init container of a build Job: downloads the source-controller
artifact, verifies its digest, untars it safely, runs the optional update
command, renders the tag template, and writes the tag for the build container.

Failure messages use stable markers ("artifact fetch failed", "digest
mismatch") that the controller matches to self-heal when an artifact revision
is garbage-collected mid-build.
"""

import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile
import urllib.request

MAX_ARTIFACT_BYTES = 2 * 1024 * 1024 * 1024  # 2 GiB, far above this repo


def die(message):
    print(message, file=sys.stderr)
    # Surface the marker on the container status, not only in the logs: the
    # controller reads init-container termination messages to self-heal
    # artifact GC. No-op when not running under kubelet (tests).
    try:
        pathlib.Path("/dev/termination-log").write_text(message)
    except OSError:
        pass
    sys.exit(1)


def fetch_artifact(url, digest):
    buf = io.BytesIO()
    try:
        with urllib.request.urlopen(url, timeout=300) as response:
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                buf.write(chunk)
                if buf.tell() > MAX_ARTIFACT_BYTES:
                    die("artifact fetch failed: artifact exceeds size limit")
    except Exception as exc:  # noqa: BLE001 - any transport error is fatal
        die(f"artifact fetch failed: {exc}")

    if digest:
        algorithm, _, expected = digest.partition(":")
        try:
            actual = hashlib.new(algorithm, buf.getvalue()).hexdigest()
        except ValueError:
            die(f"digest mismatch: unsupported algorithm {algorithm!r}")
        if actual != expected:
            die(f"digest mismatch: artifact {algorithm} does not match the source status")
    return buf


def extract_artifact(buf, dest):
    buf.seek(0)
    try:
        with tarfile.open(fileobj=buf, mode="r:gz") as archive:
            for member in archive.getmembers():
                name = os.path.normpath(member.name)
                parts = pathlib.PurePosixPath(name).parts
                if name.startswith("/") or name.startswith("..") or ".." in parts:
                    die(f"artifact fetch failed: unsafe path in artifact: {member.name}")
            # filter="data" neutralizes links that escape the extraction root
            # (and devices); in-tree symlinks are legit repo content.
            archive.extractall(dest, filter="data")
    except tarfile.TarError as exc:
        die(f"artifact fetch failed: bad tarball: {exc}")


def resolve_context(root, relative):
    context = (root / relative).resolve()
    if context != root and not str(context).startswith(str(root) + os.sep):
        die(f"context escapes source: {relative}")
    return context


def render_tag(template, variables):
    # Any whitespace inside the braces is accepted, mirroring the controller's
    # tagVarPattern so a spec that passes validation always renders.
    for key, value in variables.items():
        template = re.sub(
            r"\{\{\s*" + re.escape(key) + r"\s*\}\}",
            lambda _m, value=value: value,
            template,
        )
    if "{{" in template or "}}" in template:
        die(f"unresolved template variable in tag: {template!r}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,127}", template):
        die(f"invalid tag: {template!r}")
    return template


def main():
    source_dir = pathlib.Path(os.environ.get("SOURCE_DIR", "/work/src"))
    out_dir = pathlib.Path(os.environ.get("OUT_DIR", "/work/out"))
    out_dir.mkdir(parents=True, exist_ok=True)

    context = resolve_context(source_dir, os.environ.get("CONTEXT", "."))

    buf = fetch_artifact(os.environ["ARTIFACT_URL"], os.environ.get("ARTIFACT_DIGEST", ""))
    extract_artifact(buf, source_dir)

    if not (context / "Dockerfile").is_file():
        die(f"no Dockerfile at {os.environ.get('CONTEXT', '.')}")

    update_command = os.environ.get("UPDATE_CMD", "")
    if update_command:
        result = subprocess.run(json.loads(update_command), cwd=context)
        if result.returncode != 0:
            die(f"update command failed with exit code {result.returncode}")

    version = os.environ.get("VERSION_LITERAL", "")
    version_file = os.environ.get("VERSION_FILE", "")
    if version_file:
        version = (context / version_file).read_text().strip()
        if not version:
            die(f"empty version file: {version_file}")

    tag = render_tag(os.environ["TAG"], {
        "base": os.environ.get("VAR_BASE", ""),
        "sha": os.environ.get("VAR_SHA", ""),
        "date": os.environ.get("VAR_DATE", ""),
        "version": version,
    })

    (out_dir / "tag").write_text(tag)
    print(f"prepare: tag {tag}")


if __name__ == "__main__":
    main()
