"""
Headless renderer for wallpaper.blend, driven entirely by environment
variables so it can run unattended inside a Nix derivation:

  WALLPAPER_COLORS  comma-separated hex colors (no '#'), evenly spaced
                     left-to-right across the ramp, e.g. "353535,a33a45,..."
  WALLPAPER_WIDTH   output width in pixels
  WALLPAPER_HEIGHT  output height in pixels
  WALLPAPER_OUT     output PNG path
  WALLPAPER_SAMPLES optional, Cycles sample count (default 64)

Targets the "Color Ramp.001" node in the "Material.002" material -- the
ramp actually wired into the rendered output (see Material.001's ramp,
which is unused/orphaned in the current file). Drives Cycles on CPU only:
EEVEE needs a GL context that a sandboxed Nix build never has, on any
machine, regardless of GPU.
"""
import os
import bpy


def srgb_to_linear(v):
    v = v / 255.0
    if v <= 0.04045:
        return v / 12.92
    return ((v + 0.055) / 1.055) ** 2.4


def hex_to_linear_rgba(hex_str):
    hex_str = hex_str.strip().lstrip("#")
    r, g, b = (int(hex_str[i:i + 2], 16) for i in (0, 2, 4))
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)


def set_ramp(node, colors):
    ramp = node.color_ramp
    elements = ramp.elements
    n = len(colors)

    while len(elements) > 1:
        elements.remove(elements[-1])

    elements[0].position = 0.0
    elements[0].color = hex_to_linear_rgba(colors[0])

    for i, color in enumerate(colors[1:], start=1):
        pos = i / (n - 1)
        el = elements.new(pos)
        el.color = hex_to_linear_rgba(color)


def main():
    colors = os.environ["WALLPAPER_COLORS"].split(",")
    width = int(os.environ["WALLPAPER_WIDTH"])
    height = int(os.environ["WALLPAPER_HEIGHT"])
    out_path = os.environ["WALLPAPER_OUT"]
    samples = int(os.environ.get("WALLPAPER_SAMPLES", "64"))

    mat = bpy.data.materials["Material.002"]
    node = mat.node_tree.nodes["Color Ramp.001"]
    set_ramp(node, colors)

    scene = bpy.data.scenes["Scene"]
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"

    # Render into memory and save explicitly, rather than
    # render(write_still=True) with scene.render.filepath set -- that path
    # gets a frame-number suffix inserted before the extension, which isn't
    # what we want for a single exact output path.
    bpy.ops.render.render(write_still=False)
    bpy.data.images["Render Result"].save_render(filepath=out_path)


main()
