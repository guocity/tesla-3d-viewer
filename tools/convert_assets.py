#!/usr/bin/env python3
"""Convert extracted Tesla Godot 3 (.scn, .mesh, .tscn) 3D assets into standard glTF 2.0 Binary (.glb) files.

Uses Python standard library + numpy for fast vectorized vertex/normal/UV decoding and glTF 2.0 binary packing.
Outputs source-linked .glb files and catalog.json into tesla-3d-viewer/models/.
"""
from __future__ import annotations


import json
import os
import ctypes
import ctypes.util
from functools import lru_cache
import math
import re
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
EXTRACTED_ROOT = Path(os.environ.get("TESLA_EXTRACTED_ROOT", str(ROOT / "extracted_models")))
REA_GODOT_ROOT = Path(os.environ.get("TESLA_GODOT_ROOT", str(EXTRACTED_ROOT)))
OUT_DIR = ROOT / "tesla-3d-viewer" / "models"


# Build a global lookup from Godot `res://...` source path -> compiled `.scn` or `.mesh` path
def build_import_map():
    import_map = {}
    search_roots = [EXTRACTED_ROOT, REA_GODOT_ROOT]
    for sroot in search_roots:
        if not sroot.exists():
            continue
        for imp in sroot.rglob("*.import"):
            if not imp.is_file():
                continue
            txt = imp.read_text(errors="ignore")
            m_src = re.search(r'source_file="([^"]+)"', txt)
            m_path = re.search(r'path(?:\.etc)?="([^"]+)"', txt)
            if m_path:
                rel_target = m_path.group(1).removeprefix("res://")
                for cand_root in search_roots:
                    cand = cand_root / rel_target
                    if cand.exists():
                        if m_src:
                            import_map[m_src.group(1)] = cand
                        # Also map by relative path without .import
                        try:
                            rel_imp = "res://" + str(imp.relative_to(sroot)).removesuffix(".import")
                            import_map[rel_imp] = cand
                        except Exception:
                            pass
                        break
    return import_map


IMPORT_MAP = build_import_map()


def resolve_res_path(res_path: str) -> Path | None:
    if res_path in IMPORT_MAP:
        return IMPORT_MAP[res_path]
    rel = res_path.removeprefix("res://")
    for base in [EXTRACTED_ROOT, EXTRACTED_ROOT / "models_by_vehicle", REA_GODOT_ROOT]:
        p = base / rel
        if p.exists() and p.is_file():
            return p
        for ext in [".scn", ".mesh"]:
            p2 = base / Path(rel).with_suffix(ext)
            if p2.exists() and p2.is_file():
                return p2
    return None


def parse_rsrc_file(path: Path):
    """Parse a Godot 3.x RSRC binary file (.scn or .mesh)."""
    data = path.read_bytes()
    compressed = data[:4] == b"RSCC"
    if compressed:
        mode, block_size, total = struct.unpack_from("<III", data, 4)
        if mode != 2:
            raise ValueError(f"Unsupported Godot compression {mode}")
        count = total // block_size + 1
        sizes = struct.unpack_from(f"<{count}I", data, 16)
        zstd = ctypes.CDLL(ctypes.util.find_library("zstd") or "/opt/homebrew/lib/libzstd.dylib")
        zstd.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        zstd.ZSTD_decompress.restype = ctypes.c_size_t
        offset = 16 + count * 4
        chunks = []
        for size in sizes:
            dst = ctypes.create_string_buffer(block_size)
            n = zstd.ZSTD_decompress(dst, block_size, data[offset:offset+size], size)
            if n > block_size:
                raise ValueError("Invalid Zstandard resource block")
            chunks.append(dst.raw[:n]); offset += size
        data = b"RSRC" + b"".join(chunks)[:total]
    if data[:4] != b"RSRC":
        raise ValueError(f"Not an RSRC file: {path}")

    pos = 24
    strlen = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    res_type = data[pos:pos + strlen].decode("utf-8", errors="replace").rstrip("\x00")
    pos += strlen + 64

    scnt = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    strings = []
    for _ in range(scnt):
        slen = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 4
        strings.append(data[pos:pos + slen].decode("utf-8", errors="replace").rstrip("\x00"))
        pos += slen

    ecnt = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    ext_res = []
    for _ in range(ecnt):
        slen = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 4
        etype = data[pos:pos + slen].decode("utf-8", errors="replace").rstrip("\x00")
        pos += slen
        slen = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 4
        epath = data[pos:pos + slen].decode("utf-8", errors="replace").rstrip("\x00")
        pos += slen
        ext_res.append((etype, epath))

    icnt = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    int_res_offsets = []
    for _ in range(icnt):
        slen = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 4
        epath = data[pos:pos + slen].decode("utf-8", errors="replace").rstrip("\x00")
        pos += slen
        ofs = struct.unpack("<Q", data[pos:pos + 8])[0]
        pos += 8
        int_res_offsets.append((epath, ofs + (4 if compressed else 0)))

    def get_ustring(p):
        slen = struct.unpack("<I", data[p:p + 4])[0]
        p += 4
        return data[p:p + slen].decode("utf-8", errors="replace").rstrip("\x00"), p + slen

    def get_name(p):
        idx = struct.unpack("<I", data[p:p + 4])[0]
        p += 4
        if idx & 0x80000000:
            slen = idx & 0x7FFFFFFF
            return data[p:p + slen].decode("utf-8", errors="replace").rstrip("\x00"), p + slen
        return strings[idx], p

    def parse_variant(p):
        vtype = struct.unpack("<I", data[p:p + 4])[0]
        p += 4
        if vtype == 1:
            return None, p
        elif vtype == 2:
            return bool(struct.unpack("<I", data[p:p + 4])[0]), p + 4
        elif vtype == 3:
            return struct.unpack("<i", data[p:p + 4])[0], p + 4
        elif vtype == 4:
            return struct.unpack("<f", data[p:p + 4])[0], p + 4
        elif vtype == 5:
            return get_ustring(p)
        elif vtype == 10:
            return struct.unpack("<2f", data[p:p + 8]), p + 8
        elif vtype == 11:
            return struct.unpack("<4f", data[p:p + 16]), p + 16
        elif vtype == 12:
            return struct.unpack("<3f", data[p:p + 12]), p + 12
        elif vtype == 13:
            return struct.unpack("<4f", data[p:p + 16]), p + 16
        elif vtype == 14:
            return struct.unpack("<4f", data[p:p + 16]), p + 16
        elif vtype == 15:
            return struct.unpack("<6f", data[p:p + 24]), p + 24
        elif vtype == 16:
            return struct.unpack("<9f", data[p:p + 36]), p + 36
        elif vtype == 17:
            return struct.unpack("<12f", data[p:p + 48]), p + 48
        elif vtype == 18:
            return struct.unpack("<6f", data[p:p + 24]), p + 24
        elif vtype == 20:
            return struct.unpack("<4f", data[p:p + 16]), p + 16
        elif vtype == 22:
            np_counts = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            if np_counts & 0x80000000:
                name_cnt = np_counts & 0x7FFFFFFF
                sub_cnt = struct.unpack("<I", data[p:p + 4])[0]
                p += 4
                flags = struct.unpack("<I", data[p:p + 4])[0]
                p += 4
                names = []
                for _ in range(name_cnt + sub_cnt):
                    nm, p = get_name(p)
                    names.append(nm)
                return ("NodePath", names, flags), p
            return get_ustring(p - 4)
        elif vtype == 23:
            return ("RID",), p
        elif vtype == 24:
            obj_mode = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            if obj_mode == 0:
                return None, p
            elif obj_mode == 1:
                t, p = get_ustring(p)
                path_s, p = get_ustring(p)
                return ("ExtResourcePath", t, path_s), p
            elif obj_mode == 2:
                idx = struct.unpack("<I", data[p:p + 4])[0]
                return ("SubResource", idx), p + 4
            elif obj_mode == 3:
                idx = struct.unpack("<I", data[p:p + 4])[0]
                return ("ExtResource", idx), p + 4
            else:
                raise ValueError(f"Unknown obj_mode {obj_mode}")
        elif vtype == 26:
            cnt = struct.unpack("<I", data[p:p + 4])[0] & 0x7FFFFFFF
            p += 4
            d = {}
            for _ in range(cnt):
                k, p = parse_variant(p)
                v, p = parse_variant(p)
                d[k] = v
            return d, p
        elif vtype == 30:
            cnt = struct.unpack("<I", data[p:p + 4])[0] & 0x7FFFFFFF
            p += 4
            arr = []
            for _ in range(cnt):
                v, p = parse_variant(p)
                arr.append(v)
            return arr, p
        elif vtype == 31:
            blen = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            b = data[p:p + blen]
            p += blen + ((4 - (blen % 4)) % 4)
            return b, p
        elif vtype == 32:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            return struct.unpack(f"<{cnt}i", data[p:p + cnt * 4]), p + cnt * 4
        elif vtype == 33:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            return struct.unpack(f"<{cnt}f", data[p:p + cnt * 4]), p + cnt * 4
        elif vtype == 34:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            arr = []
            for _ in range(cnt):
                s, p = get_ustring(p)
                arr.append(s)
            return arr, p
        elif vtype == 35:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            return struct.unpack(f"<{cnt * 3}f", data[p:p + cnt * 12]), p + cnt * 12
        elif vtype == 36:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            return struct.unpack(f"<{cnt * 4}f", data[p:p + cnt * 16]), p + cnt * 16
        elif vtype == 37:
            cnt = struct.unpack("<I", data[p:p + 4])[0]
            p += 4
            return struct.unpack(f"<{cnt * 2}f", data[p:p + cnt * 8]), p + cnt * 8
        elif vtype == 40:
            return struct.unpack("<q", data[p:p + 8])[0], p + 8
        elif vtype == 41:
            return struct.unpack("<d", data[p:p + 8])[0], p + 8
        else:
            raise ValueError(f"Unknown vtype {vtype} at {p}")

    resources = {}
    for i, (epath, ofs) in enumerate(int_res_offsets):
        rtype, p = get_ustring(ofs)
        pcnt = struct.unpack("<I", data[p:p + 4])[0]
        p += 4
        props = {}
        for _ in range(pcnt):
            k, p = get_name(p)
            v, p = parse_variant(p)
            props[k] = v
        m_id = re.search(r"local://(\d+)", epath)
        sub_id = int(m_id.group(1)) if m_id else (i + 1)
        resources[sub_id] = {"type": rtype, "props": props, "epath": epath}

    return {
        "res_type": res_type,
        "ext_res": ext_res,
        "resources": resources,
        "main_id": len(int_res_offsets) if int_res_offsets else None,
    }


