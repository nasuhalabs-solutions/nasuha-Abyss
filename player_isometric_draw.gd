extends CharacterBody2D
class_name IsoPlayerDraw
# ============================================================================
# PLAYER ISOMETRIK 2.5D — SELF-CONTAINED (TANPA ASET GAMBAR / EXTERNAL)
# ----------------------------------------------------------------------------
# Cara pakai:
#   1. Buat node "CharacterBody2D" kosong di scene apa pun.
#   2. Tempel skrip ini ke node tersebut (drag-drop atau Add Script).
#   3. Tekan F6 (Run Current Scene) -> karakter langsung bisa dijalankan.
#
# Kenapa self-contained?
#   - CollisionShape2D dibuat otomatis di _ready() bila belum ada.
#   - Timer attack dibuat terprogram (SceneTree.create_timer), tidak perlu
#     menambah node Timer manual di editor.
#   - Visual digambar lewat _draw() (kaplet/lingkaran + garis arah hadap),
#     jadi tidak butuh AnimatedSprite2D maupun tekstur sama sekali.
# ============================================================================

# ---------------------------------------------------------------------------
# KONFIGURASI (export variables) — atur dari Inspector tanpa menyentuh kode
# ---------------------------------------------------------------------------
@export var speed: float = 200.0                     # Kecepatan gerak (px/detik)
@export_range(1, 8, 1) var direction_count: int = 8  # 8 = mata angin penuh, 4 = orthogonal saja
@export var capsule_radius: float = 14.0             # Radius badan karakter (px)
@export var attack_duration: float = 0.45            # Durasi state ATTACK (detik)

# ---------------------------------------------------------------------------
# STATE MACHINE SEDERHANA
# ---------------------------------------------------------------------------
enum State { IDLE, WALK, ATTACK }

## Warna visual per state — dipakai di _draw() agar respon terlihat jelas:
## Hijau = Idle, Biru = Walk, Merah = Attack.
const STATE_COLORS: Dictionary = {
	State.IDLE:   Color(0.30, 0.75, 0.40),  # Hijau
	State.WALK:   Color(0.25, 0.55, 0.95),  # Biru
	State.ATTACK: Color(0.95, 0.30, 0.25),  # Merah
}

# ---------------------------------------------------------------------------
# VARIABEL INTERNAL
# ---------------------------------------------------------------------------
var _state: State = State.IDLE          # State aktif saat ini
var _facing: Vector2 = Vector2.DOWN     # Arah hadap karakter (sudah di-snapped 8 arah)
var _attack_time_left: float = 0.0      # Sisa waktu lock-out serangan (detik)
var _attack_token: int = 0              # Penanda generasi timer (anti race-condition)


## Inisialisasi: jamin node punya CollisionShape2D walau ditempel ke
## CharacterBody2D kosong (self-contained, tanpa setup editor).
func _ready() -> void:
	_ensure_collision_shape()


# ===========================================================================
# PERSEDIAAN OTOMATIS (Self-Containment)
# ===========================================================================

## Membuat CollisionShape2D secara terprogram jika node child-nya belum ada,
## sehingga skrip bisa ditempel ke CharacterBody2D KOSONG tanpa error.
func _ensure_collision_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return  # Sudah ada -> jangan duplikat
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = capsule_radius
	shape.shape = circle
	add_child.call_deferred(shape)  # Deferred: aman walau dipanggil saat fisika berjalan


# ===========================================================================
# INPUT & LOGIKA PERGERAKAN (8 ARAH MATA ANGIN)
# ===========================================================================

## Input movement berbasis vector/analog (mendukung gamepad/stick analog).
## PENTING: action "move_left/right/up/down" TIDAK ada di default project
## settings Godot 4, jadi skrip ini memakai action bawaan "ui_*" yang sudah
## ter-define secara default (WASD + arrow keys + gamepad) => zero setup.
func _get_input_direction() -> Vector2:
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")


## Membulatkan vector mentah menjadi salah satu dari 8 arah mata angin
## (Atas, Bawah, Kiri, Kanan + 4 diagonal). Bila direction_count = 4,
## komponen diagonal akan dibuang (hanya orthogonal).
func _snap_to_compass(raw: Vector2) -> Vector2:
	if raw == Vector2.ZERO:
		return _facing  # Tidak ada input -> pertahankan arah hadap terakhir

	# Tabel 8 arah mata angin (indeks = sektor 45 derajat).
	var compass: Array[Vector2] = [
		Vector2.RIGHT,          # 0   : Timur / Kanan
		Vector2.DOWN_RIGHT,     # 1   : Tenggara / Bawah-Kanan
		Vector2.DOWN,           # 2   : Selatan / Bawah
		Vector2.DOWN_LEFT,      # 3   : Barat Daya / Bawah-Kiri
		Vector2.LEFT,           # 4   : Barat / Kiri
		Vector2.UP_LEFT,        # 5   : Barat Laut / Atas-Kiri
		Vector2.UP,             # 6   : Utara / Atas
		Vector2.UP_RIGHT,       # 7   : Timur Laut / Atas-Kanan
	]

	# Sudut raw (rad) -> indeks sektor 45 derajat.
	# Offset +TAU/16 (= 22.5 deg) agar pembulatan ke sektor TERDEKAT.
	var angle := raw.angle()
	var sector := int(floorf((angle + TAU / 16.0) / (TAU / 8.0))) % 8
	var snapped_dir: Vector2 = compass[sector]

	if direction_count == 4:
		snapped_dir = _to_orthogonal(snapped_dir)
	return snapped_dir


