extends Node2D
## Ground-only 2D shadow approximation for the fixed environment lighting.
## The source illustration stays static; no running animation is introduced.

const CAST_SHADER := preload("res://cast_shadow.gdshader")
const CONTACT_SHADER := preload("res://contact_shadow.gdshader")
# Source: v108-professional-environment/build_scene.py:167, SUN Euler XYZ
# (37, -39, -35) degrees; ray = Rz*Ry*Rx*(0,0,-1).
const SUN_RAY_WORLD := Vector3(0.75689078, 0.20469986, -0.62065636)
const SHADOW_SCREEN_PER_METRE_HEIGHT := Vector2(57.81335966, -12.80787436)
const SCREEN_HEIGHT_PIXEL_PER_METRE := 27.191771797382927
# Keep the light's direction but restrain the illustrative projection length.
# This is an art-controlled billboard approximation, not a 3D shadow solution.
const CAST_LENGTH_GAIN := 0.62
const CAST_OPACITY := 0.22
const CONTACT_OPACITY := 0.30

var target: CharacterBody2D
var cast_sprite: Sprite2D
var contact_mesh: MeshInstance2D
var cast_material: ShaderMaterial
var contact_material: ShaderMaterial
var current_direction := -1

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cast_sprite = Sprite2D.new()
	cast_sprite.name = "SoftDirectionalSilhouette"
	cast_sprite.texture = target.sprite.texture
	cast_sprite.centered = false
	cast_sprite.region_enabled = true
	cast_sprite.region_filter_clip_enabled = true
	cast_material = ShaderMaterial.new()
	cast_material.shader = CAST_SHADER
	cast_material.set_shader_parameter("silhouette_atlas", cast_sprite.texture)
	cast_material.set_shader_parameter("opacity", CAST_OPACITY)
	cast_sprite.material = cast_material
	var vertical_basis: Vector2 = -SHADOW_SCREEN_PER_METRE_HEIGHT / SCREEN_HEIGHT_PIXEL_PER_METRE * CAST_LENGTH_GAIN * target.ART_SCALE
	cast_sprite.transform = Transform2D(Vector2(target.ART_SCALE, 0), vertical_basis, Vector2.ZERO)
	add_child(cast_sprite)
	contact_mesh = MeshInstance2D.new()
	contact_mesh.name = "SoftBootContact"
	var quad := QuadMesh.new()
	quad.size = Vector2(32, 12)
	contact_mesh.mesh = quad
	contact_material = ShaderMaterial.new()
	contact_material.shader = CONTACT_SHADER
	contact_material.set_shader_parameter("opacity", CONTACT_OPACITY)
	contact_mesh.material = contact_material
	add_child(contact_mesh)
	update_from_player()

func _process(_delta: float) -> void:
	update_from_player()

func update_from_player() -> void:
	if not is_instance_valid(target):
		visible = false
		return
	global_position = target.global_position
	if current_direction == target.direction_index:
		return
	current_direction = target.direction_index
	var region: Rect2 = target.REGIONS[current_direction]
	var foot: Vector2 = target.FEET[current_direction]
	cast_sprite.region_rect = region
	cast_sprite.offset = -foot
	var texture_size: Vector2 = cast_sprite.texture.get_size()
	cast_material.set_shader_parameter("atlas_region", Vector4(region.position.x / texture_size.x, region.position.y / texture_size.y, region.end.x / texture_size.x, region.end.y / texture_size.y))
	cast_material.set_shader_parameter("foot_uv_y", (region.position.y + foot.y) / texture_size.y)
	cast_material.set_shader_parameter("body_uv_height", 450.0 / texture_size.y)