def decode_surface(surf: dict):
    """Decode a Godot 3 ArrayMesh surface dict into (positions, normals, uvs, indices) numpy arrays."""
    vcnt = surf.get("vertex_count", 0)
    adata = surf.get("array_data", b"")
    if vcnt == 0 or not adata:
        return None

    fmt = surf.get("format", 0)
    stride = len(adata) // vcnt
    raw = np.frombuffer(adata, dtype=np.uint8, count=vcnt * stride).reshape(vcnt, stride)

    # Position is ALWAYS uncompressed 3x float32 at offset 0..12
    pos = np.frombuffer(raw[:, 0:12].tobytes(), dtype="<f4").reshape(vcnt, 3).copy()
    ofs = 12

    # Normal
    norm = None
    if fmt & (1 << 1):
        if fmt & (1 << 10):  # COMPRESS_NORMAL (4x int8)
            n_i8 = np.frombuffer(raw[:, ofs:ofs + 4].tobytes(), dtype="i1").reshape(vcnt, 4)[:, :3].astype(np.float32)
            norm = n_i8 / 127.0
            ofs += 4
        else:
            norm = np.frombuffer(raw[:, ofs:ofs + 12].tobytes(), dtype="<f4").reshape(vcnt, 3).copy()
            ofs += 12

    # Tangent
    if fmt & (1 << 2):
        ofs += 4 if (fmt & (1 << 11)) else 16

    # Color
    if fmt & (1 << 3):
        ofs += 4 if (fmt & (1 << 12)) else 16

    # UV
    uv = None
    if fmt & (1 << 4):
        if fmt & (1 << 13):  # COMPRESS_TEX_UV (2x float16)
            uv = np.frombuffer(raw[:, ofs:ofs + 4].tobytes(), dtype="<f2").reshape(vcnt, 2).astype(np.float32).copy()
            ofs += 4
        else:
            uv = np.frombuffer(raw[:, ofs:ofs + 8].tobytes(), dtype="<f4").reshape(vcnt, 2).copy()
            ofs += 8

    uv2 = None
    if fmt & (1 << 5):
        size = 4 if fmt & (1 << 14) else 8
        dtype = "<f2" if size == 4 else "<f4"
        uv2 = np.frombuffer(raw[:,ofs:ofs+size].tobytes(),dtype=dtype).reshape(vcnt,2).astype(np.float32)

    # Normalize normals carefully
    if norm is not None:
        lengths = np.linalg.norm(norm, axis=1, keepdims=True)
        lengths = np.where(lengths < 1e-6, 1.0, lengths)
        norm = (norm / lengths).astype(np.float32)
        # Replace any NaN/Inf
        norm = np.nan_to_num(norm, nan=0.0, posinf=0.0, neginf=0.0)

    if uv is not None:
        uv = np.nan_to_num(uv, nan=0.0, posinf=0.0, neginf=0.0)

    # Indices
    icnt = surf.get("index_count", 0)
    idata = surf.get("array_index_data", b"")
    if icnt > 0 and idata:
        idx_stride = len(idata) // icnt
        idx_dtype = "<u2" if idx_stride == 2 else "<u4"
        indices = np.frombuffer(idata, dtype=idx_dtype, count=icnt).copy()
        # Flip triangle winding from Godot CW (i0, i1, i2) to glTF CCW (i0, i2, i1)
        if len(indices) % 3 == 0:
            indices = indices.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
    else:
        indices = np.arange(vcnt, dtype=np.uint32)
        if len(indices) % 3 == 0:
            indices = indices.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)

    return pos, norm, uv, indices, uv2


def classify_pbr_material(mat_name: str, node_name: str = "") -> dict:
    """Map Tesla Godot material names to physically based glTF 2.0 material parameters."""
    source_path = mat_name
    mat_name = Path(mat_name).stem
    key = mat_name.lower()

    # Default PBR
    base_color = [0.22, 0.23, 0.25, 1.0]
    metallic = 0.2
    roughness = 0.45
    alpha_mode = "OPAQUE"
    double_sided = True
    emissive = None
    category = "trim"

    if any(k in key for k in ["stainless_steel", "stainless"]):
        base_color = [0.76, 0.78, 0.80, 1.0]
        metallic = 0.92
        roughness = 0.22
        category = "paint"
    elif any(k in key for k in ["paint", "exterior_hydroxide", "body"]) and not any(
        k in key for k in ["black", "plastic", "glass", "light", "rubber", "chrome", "interior", "mirror"]
    ):
        base_color = [0.78, 0.08, 0.11, 1.0]  # Default Ultra Red (customizable in viewer)
        metallic = 0.65
        roughness = 0.14
        category = "paint"
    elif any(k in key for k in ["glass_lights", "lights_glass", "headlights_glass", "light_glass"]):
        base_color = [0.92, 0.95, 0.99, 0.28]
        metallic = 0.05
        roughness = 0.04
        alpha_mode = "BLEND"
        category = "glass_clear"
    elif any(k in key for k in ["glass_tinted", "windows_top", "roof_glass", "windshield", "window", "glass"]):
        is_tinted = any(k in key for k in ["tinted", "top", "lr", "rr", "rear"])
        base_color = [0.05, 0.07, 0.09, 0.72 if is_tinted else 0.42]
        metallic = 0.1
        roughness = 0.03
        alpha_mode = "BLEND"
        category = "glass_tinted" if is_tinted else "glass"
    elif "mirror" in key:
        base_color = [0.95, 0.96, 0.98, 1.0]
        metallic = 1.0
        roughness = 0.02
        category = "mirror"
    elif any(k in key for k in ["caliper", "brakes_perf", "plastic_red"]):
        base_color = [0.82, 0.08, 0.10, 1.0]
        metallic = 0.45
        roughness = 0.22
        category = "caliper"
    elif any(k in key for k in ["rotor", "brake_disc"]):
        base_color = [0.68, 0.70, 0.74, 1.0]
        metallic = 0.88
        roughness = 0.28
        category = "rotor"
    elif any(k in key for k in ["brake_light", "stoplight", "taillight", "rear_light", "lights_trunk"]):
        base_color = [0.85, 0.06, 0.08, 1.0]
        metallic = 0.1
        roughness = 0.15
        emissive = [0.95, 0.08, 0.08]
        category = "taillight"
    elif any(k in key for k in ["turn_signal", "marker", "amber"]):
        base_color = [0.95, 0.45, 0.05, 1.0]
        metallic = 0.1
        roughness = 0.2
        emissive = [0.9, 0.38, 0.02]
        category = "turn_signal"
    elif any(k in key for k in ["illumination", "drl", "headlight", "lightbar", "beam", "light_global", "light.", "lights1"]):
        base_color = [0.96, 0.98, 1.0, 1.0]
        metallic = 0.2
        roughness = 0.12
        emissive = [0.92, 0.96, 1.0]
        category = "headlight"
    elif any(k in key for k in ["tire", "pirelli", "conti", "rubber"]):
        base_color = [0.09, 0.095, 0.105, 1.0]
        metallic = 0.04
        roughness = 0.82
        category = "tire"
    elif any(k in key for k in ["chrome", "aluminum", "silver", "metal", "badge"]):
        base_color = [0.82, 0.84, 0.87, 1.0]
        metallic = 0.92
        roughness = 0.16
        category = "chrome"
    elif any(k in key for k in [
        "wheel", "rim", "arachnid", "cyberstream", "cardenio", "turbine",
        "uberhelix", "helix", "riptide", "halo", "cypress", "gemini", "glider", "wishbone", "machina"
    ]):
        base_color = [0.26, 0.27, 0.30, 1.0]
        metallic = 0.84
        roughness = 0.24
        category = "wheel_rim"
    elif any(k in key for k in ["seats_white", "decor_white", "suede_light", "white"]):
        base_color = [0.90, 0.91, 0.93, 1.0]
        metallic = 0.02
        roughness = 0.48
        category = "interior_white"
    elif any(k in key for k in ["wood", "walnut"]):
        base_color = [0.42, 0.29, 0.20, 1.0]
        metallic = 0.04
        roughness = 0.62
        category = "wood"
    elif any(k in key for k in ["screen", "display"]):
        base_color = [0.05, 0.07, 0.10, 1.0]
        metallic = 0.15
        roughness = 0.06
        emissive = [0.04, 0.08, 0.14]
        category = "screen"
    elif any(k in key for k in ["spoiler", "carbon"]):
        base_color = [0.12, 0.13, 0.15, 1.0]
        metallic = 0.35
        roughness = 0.22
        category = "carbon"
    elif any(k in key for k in ["leather", "seat", "interior", "suede", "carpet", "fabric"]):
        base_color = [0.13, 0.14, 0.16, 1.0]
        metallic = 0.03
        roughness = 0.62
        category = "interior"
    elif any(k in key for k in ["solar"]):
        base_color = [0.08, 0.11, 0.18, 1.0]
        metallic = 0.65
        roughness = 0.18
        category = "solar"

    mat_def = {
        "name": f"{category}__{mat_name}",
        "pbrMetallicRoughness": {
            "baseColorFactor": base_color,
            "metallicFactor": metallic,
            "roughnessFactor": roughness,
        },
        "doubleSided": double_sided,
        "extras": {"category": category, "originalName": mat_name, "sourcePath": source_path},
    }
    if alpha_mode != "OPAQUE":
        mat_def["alphaMode"] = alpha_mode
    if emissive:
        mat_def["emissiveFactor"] = emissive
    source = read_source_material(source_path)
    if source:
        props, source_type = source
        mat_def["extras"]["sourceType"] = source_type
        mat_def["extras"]["sourceProperties"] = {k: v for k, v in props.items() if isinstance(v, (int, float, str, bool)) or (isinstance(v, (tuple, list)) and all(isinstance(x, (float, int)) for x in v))}
        pbr = mat_def["pbrMetallicRoughness"]
        if source_type == "SpatialMaterial":
            # Godot omits default properties from serialized materials.
            pbr.update(baseColorFactor=[1.0,1.0,1.0,1.0],metallicFactor=0.0,roughnessFactor=1.0)
            if not props.get("emission_enabled", False): mat_def.pop("emissiveFactor", None)
            emission = props.get("emission")
            if props.get("emission_enabled") and isinstance(emission, (list,tuple)):
                mat_def["emissiveFactor"] = list(emission[:3])
        color = props.get("albedo_color", props.get("shader_param/albedo"))
        if isinstance(color, (tuple, list)) and len(color) == 4:
            pbr["baseColorFactor"] = list(color)
        for key in ("metallic", "roughness"):
            value = props.get(key, props.get("shader_param/" + key))
            if isinstance(value, (float, int)):
                pbr[key + "Factor"] = max(0, min(1, value))
    return mat_def