## Mengonversi arah diagonal menjadi orthogonal dominan (untuk mode 4 arah).
func _to_orthogonal(dir: Vector2) -> Vector2:
	if absf(dir.x) > absf(dir.y):
		return Vector2(signf(dir.x), 0.0)
	elif absf(dir.y) > absf(dir.x):
		return Vector2(0.0, signf(dir.y))
	# x == y (tepat 45 derajat): pilih sumbu Y dulu (konvensi isometrik umum)
	return Vector2(0.0, signf(dir.y))


## Loop fisika utama: tangani input -> tentukan facing & velocity ->
## jalankan state machine -> move_and_slide(). Saat ATTACK, movement dikunci.
func _physics_process(delta: float) -> void:
	# --- Penanganan state ATTACK (movement dikunci) -------------------------
	if _state == State.ATTACK:
		_attack_time_left -= delta
		if _attack_time_left <= 0.0:
			_enter_state(State.IDLE)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# --- Pergerakan normal ---------------------------------------------------
	var input_dir := _get_input_direction()

	if input_dir != Vector2.ZERO:
		_facing = _snap_to_compass(input_dir)
		velocity = _facing * speed      # Analog input tetap dinormalisasi (max = speed)
		_enter_state(State.WALK)
	else:
		velocity = Vector2.ZERO
		_enter_state(State.IDLE)

	# --- Trigger serangan: Spacebar / Enter (ui_accept) atau tombol "attack" --
	# is_action_just_pressed aman dipanggil walau action belum didefinisikan.
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		_start_attack()

	move_and_slide()


# ===========================================================================
# STATE MACHINE — transisi & efek samping terpusat di satu tempat
# ===========================================================================

## Satu-satunya jalur untuk berpindah state. Memanggil queue_redraw()
## agar visual (_draw) langsung ter-update saat state berubah.
func _enter_state(new_state: State) -> void:
	if new_state == _state:
		return
	_state = new_state
	queue_redraw()


## Memulai serangan: kunci movement + jalankan countdown attack.
## Timer dibuat terprogram via SceneTree.create_timer() (Godot 4, one-shot)
## dengan "token" agar timer lama tidak bisa membatalkan serangan baru.
func _start_attack() -> void:
	_enter_state(State.ATTACK)
	velocity = Vector2.ZERO
	_attack_time_left = attack_duration
	_attack_token += 1
	var token := _attack_token
	get_tree().create_timer(attack_duration).timeout.connect(
		_on_attack_timer_timeout.bind(token)
	)


## Callback penyelesaian serangan. Token dicocokkan supaya hanya timer
## dari serangan TERAKHIR yang boleh mengakhiri state ATTACK.
func _on_attack_timer_timeout(token: int) -> void:
	if token != _attack_token:
		return  # Timer basi dari serangan sebelumnya -> abaikan
	if _state == State.ATTACK:
		_enter_state(State.IDLE)


# ===========================================================================
# VISUAL — DIGAMBAR TANPA TEKSTUR (self-contained)
# ===========================================================================

## Menggambar karakter: kapsul dua-tone + garis arah hadap + indikator state.
## Dipanggil ulang oleh engine setiap kali queue_redraw() dieksekusi.
func _draw() -> void:
	var body_color: Color = STATE_COLORS[_state]

	# 1) Bayangan sederhana (efek "isometrik" murah, sedikit pipih ke bawah)
	draw_circle(Vector2(0, capsule_radius * 0.6), capsule_radius * 1.1,
		Color(0, 0, 0, 0.20))

	# 2) Badan kapsul: dua lingkaran + penghubung, orientasi mengikuti facing
	#    (sumbu panjang kapsul sejajar arah hadap -> terasa seperti "menghadap").
	var axis := _facing.rotated(PI / 2.0) * capsule_radius * 0.55
	draw_circle(axis, capsule_radius, body_color.darkened(0.15))
	draw_circle(-axis, capsule_radius, body_color)
	draw_line(axis, -axis, body_color, capsule_radius * 2.0)

	# 3) Outline kontras tipis agar bentuk terbaca di latar apa pun
	draw_circle(axis, capsule_radius, Color(0, 0, 0, 0.55), false, 2.0)
	draw_circle(-axis, capsule_radius, Color(0, 0, 0, 0.55), false, 2.0)

	# 4) Garis penunjuk arah hadap (hidung karakter)
	var nose_tip := _facing * (capsule_radius * 2.0)
	draw_line(_facing * capsule_radius * 0.4, nose_tip,
		Color.WHITE, 3.0)
	draw_circle(nose_tip, 3.0, Color.WHITE)

	# 5) Efek tebasan saat ATTACK: arc kuning-oranye di depan karakter
	if _state == State.ATTACK:
		var swing_center_angle := _facing.angle()
		var points := PackedVector2Array()
		for i in range(9):
			var a := swing_center_angle - PI / 3.0 + (TAU / 3.0) * (float(i) / 8.0)
			points.append(Vector2.from_angle(a) * capsule_radius * 2.2)
		draw_polyline(points, Color(1.0, 0.8, 0.2, 0.9), 4.0)


# ===========================================================================
# DEBUG / INFO
# ===========================================================================

## Label teks opsional (buat CanvasLayer + Label manual bila ingin HUD).
## Contoh pemakaian dari luar: print(player.get_debug_info())
func get_debug_info() -> String:
	var state_names := ["IDLE", "WALK", "ATTACK"]
	return "State: %s | Facing: %s | Speed: %.0f" % [
		state_names[_state], str(_facing), speed
	]
