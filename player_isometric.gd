# =============================================================================
# player_isometric.gd
# Skrip CharacterBody2D untuk Action RPG 2.5D Isometric (Godot 4.x)
#
# Fitur:
#   1. Pergerakan analog/vector dengan 8 arah mata angin (N, NE, E, SE, S, SW, W, NW)
#      atau 4 arah (utara/selatan/timur/barat murni) — otomatis terdeteksi dari vektor input.
#   2. Kecepatan gerak dapat diatur lewat @export variable di Inspector.
#   3. Integrasi AnimatedSprite2D: nama animasi diambil dari prefix + arah,
#      contoh: "walk_top", "walk_bottom_left", "idle_right", "attack_top_right".
#   4. State machine sederhana (IDLE / WALK / ATTACK). Saat menyerang, movement
#      dikunci sampai animasi attack selesai.
#   5. Bersih, modular, tanpa API deprecated Godot 4 (mis. `connect(..., self, "method")`
#      lama diganti callable `method.bind()`, dst.)
#
# Cara pakai:
#   - Tempelkan skrip ini pada node bertipe CharacterBody2D.
#   - Jadikan AnimatedSprite2D sebagai ANAK node ini.
#   - Siapkan input map bawaan ("move_left", "move_right", "move_up", "move_down", "attack").
#     Atau ubah fungsi _get_input_direction() untuk memakai action custom milikmu.
# =============================================================================

extends CharacterBody2D

# -----------------------------------------------------------------------------
# Konfigurasi yang bisa diubah dari Inspector
# -----------------------------------------------------------------------------
## Kecepatan gerak player dalam piksel per detik.
@export var speed: float = 200.0

## Jika true, diagonal (mis. walk_top_right) akan dinormalkan agar tidak lebih cepat.
@export var normalize_diagonal: bool = true

## Jika true, hanya gunakan 4 arah mata angin (top/bottom/left/right),
## jika false gunakan 8 arah termasuk diagonal.
@export var use_4_directions_only: bool = false

## Prefix nama animasi untuk tiap state. Contoh: "walk_" + "top" => "walk_top"
@export var anim_prefix_idle: String = "idle_"
@export var anim_prefix_walk: String = "walk_"
@export var anim_prefix_attack: String = "attack_"

## Durasi maksimum serangan (detik). Dipakai sebagai pengaman bila animasi
## tidak memicu sinyal animation_finished.
@export var attack_duration: float = 0.5

# -----------------------------------------------------------------------------
# Enum & variabel state
# -----------------------------------------------------------------------------
## Delapan arah mata angin (dalam derajat kompas) yang dipetakan ke string suffix animasi.
enum Dir { TOP, TOP_RIGHT, RIGHT, BOTTOM_RIGHT, BOTTOM, BOTTOM_LEFT, LEFT, TOP_LEFT }

## State sederhana untuk kontrol pergerakan dan animasi.
enum State { IDLE, WALK, ATTACK }

const DIR_SUFFIX := {
	Dir.TOP:         "top",
	Dir.TOP_RIGHT:   "top_right",
	Dir.RIGHT:       "right",
	Dir.BOTTOM_RIGHT:"bottom_right",
	Dir.BOTTOM:      "bottom",
	Dir.BOTTOM_LEFT: "bottom_left",
	Dir.LEFT:        "left",
	Dir.TOP_LEFT:    "top_left",
}

var _state: State = State.IDLE
var _facing: Dir = Dir.BOTTOM          # Arah hadap terakhir saat idle
var _attack_timer: Timer               # Timer pengaman durasi serangan
var _sprite: AnimatedSprite2D          # Referensi child AnimatedSprite2D

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

func _ready() -> void:
	_cache_sprite_and_signals()
	_setup_attack_timer()


func _physics_process(_delta: float) -> void:
	var input_dir := _get_input_direction()

	match _state:
		State.IDLE:
			if input_dir != Vector2.ZERO:
				_enter_state(State.WALK)
			else:
				velocity = Vector2.ZERO
				move_and_slide()
				_play_state_anim(anim_prefix_idle)

		State.WALK:
			if input_dir == Vector2.ZERO:
				_enter_state(State.IDLE)
			else:
				velocity = input_dir * speed
				_facing = _direction_to_dir(input_dir)
				move_and_slide()
				_play_state_anim(anim_prefix_walk)

		State.ATTACK:
			# Player terkunci selama serangan berlangsung (tidak bisa bergerak).
			velocity = Vector2.ZERO
			move_and_slide()

	# Safety net: jika state ATTACK tapi timer sudah mati dan animasi attack
	# ternyata tidak memicu animation_finished, kembalikan ke IDLE/WALK.
	if _state == State.ATTACK and _attack_timer.time_left <= 0.0:
		_on_attack_finished()

# -----------------------------------------------------------------------------
# Input & Arah
# -----------------------------------------------------------------------------