@lru_cache(maxsize=None)
def read_source_material(source_path):
    path = resolve_res_path(source_path)
    if not path:
        return None
    if path.suffix == ".tres":
        text = path.read_text()
        props = {}
        refs = {int(i): path for path,i in re.findall(r'\[ext_resource path="([^"]+)" type="[^"]+" id=(\d+)\]',text)}
        for key, value in re.findall(r"^([\w/]+) = (.+)$", text, re.M):
            if value.startswith("Color("):
                props[key] = [float(x) for x in value[6:-1].split(",")]
            elif value.startswith("ExtResource"):
                ref = re.search(r"\d+",value)
                if ref: props[key] = refs.get(int(ref.group()))
            else:
                try: props[key] = float(value)
                except ValueError: pass
        return props, "SpatialMaterial"
    parsed = parse_rsrc_file(path)
    resource = parsed["resources"][parsed["main_id"]]
    props = dict(resource["props"])
    for key, value in list(props.items()):
        if isinstance(value, tuple) and value[0] == "ExtResource":
            props[key] = parsed["ext_res"][value[1]][1]
    return props, resource["type"]


def should_skip_node(node_name: str, hidden_set: set[str]) -> bool:
    """Return True if a node is a duplicate RHD/Global part, collision volume, or baked ground projection plane."""
    if node_name in hidden_set:
        return True
    nl = node_name.lower()
    if "groundplane" in nl.replace("_", ""): return True
    skip_substrings = [
        "_rhd", "rhd_", "_global", "global_", "plate_eu",
        "collision", "projection", "ground_plane", "ground_shadow", "groundshadow", "groundreflection",
        "headlights_beam", "leftglow", "rightglow", "airflow", "defrost",
        "interior_6_seater", "interior_7_seater",
        "body_original", "bumper_f_original", "hood_original", "lights_original", "lights_glass_original",
        "drl_original", "turn_signal_original", "headlights_original",
        "doorcard_2_0", "blocker", "floor_longrange",
    ]
    if nl == "floor":
        return True
    return any(s in nl for s in skip_substrings)


def parse_animation(text):
    tracks = []
    for tid in sorted(set(re.findall(r"tracks/(\d+)/type", text)), key=int):
        def field(name):
            m = re.search(rf'tracks/{tid}/{name} = (.*?)(?=\ntracks/|\n\[|\Z)', text, re.S)
            return m.group(1).strip() if m else ""
        target = re.search(r'NodePath\("([^\"]+)"\)', field("path"))
        if not target or field("enabled") == "false": continue
        kind = field("type").strip('"')
        keys = field("keys")
        track = {"target": target.group(1), "type": kind, "interpolation": int(field("interp") or 1)}
        if kind == "transform":
            values = [float(x) for x in keys.removeprefix("PoolRealArray(").rstrip(" )").split(",") if x.strip()]
            if len(values) % 12: raise ValueError("Invalid transform track")
            rows = [values[i:i+12] for i in range(0, len(values), 12)]
            track.update(times=[r[0] for r in rows], transitions=[r[1] for r in rows], values=[r[2:] for r in rows])
        elif kind == "value":
            tm = re.search(r'"times": PoolRealArray\( ([^)]*)\)', keys)
            vm = re.search(r'"values": \[([^]]*)\]', keys, re.S)
            if not tm or not vm: continue
            vectors = re.findall(r'Vector3\( ([^)]*)\)', vm.group(1))
            if not vectors: continue
            track.update(times=[float(x) for x in tm.group(1).split(",")], values=[[float(x) for x in v.split(",")] for v in vectors])
        else: continue
        if len(track.get("times", [])) == len(track.get("values", [])) and track.get("times"):
            tracks.append(track)
    length = re.search(r'^length = ([\d.]+)', text, re.M)
    return {"duration": float(length.group(1)) if length else 1.0, "tracks": tracks}


