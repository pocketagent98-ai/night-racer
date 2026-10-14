extends Node3D
##
## NIGHT RACER — an endless 3D highway racer (Race Master 3D style).
##
## The world scrolls toward a fixed player car; traffic and scenery are
## recycled. Everything in the scene is built in code from one root node,
## which keeps the project small and easy for an AI assistant to edit.
##

# ============================== TUNABLES ==============================
const ROAD_WIDTH := 13.0
const LANES := 4
const LANE_W := ROAD_WIDTH / float(LANES)
const ROAD_LEN := 700.0
const ROAD_CENTER_Z := -300.0
const TILE_LEN := 18.0

const PLAYER_LIMIT := ROAD_WIDTH * 0.5 - 0.9

const START_SPEED := 22.0
const MAX_SPEED := 70.0
const ACCEL := 1.1
const LATERAL_SPEED := 12.0

const TRAFFIC_COUNT := 16
const SPAWN_Z := -240.0
const DESPAWN_Z := 30.0

const CAR_DIR := "res://assets/cars/"
const PLAYER_CAR := "race.glb"
const TRAFFIC_CARS := [
	"sedan.glb", "van.glb", "taxi.glb", "truck.glb",
	"suv.glb", "hatchback-sports.glb", "police.glb", "truck-flat.glb",
]
const CAR_Y := 0.3
const CAR_HALF_W := 0.85
const CAR_HALF_L := 1.5

const SCENERY_SPAN := 640.0
const BUILDING_COUNT := 24
const POLE_COUNT := 32

enum State { MENU, PLAY, OVER }

# ============================== STATE ==============================
var state: State = State.MENU
var speed := 0.0
var distance := 0.0
var best := 0.0
var player_x := 0.0
var target_x := 0.0
var steer_dir := 0.0

var rng := RandomNumberGenerator.new()

var road_mat: ShaderMaterial
var player: Node3D
var player_wheels: Array = []
var camera: Camera3D
var traffic: Array = []
var buildings: Array = []
var poles: Array = []

var dist_label: Label
var speed_label: Label
var best_label: Label
var overlay: Control
var overlay_title: Label
var overlay_sub: Label

var engine_snd: AudioStreamPlayer
var impact_snd: AudioStreamPlayer
var skid_snd: AudioStreamPlayer


# ============================== LIFECYCLE ==============================
func _ready() -> void:
	rng.randomize()
	_load_best()
	_build_environment()
	_build_ground_and_road()
	_build_roadside()
	_build_player()
	_build_traffic()
	_build_camera()
	_build_audio()
	_build_hud()
	_start_menu()


func _process(delta: float) -> void:
	var playing := state == State.PLAY

	if playing:
		speed = minf(MAX_SPEED, speed + ACCEL * delta)
		distance += speed * delta
	elif state == State.OVER:
		speed = maxf(0.0, speed - 45.0 * delta)

	_read_input()
	_update_steering(delta, playing)
	_move_traffic(delta)
	if playing:
		_check_collision()
	_update_scenery(delta)
	_update_road(delta)
	_update_camera(delta)
	_update_wheels(delta)
	_update_audio(playing)
	_update_hud()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if state != State.PLAY:
			_start_play()
	elif event is InputEventScreenDrag:
		target_x = clampf(target_x + event.relative.x * 0.02, -PLAYER_LIMIT, PLAYER_LIMIT)
	elif event is InputEventMouseButton and event.pressed:
		if state != State.PLAY:
			_start_play()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target_x = clampf(target_x + event.relative.x * 0.02, -PLAYER_LIMIT, PLAYER_LIMIT)


func _read_input() -> void:
	if Input.is_action_just_pressed("ui_accept") and state != State.PLAY:
		_start_play()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()


# ============================== BUILD: ENVIRONMENT ==============================
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.85)
	env.ambient_light_energy = 0.85
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.13)
	env.fog_density = 0.011
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 1.1
	moon.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	moon.shadow_enabled = false
	add_child(moon)


