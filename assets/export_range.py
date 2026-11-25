"""Export the training range in world units from Blender."""
from pathlib import Path

import bpy


def point(x, y, z):
    # The runtime reflects glTF Z and Blender exports from Z-up to Y-up.
    return (x, z, y)


def material(name, rgb):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = 0.8
    return result


def box(name, center, half, surface):
    bpy.ops.mesh.primitive_cube_add(size=2, location=point(*center))
    item = bpy.context.object
    item.name = "Solid_" + name
    item.scale = point(*half)
    item.data.materials.append(surface)


def marker(name, xyz):
    item = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(item)
    item.location = point(*xyz)


bpy.ops.wm.read_factory_settings(use_empty=True)
floor = material("Floor", (0.20, 0.23, 0.24))
wall = material("Walls", (0.26, 0.35, 0.39))
blue = material("Blue", (0.02, 0.42, 0.73))
orange = material("Orange", (0.74, 0.16, 0.035))

ground = -2.65
box("Floor", (0, ground - 0.15, 3), (6, 0.15, 7), floor)
box("Left", (-6, ground + 1.3, 3), (0.18, 1.3, 7), wall)
box("Right", (6, ground + 1.3, 3), (0.18, 1.3, 7), wall)
box("Front", (0, ground + 1.3, -4), (6, 1.3, 0.18), wall)
box("Back", (0, ground + 1.3, 10), (6, 1.3, 0.18), wall)
box("Step", (-2, ground + 0.3, 1.25), (0.8, 0.3, 0.65), blue)
box("Cover", (-2.5, ground + 1.0, 4.35), (0.92, 1.0, 0.45), orange)

marker("PlayerSpawn", (0, ground, -2.75))
marker("TargetCenter", (0, ground + 1.05, 9.66))
marker("CrateCenter", (2.25, 2.3, 0.05))
for index, (x, z) in enumerate(((-3.9, 7.5), (3.9, 7.5), (3.9, 5.7), (-3.9, 5.7))):
    marker(f"Patrol_{index}", (x, ground, z))
for index, (x, z) in enumerate((
    (-4.15, 3.15), (-0.85, 3.15), (-0.85, 5.55), (-4.15, 5.55),
    (-3.42, -0.04), (-0.61, -0.04), (-0.61, 2.52), (-3.42, 2.52),
)):
    marker(f"Nav_{index}", (x, ground, z))

bpy.ops.export_scene.gltf(
    filepath=str(Path(__file__).with_name("range.glb")),
    export_format="GLB",
)