def parse_tscn_metadata(tscn_path: Path | None):
    """Parse a .tscn file for ext_resources, hidden nodes, material overrides, transforms, and animations."""
    info = {
        "ext_res": {},
        "hidden_nodes": set(),
        "node_materials": {},
        "node_transforms": {},
        "node_meshes": {},
        "node_parents": {},
        "wheel_mounts": [],
        "brake_mounts": [],
        "animations": [],
    }
    if not tscn_path or not tscn_path.exists():
        return info

    txt = tscn_path.read_text(errors="ignore")
    for m in re.finditer(r'\[ext_resource path="([^"]+)" type="([^"]+)" id=(\d+)\]', txt):
        info["ext_res"][int(m.group(3))] = (m.group(2), m.group(1))

    sub_anims = {}
    for sec in txt.split("\n["):
        lines = sec.splitlines()
        if not lines: continue
        header = lines[0]
        if header.startswith('sub_resource type="Animation"'):
            aid = int(re.search(r"id=(\d+)", header).group(1))
            sub_anims[aid] = parse_animation("\n".join(lines[1:]))
        elif header.startswith("node "):
            m_name = re.search(r'name="([^"]+)"', header)
            if not m_name:
                continue
            nm = m_name.group(1)
            m_parent = re.search(r'parent="([^"]+)"', header)
            parent_str = m_parent.group(1) if m_parent else None
            if parent_str:
                info["node_parents"][nm] = parent_str

            sec_body = "\n".join(lines[1:])
            if re.search(r"^visible\s*=\s*false", sec_body, re.MULTILINE):
                info["hidden_nodes"].add(nm)

            is_marker = ("marker_name" in sec_body or (parent_str and parent_str.startswith("Spatials"))) and not any(k in nm for k in ["Wheel", "Brake"])
            m_tr = re.search(r"transform\s*=\s*Transform\(\s*([^\)]+)\)", sec_body)
            if m_tr and not is_marker:
                vals = [float(x.strip()) for x in m_tr.group(1).split(",")]
                if len(vals) == 12:
                    info["node_transforms"][(parent_str, nm)] = vals
                    info["node_transforms"][nm] = vals

            m_mesh = re.search(r"^mesh\s*=\s*ExtResource\(\s*(\d+)\s*\)", sec_body, re.MULTILINE)
            if m_mesh:
                info["node_meshes"][nm] = int(m_mesh.group(1))

            mat_ovr = {}
            for m_mat in re.finditer(r"material/(\d+)\s*=\s*ExtResource\(\s*(\d+)\s*\)", sec_body):
                s_idx = int(m_mat.group(1))
                er_id = int(m_mat.group(2))
                if er_id in info["ext_res"]:
                    mat_ovr[s_idx] = info["ext_res"][er_id][1]
            if mat_ovr:
                info["node_materials"][nm] = mat_ovr

            if "AnimationPlayer" in header:
                for m_an in re.finditer(r'anims/(\w+)\s*=\s*(SubResource|ExtResource)\(\s*(\d+)\s*\)', sec_body):
                    aid = int(m_an.group(3))
                    if m_an.group(2) == "SubResource":
                        animation = sub_anims.get(aid)
                    else:
                        ref = info["ext_res"].get(aid)
                        path = resolve_res_path(ref[1]) if ref else None
                        animation = parse_animation(path.read_text()) if path else None
                    if animation and animation["tracks"]:
                        info["animations"].append(dict(animation, name=nm, source=str(tscn_path.relative_to(EXTRACTED_ROOT)), root=parent_str or "."))

            # Wheel & Brake mounts
            if any(nm.startswith(p) for p in ["Wheel_LF", "Wheel_RF", "Wheel_LR", "Wheel_RL", "Wheel_RR", "Wheel_L_Spatial", "Wheel_R_Spatial"]):
                if nm in info["node_transforms"] or (parent_str, nm) in info["node_transforms"]:
                    t_vals = info["node_transforms"].get((parent_str, nm), info["node_transforms"].get(nm))
                    info["wheel_mounts"].append((parent_str, nm, t_vals))
            elif any(nm.startswith(p) for p in ["Brakes_LF", "Brakes_RF", "Brakes_LR", "Brakes_RR"]):
                if nm in info["node_transforms"] or (parent_str, nm) in info["node_transforms"]:
                    t_vals = info["node_transforms"].get((parent_str, nm), info["node_transforms"].get(nm))
                    info["brake_mounts"].append((parent_str, nm, t_vals))

    return info


def godot_transform_to_gltf_matrix(t):
    """Convert Godot 12-float Transform (row-major 3x3 basis + origin) to glTF 16-float column-major matrix."""
    return [
        float(t[0]), float(t[3]), float(t[6]), 0.0,
        float(t[1]), float(t[4]), float(t[7]), 0.0,
        float(t[2]), float(t[5]), float(t[8]), 0.0,
        float(t[9]), float(t[10]), float(t[11]), 1.0,
    ]