## Ambil vektor input dari empat aksi dasar. Bisa diganti dengan get_vector()
## bawaan Godot 4 bila ingin langsung memakai deadzone & normalization.
func _get_input_direction() -> Vector2:
	# Alternatif Godot 4 modern:
	# return Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector2.ZERO
	dir.x = Input.get_axis("move_left", "move_right")
	dir.y = Input.get_axis("move_up", "move_down")
	if normalize_diagonal and dir.length_squared() > 1.0:
		dir = dir.normalized()
	return dir


## Konversi vektor 2D menjadi salah satu dari 8 arah mata angin (atau 4 jika opsi dipilih).
## Sudut dihitung relatif terhadap sumbu +X (kanan), lalu dipetakan ke bucket 45°.
func _direction_to_dir(dir: Vector2) -> Dir:
	if dir == Vector2.ZERO:
		return _facing

	# Gunakan atan2(y,x) => radian; konversi ke derajat [0..360)
	var angle_deg := rad_to_deg(atan2(dir.y, dir.x))
	if angle_deg < 0:
		angle_deg += 360.0

	if use_4_directions_only:
		# Bucket 90°: kanan (0±45), bawah (90±45), kiri (180±45), atas (270±45)
		match int(round(angle_deg / 90.0)) % 4:
			0: return Dir.RIGHT
			1: return Dir.BOTTOM
			2: return Dir.LEFT
			_: return Dir.TOP
	else:
		# Bucket 45°: delapan arah. Kita geser offset 22.5° supaya batas tengah tepat.
		var idx := int(floor(((angle_deg + 22.5) % 360.0) / 45.0))
		match idx:
			0: return Dir.RIGHT
			1: return Dir.BOTTOM_RIGHT
			2: return Dir.BOTTOM
			3: return Dir.BOTTOM_LEFT
			4: return Dir.LEFT
			5: return Dir.TOP_LEFT
			6: return Dir.TOP
			_: return Dir.TOP_RIGHT

# -----------------------------------------------------------------------------
# State Machine
# -----------------------------------------------------------------------------

## Pindah ke state baru dan sinkronkan animasi.
func _enter_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state

	match _state:
		State.IDLE:
			_play_state_anim(anim_prefix_idle)
		State.WALK:
			_play_state_anim(anim_prefix_walk)
		State.ATTACK:
			_play_state_anim(anim_prefix_attack)
			_start_attack()

# -----------------------------------------------------------------------------
# Attack
# -----------------------------------------------------------------------------

## Trigger serangan: biasanya dipanggil oleh input handler di bawah.
func try_attack() -> void:
	if _state == State.ATTACK:
		return
	_enter_state(State.ATTACK)


## Mulai timer pengaman agar state ATTACK berakhir walau animasi tak memberi sinyal.
func _start_attack() -> void:
	_attack_timer.start(attack_duration)


## Panggilan ketika animasi attack selesai (atau timer habis).
func _on_attack_finished() -> void:
	if _state != State.ATTACK:
		return
	_attack_timer.stop()
	_enter_state(State.IDLE if velocity == Vector2.ZERO else State.WALK)

# -----------------------------------------------------------------------------
# Animasi
# -----------------------------------------------------------------------------

## Bangun nama animasi lengkap = prefix + suffix arah, lalu mainkan jika ada.
func _play_state_anim(prefix: String) -> void:
	if _sprite == null:
		return
	var anim_name := prefix + DIR_SUFFIX[_facing]
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim_name):
		if _sprite.animation != anim_name:
			_sprite.play(anim_name)
	else:
		# Fallback: coba tanpa suffix (mis. hanya "idle"/"walk"/"attack")
		var fallback := prefix.trim_suffix("_")
		if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(fallback):
			_sprite.play(fallback)

# -----------------------------------------------------------------------------
# Setup internal
# -----------------------------------------------------------------------------

## Cari AnimatedSprite2D anak & pasang sinyal animation_finished untuk state ATTACK.
func _cache_sprite_and_signals() -> void:
	for child in get_children():
		if child is AnimatedSprite2D:
			_sprite = child as AnimatedSprite2D
			break
	if _sprite:
		# Godot 4: connect(StringName, Callable) — bukan (String, Object, method)
		_sprite.animation_finished.connect(_on_sprite_animation_finished)


## Buat timer sekali-pakai sebagai fallback jika animasi tak memicu finished.
func _setup_attack_timer() -> void:
	_attack_timer = Timer.new()
	_attack_timer.one_shot = true
	_attack_timer.autostart = false
	add_child(_attack_timer)
	_attack_timer.timeout.connect(_on_attack_timeout)

# -----------------------------------------------------------------------------
# Callbacks
# -----------------------------------------------------------------------------

## Bila sprite menyelesaikan animasi ber-prefix attack_, anggap serangan tuntas.
func _on_sprite_animation_finished() -> void:
	if _state != State.ATTACK or _sprite == null:
		return
	if _sprite.animation.begins_with(anim_prefix_attack):
		_on_attack_finished()


func _on_attack_timeout() -> void:
	_on_attack_finished()

# -----------------------------------------------------------------------------
# Input action (opsional — hapus bila sudah punya sistem input sendiri)
# -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		try_attack()