func _build_ground_and_road() -> void:
	var ground := MeshInstance3D.new()
	var gmesh := PlaneMesh.new()
	gmesh.size = Vector2(260.0, ROAD_LEN + 120.0)
	ground.mesh = gmesh
	ground.position = Vector3(0.0, -0.02, ROAD_CENTER_Z)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.04, 0.05, 0.09)
	gmat.roughness = 1.0
	ground.material_override = gmat
	add_child(ground)

	var road := MeshInstance3D.new()
	var rmesh := PlaneMesh.new()
	rmesh.size = Vector2(ROAD_WIDTH, ROAD_LEN)
	road.mesh = rmesh
	road.position = Vector3(0.0, 0.0, ROAD_CENTER_Z)
	road_mat = ShaderMaterial.new()
	road_mat.shader = load("res://assets/shaders/road.gdshader")
	road_mat.set_shader_parameter("road_tex", load("res://assets/textures/road.png"))
	road_mat.set_shader_parameter("uv_scale", Vector2(1.0, ROAD_LEN / TILE_LEN))
	road_mat.set_shader_parameter("uv_offset", Vector2(0.0, 0.0))
	road.material_override = road_mat
	add_child(road)


func _build_roadside() -> void:
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.10, 0.11, 0.15)
	bar_mat.roughness = 1.0

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.2, 0.6, 1.0)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.3, 0.7, 1.0)
	glow_mat.emission_energy_multiplier = 3.0

	for side in [-1.0, 1.0]:
		var bx: float = side * (ROAD_WIDTH * 0.5 + 0.25)

		var bar := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(0.4, 0.7, ROAD_LEN)
		bar.mesh = bmesh
		bar.position = Vector3(bx, 0.35, ROAD_CENTER_Z)
		bar.material_override = bar_mat
		add_child(bar)

		var strip := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		smesh.size = Vector3(0.44, 0.06, ROAD_LEN)
		strip.mesh = smesh
		strip.position = Vector3(bx, 0.73, ROAD_CENTER_Z)
		strip.material_override = glow_mat
		add_child(strip)

	# Neon city skyline (recycled toward the player).
	var bshader: Shader = load("res://assets/shaders/building.gdshader")
	var btex: Texture2D = load("res://assets/textures/building.png")
	var spacing := SCENERY_SPAN / float(BUILDING_COUNT)
	for i in BUILDING_COUNT:
		for side in [-1.0, 1.0]:
			var h := rng.randf_range(9.0, 34.0)
			var w := rng.randf_range(7.0, 14.0)
			var d := rng.randf_range(7.0, 14.0)

			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w, h, d)
			mi.mesh = bm

			var mat := ShaderMaterial.new()
			mat.shader = bshader
			mat.set_shader_parameter("tex", btex)
			mi.material_override = mat
			mi.set_instance_shader_parameter(
				"uv_scale",
				Vector2(maxf(1.0, roundf(w / 3.0)), maxf(1.0, roundf(h / 3.0)))
			)

			var z := -SCENERY_SPAN + spacing * float(i) + rng.randf_range(-6.0, 6.0)
			var x: float = side * (ROAD_WIDTH * 0.5 + 6.0 + rng.randf_range(0.0, 14.0) + w * 0.5)
			mi.position = Vector3(x, h * 0.5 - 0.02, z)
			add_child(mi)
			buildings.append(mi)

	# Street lights.
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.14, 0.15, 0.19)
	pole_mat.roughness = 0.8

	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.85, 0.5)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.8, 0.45)
	lamp_mat.emission_energy_multiplier = 4.0

	var pspacing := SCENERY_SPAN / float(POLE_COUNT)
	for i in POLE_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var holder := Node3D.new()

		var pole := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.18, 6.0, 0.18)
		pole.mesh = pm
		pole.position = Vector3(0.0, 3.0, 0.0)
		pole.material_override = pole_mat
		holder.add_child(pole)

		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.5, 0.16, 0.9)
		lamp.mesh = lm
		lamp.position = Vector3(-side * 0.6, 5.9, 0.0)
		lamp.material_override = lamp_mat
		holder.add_child(lamp)

		var z := -SCENERY_SPAN + pspacing * float(i)
		holder.position = Vector3(side * (ROAD_WIDTH * 0.5 + 1.4), 0.0, z)
		add_child(holder)
		poles.append(holder)


# ============================== BUILD: CARS ==============================
func _instantiate_car(fname: String) -> Node3D:
	var path := CAR_DIR + fname
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Missing car model: " + path)
		return Node3D.new()
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		return inst as Node3D
	var holder := Node3D.new()
	holder.add_child(inst)
	return holder


func _build_player() -> void:
	player = Node3D.new()
	player.position = Vector3(0.0, CAR_Y, 0.0)
	add_child(player)

	var model := _instantiate_car(PLAYER_CAR)
	model.rotation.y = PI          # Kenney models face +Z; Godot forward is -Z
	player.add_child(model)

	player_wheels.clear()
	for wheel_name in ["wheel-front-left", "wheel-front-right", "wheel-back-left", "wheel-back-right"]:
		var w := model.find_child(wheel_name, true, false)
		if w != null:
			player_wheels.append(w)

	_add_headlight(player, -0.42)
	_add_headlight(player, 0.42)