class GLBBuilder:
    """Packs nodes, meshes, and PBR materials into a standard binary glTF 2.0 (.glb) file."""

    def __init__(self):
        self.buffer = bytearray()
        self.buffer_views = []
        self.accessors = []
        self.materials = []
        self.mat_cache = {}
        self.meshes = []
        self.nodes = []
        self.root_nodes = []
        self.source_animations = []
        self.runtime_effects = {}
        self.source_textures = []
        self.texture_cache = {}
        self.total_vertices = 0
        self.total_triangles = 0

    def get_or_create_material(self, mat_name: str, node_name: str = "") -> int:
        mat_def = classify_pbr_material(mat_name, node_name)
        key = mat_name
        if key in self.mat_cache:
            return self.mat_cache[key]
        source = read_source_material(mat_name)
        if source:
            props, _ = source
            bindings = {}
            for role, prop in [("albedo", "albedo_texture"), ("mra", "metallic_texture"), ("ao", "ao_texture")]:
                path = props.get(prop, props.get("shader_param/custom_albedo_texture") if role == "albedo" else None)
                if not isinstance(path, str): continue
                texture = self.add_source_texture(path)
                if texture is not None: bindings[role] = texture
            mat_def["extras"]["customAlbedo"] = "shader_param/custom_albedo_texture" in props
            mat_def["extras"]["textures"] = bindings
            mat_def["extras"]["aoUV2"] = bool(props.get("ao_on_uv2", False))
            mat_def["extras"]["aoChannel"] = int(props.get("ao_texture_channel", 0))
        idx = len(self.materials)
        self.materials.append(mat_def)
        self.mat_cache[key] = idx
        return idx

    def add_source_texture(self, source):
        if source in self.texture_cache: return self.texture_cache[source]
        path = resolve_res_path(source)
        if not path: return None
        data = path.read_bytes()
        if data[:4] != b"GDST": return None
        width, _, height, _, flags, fmt = struct.unpack_from("<HHHHII", data, 4)
        code = fmt & 0xFFFFF
        if code == 29: # Godot ETC / Metal ETC2 RGB8 (ETC1-compatible)
            size = ((width+3)//4)*((height+3)//4)*8
            raw = data[20:20+size]; encoding = "etc2rgb8"
        elif b"\x89PNG\r\n\x1a\n" in data[:48]:
            offset = data.index(b"\x89PNG\r\n\x1a\n")
            end = data.index(b"IEND",offset)+8
            raw = data[offset:end]; encoding = "png"
        elif b"WEBP" in data[:48]:
            offset = data.index(b"RIFF")
            size = struct.unpack_from("<I", data, offset+4)[0]+8
            raw = data[offset:offset+size]; encoding = "webp"
        elif code in (0,1,2,3,4,5):
            from PIL import Image
            import io
            mode = {0:"L",1:"LA",2:"L",3:"LA",4:"RGB",5:"RGBA"}[code]
            channels = len(mode)
            image = Image.frombytes(mode,(width,height),data[20:20+width*height*channels]).convert("RGBA")
            stream=io.BytesIO();image.save(stream,format="PNG")
            raw=stream.getvalue();encoding="png"
        else:
            return None
        index = len(self.source_textures)
        self.source_textures.append({"source":source,"width":width,"height":height,"encoding":encoding,"bufferView":self._append_bytes(raw)})
        self.texture_cache[source] = index
        return index

    def _append_bytes(self, raw_bytes: bytes, target: int | None = None) -> int:
        # Align to 4-byte boundary
        pad = (4 - (len(self.buffer) % 4)) % 4
        if pad:
            self.buffer.extend(b"\x00" * pad)
        offset = len(self.buffer)
        self.buffer.extend(raw_bytes)
        bv = {
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(raw_bytes),
        }
        if target is not None:
            bv["target"] = target
        bv_idx = len(self.buffer_views)
        self.buffer_views.append(bv)
        return bv_idx

    def add_array_mesh(self, mesh_props: dict, ext_res: list, node_name: str = "", mat_overrides: dict | None = None) -> int | None:
        primitives = []
        surf_keys = sorted(
            [k for k in mesh_props.keys() if k.startswith("surfaces/")],
            key=lambda s: int(s.split("/")[1])
        )
        for sk in surf_keys:
            s_idx = int(sk.split("/")[1])
            surf = mesh_props[sk]
            if not isinstance(surf, dict):
                continue
            decoded = decode_surface(surf)
            if decoded is None:
                continue
            pos, norm, uv, indices, uv2 = decoded
            if len(pos) == 0 or len(indices) == 0:
                continue

            # Resolve material name
            mat_name = "Default"
            if mat_overrides and s_idx in mat_overrides:
                mat_name = mat_overrides[s_idx]
            else:
                m_ref = surf.get("material")
                if isinstance(m_ref, tuple) and m_ref[0] == "ExtResource":
                    er_idx = m_ref[1]
                    if 0 <= er_idx < len(ext_res):
                        mat_name = ext_res[er_idx][1]
                    elif 1 <= er_idx <= len(ext_res):
                        mat_name = ext_res[er_idx - 1][1]

            mat_idx = self.get_or_create_material(mat_name, node_name)

            # Position accessor
            pos_f32 = np.ascontiguousarray(pos, dtype="<f4")
            pos_bv = self._append_bytes(pos_f32.tobytes(), target=34962)
            pos_acc = len(self.accessors)
            self.accessors.append({
                "bufferView": pos_bv,
                "byteOffset": 0,
                "componentType": 5126,  # FLOAT
                "count": int(len(pos_f32)),
                "type": "VEC3",
                "min": [float(x) for x in pos_f32.min(axis=0)],
                "max": [float(x) for x in pos_f32.max(axis=0)],
            })

            attrs = {"POSITION": pos_acc}

            if norm is not None and len(norm) == len(pos_f32):
                norm_f32 = np.ascontiguousarray(norm, dtype="<f4")
                norm_bv = self._append_bytes(norm_f32.tobytes(), target=34962)
                norm_acc = len(self.accessors)
                self.accessors.append({
                    "bufferView": norm_bv,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": int(len(norm_f32)),
                    "type": "VEC3",
                })
                attrs["NORMAL"] = norm_acc

            if uv is not None and len(uv) == len(pos_f32):
                uv_f32 = np.ascontiguousarray(uv, dtype="<f4")
                uv_bv = self._append_bytes(uv_f32.tobytes(), target=34962)
                uv_acc = len(self.accessors)
                self.accessors.append({
                    "bufferView": uv_bv,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": int(len(uv_f32)),
                    "type": "VEC2",
                })
                attrs["TEXCOORD_0"] = uv_acc

            if uv2 is not None:
                view = self._append_bytes(np.ascontiguousarray(uv2,dtype="<f4").tobytes(),target=34962)
                attrs["TEXCOORD_1"] = len(self.accessors)
                self.accessors.append({"bufferView":view,"byteOffset":0,"componentType":5126,"count":len(uv2),"type":"VEC2"})

            # Index accessor
            use_u32 = int(indices.max()) >= 65535
            idx_arr = np.ascontiguousarray(indices, dtype="<u4" if use_u32 else "<u2")
            idx_bv = self._append_bytes(idx_arr.tobytes(), target=34963)
            idx_acc = len(self.accessors)
            self.accessors.append({
                "bufferView": idx_bv,
                "byteOffset": 0,
                "componentType": 5125 if use_u32 else 5123,
                "count": int(len(idx_arr)),
                "type": "SCALAR",
            })

            primitives.append({
                "attributes": attrs,
                "indices": idx_acc,
                "material": mat_idx,
                "mode": 4,  # TRIANGLES
            })
            self.total_vertices += int(len(pos_f32))
            self.total_triangles += int(len(idx_arr) // 3)

        if not primitives:
            return None

        mesh_idx = len(self.meshes)
        self.meshes.append({
            "name": mesh_props.get("resource_name", node_name or f"mesh_{mesh_idx}"),
            "primitives": primitives,
        })
        return mesh_idx

    def add_scn_to_tree(self, scn_path: Path, tscn_info: dict | None = None, parent_gltf_node: int | None = None, root_matrix: list[float] | None = None) -> int:
        """Add a Godot .scn or .mesh into this GLBBuilder and return its root glTF node index."""
        parsed = parse_rsrc_file(scn_path)
        ext_res = parsed["ext_res"]
        resources = parsed["resources"]
        hidden_set = tscn_info["hidden_nodes"] if tscn_info else set()
        node_mat_map = tscn_info["node_materials"] if tscn_info else {}
        node_tr_map = tscn_info["node_transforms"] if tscn_info else {}

        if parsed["res_type"] == "ArrayMesh":
            main_res = resources[parsed["main_id"]]
            mat_ovr = node_mat_map.get(scn_path.stem)
            m_idx = self.add_array_mesh(main_res["props"], ext_res, scn_path.stem, mat_ovr)
            n_def = {"name": scn_path.stem}
            if m_idx is not None:
                n_def["mesh"] = m_idx
            if root_matrix:
                n_def["matrix"] = root_matrix
            n_idx = len(self.nodes)
            self.nodes.append(n_def)
            if parent_gltf_node is not None:
                self.nodes[parent_gltf_node].setdefault("children", []).append(n_idx)
            else:
                self.root_nodes.append(n_idx)
            return n_idx

        # PackedScene
        scene_res = resources[parsed["main_id"]]
        bundled = scene_res["props"]["_bundled"]
        names = bundled["names"]
        variants = bundled["variants"]
        nodes_flat = bundled["nodes"]
        ncnt = bundled["node_count"]

        idx = 0
        godot_to_gltf = {}
        skipped_godot_indices = set()
        first_node_idx = None

        for n in range(ncnt):
            parent, owner, ntype, name_id, instance = nodes_flat[idx:idx + 5]
            idx += 5
            pc = nodes_flat[idx]
            idx += 1
            nprops = {}
            for _ in range(pc):
                pk = names[nodes_flat[idx]]
                pv = variants[nodes_flat[idx + 1]]
                idx += 2
                nprops[pk] = pv
            gcnt = nodes_flat[idx]
            idx += 1 + gcnt

            nm = names[name_id]
            if parent in skipped_godot_indices or should_skip_node(nm, hidden_set) or nprops.get("visible") is False:
                skipped_godot_indices.add(n)
                continue

            n_def = {"name": nm}

            # Check transform (either overridden in .tscn or in .scn)
            t_vals = node_tr_map.get(nm, nprops.get("transform"))
            if n == 0 and root_matrix is not None:
                n_def["matrix"] = root_matrix
            elif isinstance(t_vals, (list, tuple)) and len(t_vals) == 12:
                n_def["matrix"] = godot_transform_to_gltf_matrix(t_vals)

            # Check mesh property
            mref = nprops.get("mesh")
            if isinstance(mref, tuple) and mref[0] == "SubResource":
                sub_id = mref[1]
                if sub_id in resources and resources[sub_id]["type"] == "ArrayMesh":
                    # Check material overrides in nprops or tscn
                    mat_ovr = dict(node_mat_map.get(nm, {}))
                    for k, v in nprops.items():
                        if k.startswith("material/") and isinstance(v, tuple) and v[0] == "ExtResource":
                            s_i = int(k.split("/")[1])
                            er_i = v[1]
                            if 0 <= er_i < len(ext_res):
                                mat_ovr.setdefault(s_i, ext_res[er_i][1])
                    m_idx = self.add_array_mesh(resources[sub_id]["props"], ext_res, nm, mat_ovr)
                    if m_idx is not None:
                        n_def["mesh"] = m_idx

            g_idx = len(self.nodes)
            self.nodes.append(n_def)
            godot_to_gltf[n] = g_idx

            if n == 0:
                first_node_idx = g_idx
                if parent_gltf_node is not None:
                    self.nodes[parent_gltf_node].setdefault("children", []).append(g_idx)
                else:
                    self.root_nodes.append(g_idx)
            elif parent in godot_to_gltf:
                self.nodes[godot_to_gltf[parent]].setdefault("children", []).append(g_idx)

        return first_node_idx

    def write_glb(self, out_path: Path):
        pad = (4 - (len(self.buffer) % 4)) % 4
        if pad:
            self.buffer.extend(b"\x00" * pad)

        gltf = {
            "asset": {
                "version": "2.0",
                "generator": "REA Tesla Godot-to-glTF 2.0 Converter",
            },
            "scene": 0,
            "scenes": [{"nodes": self.root_nodes}],
            "nodes": self.nodes,
            "meshes": self.meshes,
            "materials": self.materials,
            "extras": {"sourceAnimations": self.source_animations, "sourceTextures": self.source_textures, "runtimeEffects": self.runtime_effects},
            "accessors": self.accessors,
            "bufferViews": self.buffer_views,
            "buffers": [{"byteLength": len(self.buffer)}],
        }

        json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        json_pad = (4 - (len(json_bytes) % 4)) % 4
        if json_pad:
            json_bytes += b" " * json_pad

        total_len = 12 + 8 + len(json_bytes) + 8 + len(self.buffer)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total_len))
            f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
            f.write(json_bytes)
            f.write(struct.pack("<I4s", len(self.buffer), b"BIN\x00"))
            f.write(self.buffer)


