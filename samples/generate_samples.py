"""Write tiny STL / OBJ / glTF samples used by the viewer and loader tests."""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ASSEMBLY = ROOT / "assembly"


def write_binary_stl(path: Path, triangles: list[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    header = b"VR Model Viewer sample".ljust(80, b"\0")
    body = [header, struct.pack("<I", len(triangles))]
    for a, b, c in triangles:
        n = _normal(a, b, c)
        body.append(struct.pack("<3f", *n))
        body.append(struct.pack("<3f", *a))
        body.append(struct.pack("<3f", *b))
        body.append(struct.pack("<3f", *c))
        body.append(struct.pack("<H", 0))
    path.write_bytes(b"".join(body))


def _normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx = uy * vz - uz * vy
    ny = uz * vx - ux * vz
    nz = ux * vy - uy * vx
    length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
    return (nx / length, ny / length, nz / length)


def box_tris(p0, p1):
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    v = {
        0: (x0, y0, z0),
        1: (x1, y0, z0),
        2: (x1, y1, z0),
        3: (x0, y1, z0),
        4: (x0, y0, z1),
        5: (x1, y0, z1),
        6: (x1, y1, z1),
        7: (x0, y1, z1),
    }
    faces = (
        (0, 3, 2, 1),  # -Z
        (4, 5, 6, 7),  # +Z
        (0, 1, 5, 4),  # -Y
        (3, 7, 6, 2),  # +Y
        (0, 4, 7, 3),  # -X
        (1, 2, 6, 5),  # +X
    )
    tris = []
    for a, b, c, d in faces:
        tris.append((v[a], v[b], v[c]))
        tris.append((v[a], v[c], v[d]))
    return tris


def write_obj_cube(path: Path, size: float = 1.0) -> None:
    h = size * 0.5
    verts = [
        (-h, -h, -h),
        (h, -h, -h),
        (h, h, -h),
        (-h, h, -h),
        (-h, -h, h),
        (h, -h, h),
        (h, h, h),
        (-h, h, h),
    ]
    faces = [
        (1, 4, 3, 2),
        (5, 6, 7, 8),
        (1, 2, 6, 5),
        (4, 8, 7, 3),
        (1, 5, 8, 4),
        (2, 3, 7, 6),
    ]
    lines = ["# VR Model Viewer sample cube", f"o cube_{size:g}m"]
    for x, y, z in verts:
        lines.append(f"v {x} {y} {z}")
    for f in faces:
        lines.append("f " + " ".join(str(i) for i in f))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_gltf_triangle(path: Path) -> None:
    # Minimal glTF 2.0 with an embedded triangle in meters, offset in +X.
    # POSITION: (0,0,0), (1,0,0), (0,1,0)  — 12 floats little-endian
    import base64

    positions = struct.pack("<9f", 0.2, 0.0, 0.0, 1.2, 0.0, 0.0, 0.2, 1.0, 0.0)
    indices = struct.pack("<3H", 0, 1, 2)
    blob = positions + indices
    uri = "data:application/octet-stream;base64," + base64.b64encode(blob).decode("ascii")
    json = """{
  "asset": {"version": "2.0", "generator": "vr-model-viewer-samples"},
  "scene": 0,
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0, "name": "triangle"}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
  "buffers": [{"byteLength": %s, "uri": "%s"}],
  "bufferViews": [
    {"buffer": 0, "byteOffset": 0, "byteLength": 36, "target": 34962},
    {"buffer": 0, "byteOffset": 36, "byteLength": 6, "target": 34963}
  ],
  "accessors": [
    {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0.2, 0.0, 0.0], "max": [1.2, 1.0, 0.0]},
    {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}
  ]
}
""" % (len(blob), uri)
    path.write_text(json, encoding="utf-8")


def main() -> None:
    # 1 m cube for meters / glTF-like scale checks.
    write_obj_cube(ROOT / "cube_meters.obj", 1.0)
    write_gltf_triangle(ROOT / "triangle.gltf")

    # Two STL parts in millimeters sharing one origin: a 40mm base and a 10x40mm post.
    write_binary_stl(ASSEMBLY / "base.stl", box_tris((0, 0, 0), (40, 8, 40)))
    write_binary_stl(ASSEMBLY / "post.stl", box_tris((15, 8, 15), (25, 48, 25)))
    print("Wrote samples under", ROOT)


if __name__ == "__main__":
    main()
