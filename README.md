# 🗡️ Dungeon Hunter — Isometric ARPG Web Prototype

Web prototype **Action RPG 2.5D Isometric** (gaya top-down / Dungeon Hunter 4) yang dibangun murni dengan **HTML5 Canvas 2D + JavaScript vanilla** — tanpa engine, tanpa library, dan **tanpa aset gambar eksternal**. Semua visual (grid lantai diamond, karakter, efek tebasan, HUD) digambar secara prosedural, sehingga file `index.html` bisa langsung dibuka dan di-test di browser/tab preview mana pun.

## ▶️ Cara Menjalankan

| Metode | Langkah |
|---|---|
| **Langsung** | Buka `index.html` di browser (double-click / drag ke tab) |
| **Tab Preview** | Serve folder ini, mis. `python3 -m http.server 8000` lalu buka `http://localhost:8000` |
| **GitHub Pages** | Push repo → Settings → Pages → deploy branch utama → game berjalan di URL pages |

Tidak ada build step, tidak ada dependensi (`npm install` pun tidak diperlukan).

## 🎮 Kontrol

| Aksi | Keyboard | Mobile / Touch |
|---|---|---|
| Gerak (8 arah mata angin) | `W A S D` / Panah | Virtual joystick (drag area kiri layar) |
| Attack (tebasan arc) | `Spacebar` | Tombol ⚔ kanan bawah |
| Skill AoE (butuh MP) | `Shift` | Tombol ✦ kanan bawah |

HUD: bar **HP/MP** di kiri atas, indikator **State & Kill** di kanan atas, **health bar** di atas kepala tiap musuh, dan teks damage melayang saat mengenai target.

## ✨ Fitur

- **Proyeksi isometrik 2.5D** — grid lantai belah ketupat (`toIso`/`fromIso`), depth-sorting entity, bayangan elips ala dungeon.
- **Pergerakan analog smooth** ke 8 arah; facing dikunci ke kompas 45° terdekat (`snapAngle8`).
- **State machine sederhana** `IDLE → WALK → ATTACK`: gerakan terkunci selama animasi serangan, damage dieksekusi pada frame *impact*, hitbox berbentuk kerucut (arc 135°) sesuai arah hadap.
- **Skill AoE 360°** yang mengonsumsi MP (dengan regen otomatis).
- **3 musuh dengan AI dasar**: aggro & mengejar player dalam radius tertentu, menyerang dengan cooldown, mati dengan fade, lalu respawn otomatis (loop demo).
- **Kamera follow** halus (lerp framerate-independent) + screen-shake saat impact.
- **Mobile UI overlay** penuh: joystick dinamis muncul di titik sentuh, tombol aksi responsif pointer events.

## 🧱 Arsitektur Kode (satu file, modular per kelas)

```
CFG            — seluruh parameter gameplay di satu tempat (speed, damage, dsb.)
toIso/fromIso  — matematika proyeksi isometrik
InputHandler   — keyboard + pointer → vector gerak analog & flag aksi edge-triggered
Camera         — smooth-follow + shake
IsometricMap   — render diamond grid, pilar dekorasi, boundary clamp
Player         — state machine, movement iso, slash arc & AoE skill, i-frame
Enemy          — AI chaser, health bar, damage flash, death fade
MobileUI       — HP/MP bar, virtual joystick, tombol Attack/Skill (digambar di canvas)
Game           — bootstrap, update loop requestAnimationFrame, render pipeline
```

Debugging cepat dari console browser: instance game terekspos sebagai `window.game` (contoh: `game.player.state`, `game.enemies`).

## 📁 Struktur Repository

```
├── index.html    # Seluruh game (HTML + CSS + JS) — self-contained
├── README.md     # Dokumen ini
└── .gitignore    # Exclude file sistem/editor/node
```

## 🔭 Roadmap Ide

- Sprite sheet & animasi frame-per-direction (ganti renderer prosedural).
- Variasi tipe musuh, projectiles, dan loot drop.
- Kolisi tile berbasis rintang (rocks/walls) dan minimap.
- Combo attack, stamina, dan save-state via `localStorage`.

---
*Dibuat sebagai prototipe mekanik — semua rendering memakai Canvas 2D API standar (`fillRect`, `arc`, `ellipse`, path diamond), kompatibel dengan browser modern desktop & mobile.*