def build_legacy_tscn_vehicle(tscn_path: Path, wheel_scn: Path, out_glb: Path) -> dict:
    """Assemble legacy Model S or Model X from its .tscn file and modular .mesh objects."""
    tscn_info = parse_tscn_metadata(tscn_path)
    builder = GLBBuilder()

    root_idx = len(builder.nodes)
    builder.nodes.append({"name": tscn_path.stem})
    builder.root_nodes.append(root_idx)

    name_to_node = {".": root_idx}

    # Add all MeshInstance and Spatial nodes from .tscn
    txt = tscn_path.read_text(errors="ignore")
    for sec in txt.split("\n["):
        lines = sec.splitlines()
        if not lines or not lines[0].startswith("node "):
            continue
        header = lines[0]
        m_name = re.search(r'name="([^"]+)"', header)
        if not m_name:
            continue
        nm = m_name.group(1)
        m_parent = re.search(r'parent="([^"]+)"', header)
        parent_path = m_parent.group(1) if m_parent else None
        if parent_path is None:
            continue  # ROOT node

        parent_name = parent_path.split("/")[-1] if parent_path != "." else "."
        if parent_name not in name_to_node:
            continue
        if should_skip_node(nm, tscn_info["hidden_nodes"]):
            continue

        n_def = {"name": nm}
        t_vals = tscn_info["node_transforms"].get((parent_path, nm), tscn_info["node_transforms"].get(nm))
        if t_vals:
            n_def["matrix"] = godot_transform_to_gltf_matrix(t_vals)

        if nm in tscn_info["node_meshes"]:
            er_id = tscn_info["node_meshes"][nm]
            if er_id in tscn_info["ext_res"]:
                res_path = tscn_info["ext_res"][er_id][1]
                mesh_file = resolve_res_path(res_path)
                if mesh_file and mesh_file.suffix == ".mesh":
                    parsed = parse_rsrc_file(mesh_file)
                    main_res = parsed["resources"][parsed["main_id"]]
                    mat_ovr = tscn_info["node_materials"].get(nm)
                    m_idx = builder.add_array_mesh(main_res["props"], parsed["ext_res"], nm, mat_ovr)
                    if m_idx is not None:
                        n_def["mesh"] = m_idx

        g_idx = len(builder.nodes)
        builder.nodes.append(n_def)
        builder.nodes[name_to_node[parent_name]].setdefault("children", []).append(g_idx)
        name_to_node[nm] = g_idx

    # Mount the 4 wheels
    if wheel_scn and wheel_scn.exists():
        wheel_tscn = EXTRACTED_ROOT / "Ego" / "Wheels_X_S" / "Wheel_Turbine_Onyx_Black.tscn"
        w_info = parse_tscn_metadata(wheel_tscn)
        for _, w_nm, t_vals in tscn_info["wheel_mounts"]:
            mount_node = name_to_node.get(w_nm)
            if mount_node is None:
                mount_node = len(builder.nodes)
                builder.nodes.append({
                    "name": w_nm,
                    "matrix": godot_transform_to_gltf_matrix(t_vals),
                })
                builder.nodes[root_idx].setdefault("children", []).append(mount_node)
            builder.add_scn_to_tree(wheel_scn, w_info, parent_gltf_node=mount_node)

    from source_effects import attach
    attach(builder, tscn_path)
    builder.source_animations = tscn_info["animations"]
    builder.write_glb(out_glb)
    return {
        "vertices": builder.total_vertices,
        "triangles": builder.total_triangles,
        "size_bytes": out_glb.stat().st_size,
        "animations": tscn_info["animations"],
    }


def build_vehicle_glb(
    scn_path: Path,
    tscn_path: Path | None,
    wheel_scn: Path | None,
    wheel_tscn: Path | None,
    out_glb: Path,
    rotate_y_neg90: bool = False,
    extra_attachments: list[tuple[Path, str]] | None = None,
) -> dict:
    """Convert a flagship Tesla vehicle .scn + .tscn + mounted 3D wheels into a complete .glb."""
    tscn_info = parse_tscn_metadata(tscn_path)
    builder = GLBBuilder()

    root_matrix = None
    if rotate_y_neg90:
        # Rotate -90 deg around Y so vehicle faces +X like all other Tesla models
        root_matrix = [
            0.0, 0.0, 1.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            -1.0, 0.0, 0.0, 0.0,
            0.0, 0.0, 0.0, 1.0,
        ]

    car_root = builder.add_scn_to_tree(scn_path, tscn_info, root_matrix=root_matrix)

    # Map existing node names inside car_root
    existing_nodes = {n.get("name"): i for i, n in enumerate(builder.nodes)}

    # Attach extra sub-scenes (e.g., Cybertruck Lightbar / Tonneau)
    if extra_attachments:
        for att_scn, att_name in extra_attachments:
            if att_scn.exists():
                att_holder = len(builder.nodes)
                builder.nodes.append({"name": att_name})
                builder.nodes[car_root].setdefault("children", []).append(att_holder)
                builder.add_scn_to_tree(att_scn, parent_gltf_node=att_holder)

    # Mount wheels onto Wheel_LF / RF / LR / RR mounts
    if wheel_scn and wheel_scn.exists():
        w_info = parse_tscn_metadata(wheel_tscn)
        if tscn_path and tscn_path.name == "Semi.tscn":
            # Semi has 3 axles: FrontAxle (x=2.563, y=0.502), RearFrontAxle (x=-1.687, y=0.502), RearRearAxle (x=-2.936, y=0.502)
            rear_wheel_scn = EXTRACTED_ROOT / "models_by_vehicle/Ego/Wheels_Semi/Wheel_R_Semi.scn"
            rear_wheel_tscn = EXTRACTED_ROOT / "Ego/Wheels_Semi/Wheel_R_Semi.tscn"
            rw_info = parse_tscn_metadata(rear_wheel_tscn)
            # Compose the actual axle and wheel-socket transforms from Semi.tscn.
            source_nodes = {}
            text = tscn_path.read_text()
            for header, body in re.findall(r'\[node ([^\]]+)\]([^\[]*)', text):
                name = re.search(r'name="([^"]+)"',header).group(1)
                parent = re.search(r'parent="([^"]+)"',header)
                parent = parent.group(1) if parent else "."
                transform = re.search(r'transform = Transform\( ([^)]*)\)',body)
                if transform:
                    vals = [float(x) for x in transform.group(1).split(",")]
                    source_nodes[(parent,name)] = np.array(godot_transform_to_gltf_matrix(vals)).reshape(4,4,order="F")
            for axle, tag in [("FrontAxle","F"),("RearFrontAxle","R1"),("RearRearAxle","R2")]:
                axle_matrix = source_nodes[("Spatials",axle)]
                for side in ["L","R"]:
                    socket = source_nodes[("Spatials/"+axle,"Wheel_"+side+"_Spatial")]
                    mount = len(builder.nodes)
                    builder.nodes.append({"name":"Wheel_"+side+tag+"_Spatial", "matrix":(axle_matrix@socket).flatten(order="F").tolist(),
                                          "extras":{"spinAxis":[1,0,0],"sourcePath":"Spatials/"+axle+"/Wheel_"+side+"_Spatial"}})
                    builder.nodes[car_root].setdefault("children",[]).append(mount)
                    builder.add_scn_to_tree(wheel_scn if tag=="F" else rear_wheel_scn,w_info if tag=="F" else rw_info,parent_gltf_node=mount)
        else:
            seen_mounts = set()
            for _, w_nm, t_vals in tscn_info["wheel_mounts"]:
                # Markers describe the wheel socket in the source scene, while
                # suspension animates its Spatial. Attach geometry to that socket.
                spatial = w_nm.removesuffix("_Marker") + "_Spatial"
                if w_nm.endswith("_Marker") and spatial in existing_nodes:
                    w_nm = spatial
                if w_nm in seen_mounts:
                    continue
                seen_mounts.add(w_nm)
                if w_nm in existing_nodes:
                    m_idx = existing_nodes[w_nm]
                    builder.nodes[m_idx]["matrix"] = godot_transform_to_gltf_matrix(t_vals)
                else:
                    m_idx = len(builder.nodes)
                    builder.nodes.append({"name": w_nm, "matrix": godot_transform_to_gltf_matrix(t_vals)})
                    builder.nodes[car_root].setdefault("children", []).append(m_idx)
                builder.add_scn_to_tree(wheel_scn, w_info, parent_gltf_node=m_idx)

    from source_effects import attach
    attach(builder, tscn_path)
    builder.source_animations = tscn_info["animations"]
    builder.write_glb(out_glb)
    return {
        "vertices": builder.total_vertices,
        "triangles": builder.total_triangles,
        "size_bytes": out_glb.stat().st_size,
        "animations": tscn_info["animations"],
    }


