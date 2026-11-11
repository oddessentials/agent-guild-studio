"""Builds Studio's art packs from an Agent Guild: World checkout whose art is fetched and imported.

    python tools/pack_art.py <agent-guild-steam checkout> [--godot=godot] [--only=guild,helpers]

Each pack is a Godot resource pack holding World's own imported models, so they
load in Studio exactly as World loads them: one per world (its 18 characters,
station and clip set) and one for the helpers every world shares. Writes the
packs to build/packs and names them, with sizes and checksums, in
art/art-lock.json. Upload them to this repository's `art` release.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "packs"
LOCK = ROOT / "art" / "art-lock.json"
RELEASE = "art"
WORLDS = ["guild", "orbital", "grove", "professional", "goblinville", "gnomeland"]
PRESET = """[preset.0]

name="Pack"
platform="Windows Desktop"
runnable=false
export_filter="all_resources"
include_filter="assets/packs/*.json"
exclude_filter=""
export_path=""

[preset.0.options]

binary_format/embed_pck=false
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
"""


def sources(manifest, pack):
    """The source files (not their imports) a pack holds, by World's art units."""
    units = {u["name"]: [f for f in u["files"] if not f.startswith(".godot/")] for u in manifest["units"]}
    if pack == "helpers":
        return units["premium/helpers"]
    station = [f for f in units["models"] if Path(f).name.startswith(pack + "_station")]
    clips = [f for f in units["premium/studio"] if Path(f).name.startswith(pack + ".glb")]
    if not station or not clips:
        sys.exit(f"{pack}: its station or clip set is not in World's art")
    return units["premium/" + pack] + station + clips


def imported(world, import_file):
    text = (world / import_file).read_text(encoding="utf-8")
    line = re.search(r"^dest_files=.*$", text, re.M)
    dests = re.findall(r'"res://(\.godot/imported/[^"]+)"', line[0]) if line else []
    record = re.match(r"(.*-[0-9a-f]{32})\.", dests[0])[1] + ".md5" if dests else None
    uid = re.search(r'^uid="(uid://[^"]+)"', text, re.M)
    return dests + ([record] if record else []), uid[1] if uid else None


def build(world, manifest, pack, godot):
    maker = OUT / "maker"
    shutil.rmtree(maker, ignore_errors=True)
    maker.mkdir(parents=True)
    ids = []
    for rel in sources(manifest, pack):
        files = [rel]
        if rel.endswith(".import"):
            more, uid = imported(world, rel)
            files += more
            if uid:
                ids.append([uid, "res://" + rel[: -len(".import")]])
        for f in files:
            if not (world / f).is_file():
                sys.exit(f"{pack}: {f} is missing from the World checkout; fetch and import its art first")
            (maker / f).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(world / f, maker / f)
    (maker / "assets/packs").mkdir(parents=True, exist_ok=True)
    (maker / f"assets/packs/{pack}.json").write_text(json.dumps(sorted(ids)), encoding="utf-8", newline="\n")
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    keep = [s for s in re.split(r"(?m)^(?=\[)", project) if s.startswith(("[rendering]", "[importer_defaults]"))]
    (maker / "project.godot").write_text(
        'config_version=5\n\n[application]\n\nconfig/name="art"\nconfig/features=PackedStringArray("4.7", "Forward Plus")\n\n' + "".join(keep),
        encoding="utf-8", newline="\n")
    (maker / "export_presets.cfg").write_text(PRESET, encoding="utf-8", newline="\n")
    draft = OUT / "draft.zip"
    draft.unlink(missing_ok=True)
    run = subprocess.run([godot, "--headless", "--path", str(maker), "--export-pack", "Pack", str(draft)], capture_output=True, text=True)
    if run.returncode != 0 or not draft.is_file() or "reimport" in run.stdout.lower():
        sys.exit(f"{pack}: the pack was not exported, or Godot imported the art again:\n{run.stdout[-2000:]}\n{run.stderr[-2000:]}")
    digest = hashlib.sha256()
    with open(draft, "rb") as f:
        while chunk := f.read(8 << 20):
            digest.update(chunk)
    name = f"art-{pack}-{digest.hexdigest()[:16]}.zip"
    for old in OUT.glob(f"art-{pack}-*.zip"):
        old.unlink()
    draft.replace(OUT / name)
    shutil.rmtree(maker)
    return {"asset": name, "size": (OUT / name).stat().st_size, "sha256": digest.hexdigest()}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    options = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if len(args) != 1:
        sys.exit(__doc__)
    world = Path(args[0]).resolve()
    manifest = json.loads((world / "art-pack.json").read_text(encoding="utf-8"))
    lock = json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.is_file() else {"release": RELEASE, "packs": {}}
    lock["release"] = RELEASE
    lock["art"] = manifest["version"]
    OUT.mkdir(parents=True, exist_ok=True)
    for pack in options.get("only", ",".join(WORLDS + ["helpers"])).split(","):
        lock["packs"][pack] = build(world, manifest, pack, options.get("godot", "godot"))
        print(f"{pack}: {lock['packs'][pack]['asset']}, {lock['packs'][pack]['size'] / 2**20:.0f} MB", flush=True)
        LOCK.parent.mkdir(exist_ok=True)
        LOCK.write_text(json.dumps(lock, indent=1) + "\n", encoding="utf-8", newline="\n")


main()