func _add_headlight(parent: Node3D, x: float) -> void:
	var light := SpotLight3D.new()
	light.position = Vector3(x, 0.65, -1.2)
	light.spot_range = 40.0
	light.spot_angle = 32.0
	light.light_energy = 2.2
	light.light_color = Color(1.0, 0.96, 0.85)
	light.shadow_enabled = false
	parent.add_child(light)


func _build_traffic() -> void:
	for i in TRAFFIC_COUNT:
		var fname: String = TRAFFIC_CARS[rng.randi_range(0, TRAFFIC_CARS.size() - 1)]
		var holder := Node3D.new()
		var model := _instantiate_car(fname)
		model.rotation.y = PI
		holder.add_child(model)
		add_child(holder)
		traffic.append({"node": holder, "ratio": 0.5})


func _place_traffic(entry: Dictionary, spread: bool) -> void:
	var z := 0.0
	if spread:
		z = rng.randf_range(-260.0, -35.0)
	else:
		z = SPAWN_Z - rng.randf_range(0.0, 50.0)
	var lane := _pick_lane(z, entry)
	var x := -ROAD_WIDTH * 0.5 + LANE_W * (float(lane) + 0.5)
	entry["node"].position = Vector3(x, CAR_Y, z)
	entry["ratio"] = rng.randf_range(0.40, 0.72)


func _pick_lane(z: float, entry: Dictionary) -> int:
	var fallback := rng.randi_range(0, LANES - 1)
	for attempt in 10:
		var lane := rng.randi_range(0, LANES - 1)
		if _lane_clear(lane, z, entry):
			return lane
	return fallback


func _lane_clear(lane: int, z: float, entry: Dictionary) -> bool:
	for other in traffic:
		if other == entry:
			continue
		var n: Node3D = other["node"]
		if absf(n.position.z - z) < 24.0:
			var olane := int(roundf((n.position.x + ROAD_WIDTH * 0.5) / LANE_W - 0.5))
			if olane == lane:
				return false
	return true


# ============================== BUILD: CAMERA / AUDIO / HUD ==============================
func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.position = Vector3(0.0, 3.7, 8.3)
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.2, -14.0), Vector3.UP)


func _build_audio() -> void:
	engine_snd = _make_sound("res://assets/audio/engine.ogg", true)
	engine_snd.volume_db = -10.0
	impact_snd = _make_sound("res://assets/audio/impact.ogg", false)
	impact_snd.volume_db = -3.0
	skid_snd = _make_sound("res://assets/audio/skid.ogg", true)
	skid_snd.volume_db = -14.0


func _make_sound(path: String, looping: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream: AudioStream = load(path)
	if stream != null and looping and stream is AudioStreamOggVorbis:
		stream.loop = true
	p.stream = stream
	add_child(p)
	return p


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	dist_label = _make_label(root, 44, Color(1, 1, 1))
	dist_label.offset_left = 26.0
	dist_label.offset_top = 18.0
	dist_label.offset_right = 420.0
	dist_label.offset_bottom = 70.0

	best_label = _make_label(root, 22, Color(0.75, 0.85, 1.0))
	best_label.anchor_left = 1.0
	best_label.anchor_right = 1.0
	best_label.offset_left = -420.0
	best_label.offset_right = -26.0
	best_label.offset_top = 24.0
	best_label.offset_bottom = 56.0
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	speed_label = _make_label(root, 30, Color(0.9, 0.95, 1.0))
	speed_label.anchor_left = 1.0
	speed_label.anchor_right = 1.0
	speed_label.anchor_top = 1.0
	speed_label.anchor_bottom = 1.0
	speed_label.offset_left = -420.0
	speed_label.offset_right = -26.0
	speed_label.offset_top = -66.0
	speed_label.offset_bottom = -22.0
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)

	overlay_title = _make_label(vb, 64, Color(1, 1, 1))
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_sub = _make_label(vb, 26, Color(0.85, 0.9, 1.0))
	overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _make_label(parent: Node, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l


# ============================== GAME FLOW ==============================
func _start_menu() -> void:
	state = State.MENU
	speed = START_SPEED
	distance = 0.0
	player_x = 0.0
	target_x = 0.0
	_reset_traffic()
	if overlay:
		overlay.visible = true
		overlay_title.text = "NIGHT RACER"
		overlay_sub.text = "Dodge the traffic. Steer with ← →  or  A / D.\nPress SPACE or tap to start"


func _start_play() -> void:
	state = State.PLAY
	speed = START_SPEED
	distance = 0.0
	player_x = 0.0
	target_x = 0.0
	_reset_traffic()
	if overlay:
		overlay.visible = false
	if engine_snd != null and not engine_snd.playing:
		engine_snd.play()
	if skid_snd != null and skid_snd.playing:
		skid_snd.stop()


func _crash() -> void:
	state = State.OVER
	if impact_snd != null:
		impact_snd.play()
	if skid_snd != null and skid_snd.playing:
		skid_snd.stop()
	if distance > best:
		best = distance
		_save_best()
	if overlay:
		overlay.visible = true
		overlay_title.text = "CRASHED!"
		overlay_sub.text = "Distance %d m      Best %d m\nPress SPACE or tap to race again" % [int(distance), int(best)]


func _reset_traffic() -> void:
	for entry in traffic:
		_place_traffic(entry, true)


# ============================== UPDATE ==============================
func _update_steering(delta: float, playing: bool) -> void:
	var dir := 0.0
	if playing:
		if _left_pressed():
			dir -= 1.0
		if _right_pressed():
			dir += 1.0
	steer_dir = dir

	target_x = clampf(target_x + dir * LATERAL_SPEED * delta, -PLAYER_LIMIT, PLAYER_LIMIT)
	if not playing:
		target_x = lerpf(target_x, 0.0, clampf(2.0 * delta, 0.0, 1.0))

	player_x = lerpf(player_x, target_x, clampf(12.0 * delta, 0.0, 1.0))
	if player != null:
		player.position.x = player_x
		player.rotation.z = lerpf(player.rotation.z, -dir * 0.09, clampf(8.0 * delta, 0.0, 1.0))


func _left_pressed() -> bool:
	return Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A)