def build_standalone_glb(scn_path: Path, tscn_path: Path | None, out_glb: Path) -> dict:
    tscn_info = parse_tscn_metadata(tscn_path)
    builder = GLBBuilder()
    builder.add_scn_to_tree(scn_path, tscn_info)
    from source_effects import attach
    attach(builder, tscn_path)
    builder.source_animations = tscn_info["animations"]
    builder.write_glb(out_glb)
    return {
        "vertices": builder.total_vertices,
        "triangles": builder.total_triangles,
        "size_bytes": out_glb.stat().st_size,
        "animations": [],
    }


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ego_models = EXTRACTED_ROOT / "models_by_vehicle" / "Ego"
    ego_tscn = EXTRACTED_ROOT / "Ego"

    catalog = {
        "vehicles": [],
        "wheels": [],
        "energy_and_accessories": [],
    }

    vehicle_specs = [
        {
            "id": "cybertruck",
            "name": "Cybertruck Cyberbeast",
            "subtitle": "Tri-Motor AWD • Stainless Steel Exoskeleton",
            "category": "Trucks & Commercial",
            "badge": "CYBERBEAST",
            "defaultPaint": "Stainless Steel",
            "scn": ego_models / "Cybertruck/Cybertruck.scn",
            "tscn": ego_tscn / "Cybertruck/Cybertruck.tscn",
            "wheel_scn": ego_models / "Cybertruck/Wheels/Wheel_Cybertruck_Premium.scn",
            "wheel_tscn": ego_tscn / "Cybertruck/Wheels/Wheel_Cybertruck_Premium.tscn",
            "extras": [
                (ego_models / "Cybertruck/Lightbar.scn", "Roof_Lightbar"),
                (ego_models / "Cybertruck/Tonneau.scn", "Tonneau_Cover"),
            ],
            "specs": {"range": "320 mi", "zeroToSixty": "2.6 s", "topSpeed": "130 mph", "power": "845 hp"},
        },
        {
            "id": "model3_high",
            "name": "Model 3 Highland",
            "subtitle": "2024+ Performance & Long Range AWD",
            "category": "Sedans",
            "badge": "HIGHLAND",
            "defaultPaint": "Ultra Red",
            "scn": ego_models / "3_High/Model3_High.scn",
            "tscn": ego_tscn / "3_High/Model3_High.tscn",
            "wheel_scn": ego_models / "Wheels_P3/Wheel_Halo.scn",
            "wheel_tscn": ego_tscn / "Wheels_P3/Wheel_Halo.tscn",
            "specs": {"range": "341 mi", "zeroToSixty": "2.9 s", "topSpeed": "163 mph", "power": "510 hp"},
        },
        {
            "id": "modely_high",
            "name": "Model Y Highland (Juniper)",
            "subtitle": "Refreshed Crossover SUV • Dual Motor AWD",
            "category": "SUVs",
            "badge": "HIGHLAND SUV",
            "defaultPaint": "Quicksilver",
            "scn": ego_models / "Y_High/ModelY_High.scn",
            "tscn": ego_tscn / "Y_High/ModelY_High.tscn",
            "wheel_scn": ego_models / "Wheels_P3/Wheel_Riptide.scn",
            "wheel_tscn": ego_tscn / "Wheels_P3/Wheel_Riptide.tscn",
            "specs": {"range": "330 mi", "zeroToSixty": "3.5 s", "topSpeed": "155 mph", "power": "456 hp"},
        },
        {
            "id": "models_plaid",
            "name": "Model S Plaid (Palladium)",
            "subtitle": "Tri-Motor Plaid • Carbon-Sleeved Rotors",
            "category": "Sedans",
            "badge": "PLAID",
            "defaultPaint": "Ultra Red",
            "scn": ego_models / "S_Palladium/Palladium_S.scn",
            "tscn": ego_tscn / "S_Palladium/S_Palladium.tscn",
            "wheel_scn": ego_models / "Wheels_Palladium/Arachnid21.scn",
            "wheel_tscn": ego_tscn / "Wheels_Palladium/Arachnid21.tscn",
            "specs": {"range": "359 mi", "zeroToSixty": "1.99 s", "topSpeed": "200 mph", "power": "1,020 hp"},
        },
        {
            "id": "modelx_plaid",
            "name": "Model X Plaid (Palladium)",
            "subtitle": "Tri-Motor Plaid SUV • Falcon Wing Doors",
            "category": "SUVs",
            "badge": "PLAID SUV",
            "defaultPaint": "Pearl White",
            "scn": ego_models / "X_Palladium/X_Palladium.scn",
            "tscn": ego_tscn / "X_Palladium/X_Palladium.tscn",
            "wheel_scn": ego_models / "Wheels_Palladium/Cyberstream.scn",
            "wheel_tscn": ego_tscn / "Wheels_Palladium/Cyberstream.tscn",
            "specs": {"range": "335 mi", "zeroToSixty": "2.5 s", "topSpeed": "163 mph", "power": "1,020 hp"},
        },
        {
            "id": "bayberry",
            "name": "Project Bayberry (Juniper)",
            "subtitle": "Next-Gen Model Y Refresh • Full Lightbar",
            "category": "SUVs",
            "badge": "CODENAME BAYBERRY",
            "defaultPaint": "Quicksilver",
            "scn": ego_models / "Bayberry/Bayberry.scn",
            "tscn": ego_tscn / "Bayberry/Bayberry.tscn",
            "wheel_scn": ego_models / "Wheels_Bayberry/Uberhelix/Uberhelix_20_Caps.scn",
            "wheel_tscn": ego_tscn / "Wheels_Bayberry/Uberhelix/Uberhelix.tscn",
            "rotate_y_neg90": True,
            "specs": {"range": "350 mi", "zeroToSixty": "3.4 s", "topSpeed": "155 mph", "power": "480 hp"},
        },
        {
            "id": "bayberry_e41",
            "name": "Project Bayberry E41",
            "subtitle": "Compact / Streamlined Model Y Variant (E41)",
            "category": "SUVs",
            "badge": "CODENAME E41",
            "defaultPaint": "Stealth Grey",
            "scn": ego_models / "BayberryE41/BayberryE41.scn",
            "tscn": ego_tscn / "BayberryE41/BayberryE41.tscn",
            "wheel_scn": ego_models / "Wheels_Bayberry/BayberryE41/Wheel_E41.scn",
            "wheel_tscn": None,
            "rotate_y_neg90": True,
            "specs": {"range": "310 mi", "zeroToSixty": "4.8 s", "topSpeed": "135 mph", "power": "340 hp"},
        },
        {
            "id": "bayberry_e80",
            "name": "Project Bayberry E80",
            "subtitle": "Extended-Wheelbase 6-Seat Model Y Variant (E80)",
            "category": "SUVs",
            "badge": "CODENAME E80",
            "defaultPaint": "Deep Blue Metallic",
            "scn": ego_models / "BayberryE80/BayberryE80.scn",
            "tscn": ego_tscn / "BayberryE80/BayberryE80.tscn",
            "wheel_scn": ego_models / "Wheels_Bayberry/Helix2/Helix2.scn",
            "wheel_tscn": ego_tscn / "Wheels_Bayberry/Helix2/Helix2.tscn",
            "rotate_y_neg90": True,
            "specs": {"range": "345 mi", "zeroToSixty": "3.7 s", "topSpeed": "155 mph", "power": "465 hp"},
        },
        {
            "id": "semi",
            "name": "Tesla Semi",
            "subtitle": "Class 8 All-Electric Heavy Duty Semi Truck",
            "category": "Trucks & Commercial",
            "badge": "CLASS 8 SEMI",
            "defaultPaint": "Pearl White",
            "scn": ego_models / "Semi/Semi.scn",
            "tscn": ego_tscn / "Semi/Semi.tscn",
            "wheel_scn": ego_models / "Wheels_Semi/Wheel_F_Semi.scn",
            "wheel_tscn": ego_tscn / "Wheels_Semi/Wheel_F_Semi.tscn",
            "specs": {"range": "500 mi", "zeroToSixty": "20.0 s", "topSpeed": "65 mph", "power": "1,020 hp"},
        },
        {
            "id": "poppyseed",
            "name": "Project Poppyseed (v2023)",
            "subtitle": "Internal v2023 Architecture Vehicle Asset",
            "category": "Sedans",
            "badge": "CODENAME POPPYSEED",
            "defaultPaint": "Deep Blue Metallic",
            "scn": ego_models / "v2023/Poppyseed/Poppyseed.scn",
            "tscn": ego_tscn / "v2023/Poppyseed/Poppyseed.tscn",
            "wheel_scn": ego_models / "v2023/Wheels/Glider.scn",
            "wheel_tscn": ego_tscn / "v2023/Wheels/Glider.tscn",
            "specs": {"range": "358 mi", "zeroToSixty": "3.1 s", "topSpeed": "162 mph", "power": "490 hp"},
        },
        {
            "id": "models_legacy",
            "name": "Model S (Raven / Legacy)",
            "subtitle": "Modular OBJ Architecture • Panoramic Roof",
            "category": "Sedans",
            "badge": "RAVEN",
            "defaultPaint": "Solid Black",
            "legacy_tscn": ego_tscn / "S/Model_S.tscn",
            "wheel_scn": ego_models / "Wheels_X_S/Objects/Wheel_Turbine.mesh",
            "specs": {"range": "402 mi", "zeroToSixty": "2.3 s", "topSpeed": "163 mph", "power": "778 hp"},
        },
        {
            "id": "modelx_legacy",
            "name": "Model X (Raven / Legacy)",
            "subtitle": "Modular OBJ Architecture • 5-Seater Cabin",
            "category": "SUVs",
            "badge": "RAVEN SUV",
            "defaultPaint": "Pearl White",
            "legacy_tscn": ego_tscn / "X/Model_X.tscn",
            "wheel_scn": ego_models / "Wheels_X_S/Objects/Wheel_Turbine.mesh",
            "specs": {"range": "371 mi", "zeroToSixty": "2.6 s", "topSpeed": "163 mph", "power": "778 hp"},
        },
    ]

    source_names = {'cybertruck': 'Cybertruck', 'model3_high': 'Model 3 · 3_High', 'modely_high': 'Model Y · Y_High', 'models_plaid': 'Model S · Palladium', 'modelx_plaid': 'Model X · Palladium', 'semi': 'Tesla Semi', 'bayberry': 'Model Y · Bayberry', 'bayberry_e41': 'Bayberry E41', 'bayberry_e80': 'Bayberry E80', 'poppyseed': 'Model 3 · Poppyseed', 'models_legacy': 'Model S · legacy', 'modelx_legacy': 'Model X · legacy'}
    for v in vehicle_specs:
        v["name"] = source_names[v["id"]]
        v["subtitle"] = "APK source: " + str(v.get("tscn",v.get("legacy_tscn")).relative_to(EXTRACTED_ROOT))
        v["specs"] = None
        out_glb = OUT_DIR / f"{v['id']}.glb"
        print(f"[*] Building vehicle GLB: {v['name']} -> {out_glb.name}...")
        if "legacy_tscn" in v:
            stats = build_legacy_tscn_vehicle(v["legacy_tscn"], v["wheel_scn"], out_glb)
        else:
            stats = build_vehicle_glb(
                v["scn"],
                v.get("tscn"),
                v.get("wheel_scn"),
                v.get("wheel_tscn"),
                out_glb,
                rotate_y_neg90=v.get("rotate_y_neg90", False),
                extra_attachments=v.get("extras"),
            )
        catalog["vehicles"].append({
            "id": v["id"],
            "name": v["name"],
            "subtitle": v["subtitle"],
            "category": v["category"],
            "badge": v["badge"],
            "defaultPaint": v["defaultPaint"],
            "file": f"models/{out_glb.name}",
            "specs": v["specs"],
            **stats,
        })
        print(f"    -> {stats['vertices']:,} verts, {stats['triangles']:,} tris ({stats['size_bytes'] / (1024*1024):.2f} MB)")

    # Standalone Wheels
    wheel_specs = [
        ("wheel_halo", "20\" Warp Wheel (Model 3 Performance)", ego_models / "Wheels_P3/Wheel_Halo.scn", ego_tscn / "Wheels_P3/Wheel_Halo.tscn"),
        ("wheel_riptide", "19\" Nova Wheel (Model 3 Highland)", ego_models / "Wheels_P3/Wheel_Riptide.scn", ego_tscn / "Wheels_P3/Wheel_Riptide.tscn"),
        ("wheel_standard_p3", "18\" Photon Wheel (Model 3 Highland)", ego_models / "Wheels_P3/Wheel_Standard.scn", ego_tscn / "Wheels_P3/Wheel_Standard.tscn"),
        ("wheel_cybertruck_premium", "20\" Cyberwheel + Aero Cover", ego_models / "Cybertruck/Wheels/Wheel_Cybertruck_Premium.scn", ego_tscn / "Cybertruck/Wheels/Wheel_Cybertruck_Premium.tscn"),
        ("wheel_cybertruck_nocap", "20\" Cybertruck Core Rim (No Cap)", ego_models / "Cybertruck/Wheels/Wheel_Cybertruck_Premium_No_Cap.scn", None),
        ("wheel_arachnid21", "21\" Arachnid Wheel (Model S Plaid)", ego_models / "Wheels_Palladium/Arachnid21.scn", ego_tscn / "Wheels_Palladium/Arachnid21.tscn"),
        ("wheel_cardenio", "19\" Tempest Wheel (Model S)", ego_models / "Wheels_Palladium/Cardenio.scn", ego_tscn / "Wheels_Palladium/Cardenio.tscn"),
        ("wheel_cyberstream", "20\" Cyberstream Wheel (Model X Plaid)", ego_models / "Wheels_Palladium/Cyberstream.scn", ego_tscn / "Wheels_Palladium/Cyberstream.tscn"),
        ("wheel_turbine22", "22\" Turbine Wheel (Model X Plaid)", ego_models / "Wheels_Palladium/New_Turbine_22.scn", ego_tscn / "Wheels_Palladium/New_Turbine_22.tscn"),
        ("wheel_uberhelix", "20\" Uberhelix Wheel (Bayberry / Juniper)", ego_models / "Wheels_Bayberry/Uberhelix/Uberhelix_20_Caps.scn", None),
        ("wheel_helix2", "20\" Helix 2.0 Wheel (Model Y Juniper)", ego_models / "Wheels_Bayberry/Helix2/Helix2.scn", None),
        ("wheel_gemini_dark", "19\" Gemini Dark Wheel (Model Y)", ego_models / "Wheels_Bayberry/GeminiDark/GeminiDark.scn", None),
        ("wheel_uberturbine", "21\" Uberturbine Wheel", ego_models / "Wheels/Objects/Wheel_Uberturbine.mesh", ego_tscn / "Wheels/Wheel_Uberturbine.tscn"),
        ("wheel_zerog", "20\" Zero-G Track Package Wheel", ego_models / "Wheels/Objects/Wheel_ZeroG.mesh", ego_tscn / "Wheels/Wheel_ZeroG.tscn"),
    ]

    for wid, wname, wscn, wtscn in wheel_specs:
        if not wscn.exists():
            continue
        out_glb = OUT_DIR / f"{wid}.glb"
        stats = build_standalone_glb(wscn, wtscn, out_glb)
        catalog["wheels"].append({
            "id": wid,
            "name": wname,
            "subtitle": "Tesla OEM Wheel & Tire Assembly",
            "category": "Wheels & Brakes",
            "badge": "OEM WHEEL",
            "file": f"models/{out_glb.name}",
            **stats,
        })
        print(f"[+] Built wheel GLB: {wname} ({stats['triangles']:,} tris)")

    # Energy, Charging & Accessories
    energy_specs = [
        ("cybertruck_basecamp", "Cybertruck BaseCamp Tent", "Bed-Mounted Inflatable Expedition Tent", "Accessories & Energy", "ACCESSORY", ego_models / "Cybertruck/BaseCamp.scn"),
        ("cybertruck_lightbar", "Cybertruck Off-Road Lightbar", "Roof-Mounted Laser/LED Lightbar", "Accessories & Energy", "ACCESSORY", ego_models / "Cybertruck/Lightbar.scn"),
        ("brakes_palladium", "Plaid Carbon-Ceramic Brake Caliper", "Palladium Red Performance Brake Assembly", "Wheels & Brakes", "BRAKES", resolve_res_path("res://Ego/Brakes_Palladium/Palladium_Brakes_Perf_F.fbx")),
        ("energy_megapack", "Tesla Megapack 2XL", "Utility-Scale Energy Storage System", "Accessories & Energy", "TESLA ENERGY", resolve_res_path("res://Energy/SiteMap/Objects/Megapack.glb")),
        ("energy_powerwall", "Tesla Powerwall", "Home Battery Energy Storage Unit", "Accessories & Energy", "TESLA ENERGY", resolve_res_path("res://Energy/SiteMap/Objects/Powerwall2.glb")),
        ("energy_powerpack", "Tesla Powerpack", "Commercial Energy Storage Unit", "Accessories & Energy", "TESLA ENERGY", resolve_res_path("res://Energy/SiteMap/Objects/Powerpack.glb")),
        ("energy_wall_connector", "Tesla Wall Connector", "Gen 3 Home Charging Station", "Accessories & Energy", "CHARGING", resolve_res_path("res://Energy/SiteMap/Objects/WallConnector.glb")),
        ("energy_solar_home", "Tesla Solar Roof Residence", "Modern Home with Integrated Solar Roof", "Accessories & Energy", "TESLA SOLAR", resolve_res_path("res://Energy/SiteMap/Objects/ResidentialModernStructure.glb")),
        ("energy_generator", "Industrial Backup Generator", "Commercial Microgrid Generator Asset", "Accessories & Energy", "TESLA ENERGY", resolve_res_path("res://Energy/SiteMap/Objects/Generator_Industrial.fbx")),
    ]

    # Fallback lookup in REA .import by prefix if source_file wasn't in IMPORT_MAP
    rea_import_dir = REA_GODOT_ROOT / ".import"
    for eid, ename, esub, ecat, ebadge, escn in energy_specs:
        if escn is None or not escn.exists():
            prefix = eid.split("_")[-1].capitalize()
            if eid == "energy_solar_home":
                prefix = "ResidentialModernStructure"
            elif eid == "energy_wall_connector":
                prefix = "WallConnector.glb"
            elif eid == "energy_powerwall":
                prefix = "Powerwall2"
            elif eid == "energy_generator":
                prefix = "Generator_Industrial"
            if rea_import_dir.exists():
                matches = list(rea_import_dir.glob(f"{prefix}*.scn"))
                if matches:
                    escn = matches[0]
        if escn and escn.exists():
            out_glb = OUT_DIR / f"{eid}.glb"
            stats = build_standalone_glb(escn, None, out_glb)
            catalog["energy_and_accessories"].append({
                "id": eid,
                "name": ename,
                "subtitle": esub,
                "category": ecat,
                "badge": ebadge,
                "file": f"models/{out_glb.name}",
                **stats,
            })
            print(f"[+] Built energy/accessory GLB: {ename} ({stats['triangles']:,} tris)")

    catalog_path = OUT_DIR / "catalog.json"
    catalog_path.write_text(json.dumps(catalog, indent=2))
    print(f"\n[+] Wrote complete 3D catalog ({len(catalog['vehicles'])} vehicles, {len(catalog['wheels'])} wheels, {len(catalog['energy_and_accessories'])} energy/accessories) to {catalog_path}")


if __name__ == "__main__":
    main()