func _right_pressed() -> bool:
	return Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)


func _move_traffic(delta: float) -> void:
	for entry in traffic:
		var n: Node3D = entry["node"]
		var traffic_speed: float = speed * float(entry["ratio"])
		n.position.z += (speed - traffic_speed) * delta
		if n.position.z > DESPAWN_Z:
			_place_traffic(entry, false)


func _check_collision() -> void:
	for entry in traffic:
		var n: Node3D = entry["node"]
		if absf(n.position.x - player_x) < CAR_HALF_W * 2.0 \
				and absf(n.position.z) < CAR_HALF_L * 2.0:
			_crash()
			return


func _update_scenery(delta: float) -> void:
	var dz := speed * delta
	for b in buildings:
		b.position.z += dz
		if b.position.z > 70.0:
			b.position.z -= SCENERY_SPAN
	for p in poles:
		p.position.z += dz
		if p.position.z > 70.0:
			p.position.z -= SCENERY_SPAN


func _update_road(delta: float) -> void:
	if road_mat == null:
		return
	var off: Vector2 = road_mat.get_shader_parameter("uv_offset")
	off.y -= speed * delta / TILE_LEN
	road_mat.set_shader_parameter("uv_offset", off)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target_pos := Vector3(player_x * 0.5, 3.7, 8.3)
	camera.position = camera.position.lerp(target_pos, clampf(4.0 * delta, 0.0, 1.0))
	camera.look_at(Vector3(player_x * 0.75, 1.2, -14.0), Vector3.UP)


func _update_wheels(delta: float) -> void:
	var spin := speed * delta / 0.34
	for w in player_wheels:
		w.rotate_x(spin)


func _update_audio(playing: bool) -> void:
	if engine_snd != null and engine_snd.playing:
		engine_snd.pitch_scale = clampf(0.75 + (speed / MAX_SPEED) * 1.05, 0.6, 1.9)
	if skid_snd == null:
		return
	var want_skid := playing and absf(steer_dir) > 0.5 and speed > 30.0
	if want_skid and not skid_snd.playing:
		skid_snd.play()
	elif not want_skid and skid_snd.playing:
		skid_snd.stop()


func _update_hud() -> void:
	if dist_label != null:
		dist_label.text = "%d m" % int(distance)
	if speed_label != null:
		speed_label.text = "%d km/h" % int(speed * 3.6)
	if best_label != null:
		best_label.text = "BEST  %d m" % int(best)


# ============================== PERSISTENCE ==============================
func _load_best() -> void:
	if not FileAccess.file_exists("user://best.txt"):
		return
	var f := FileAccess.open("user://best.txt", FileAccess.READ)
	if f != null:
		best = float(f.get_as_text())


func _save_best() -> void:
	var f := FileAccess.open("user://best.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(str(best))
