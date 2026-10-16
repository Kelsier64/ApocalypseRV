extends Control
## The pre-initialization console. The original Item owns all boot state.
const DURATION := 6.0
const PROMPT := "Press ENTER to boot the system."
const BATCH_TIMES := [0.0, 0.35, 0.8, 1.5, 2.0, 2.8, 3.35, 4.15, 4.8, 5.5]
const BATCHES := [
	"[    0.000000] Linux version 6.12.0-field (civil-defense@build)\n[    0.000000] Command line: console=tty1 root=LABEL=FIELD ro quiet=0\n[    0.000000] BIOS-provided physical RAM map: 2048 MiB usable\n[    0.000000] Kernel command line accepted; booting local console",
	"[    0.074219] CPU0: portable console processor detected\n[    0.108403] Memory: 1986560K/2097152K available\n[    0.150006] clocksource: switched to monotonic clock\n[    0.203991] Console: colour dummy device 80x25",
	"[    0.321804] ACPI: internal battery controller online\n[    0.376108] input: Field keyboard as /devices/platform/keyboard/input0\n[    0.442591] tty0: local display console enabled\n[    0.516091] usbcore: registered new interface driver usb-storage",
	"[    0.682037] mmc0: new high speed MMC card at address 0001\n[    0.728193] mmcblk0: field-storage 8.00 GiB\n[    0.792141] mmcblk0: p1 p2\n[    0.873915] random: crng init done",
	"[    1.214803] EXT4-fs (mmcblk0p2): mounted filesystem read-only\n[    1.380241] VFS: Mounted root (ext4 filesystem)\n[    1.440107] devtmpfs: mounted\n[    1.526910] Freeing unused kernel memory: 2048K",
	"[    2.013391] systemd[1]: systemd running in system mode\n[    2.057103] systemd[1]: Detected architecture x86-64\n[    2.161009] systemd[1]: Hostname set to field-terminal\n[ OK ] Started Journal Service.\n[ OK ] Mounted Kernel API File Systems.",
	"[ OK ] Finished File System Check on /dev/mmcblk0p2.\n[    2.862407] EXT4-fs (mmcblk0p2): re-mounted read-write\n[ OK ] Finished Remount Root and Kernel File Systems.\n[ OK ] Mounted Local Field Data.\n[ OK ] Reached target Local File Systems.",
	"[ OK ] Started Device Event Manager.\n[ OK ] Found device Internal Console Battery.\n[ OK ] Started Internal Power Monitor.\n[ OK ] Started Local Input Service.\n[ OK ] Reached target Basic System.",
	"[ OK ] Started Civil Defense Training Service.\n[ OK ] Loaded local course database.\n[ OK ] Verified field manual index.\n[ OK ] Restored terminal identity and ownership record.\n[ OK ] Started Field Guide Session.",
	"[ OK ] Reached target Multi-User System.\n[ OK ] Console ready.\n\nfield@terminal:~$ field-guide --resume"
]
var _text: RichTextLabel
var _blink := 0.0
var _state: Dictionary = {}

static func fresh_state() -> Dictionary:
	return {"version": 2, "manual_unlocked": false, "completion": "locked", "internal_power": true,
		"internal_charge": 100.0, "initialized": false, "boot_started": false, "boot_elapsed": 0.0, "dock_locked": true}

static func advance(state: Dictionary, delta: float) -> bool:
	if not state.get("boot_started", false) or state.get("initialized", false): return false
	state.boot_elapsed = minf(DURATION, float(state.boot_elapsed) + maxf(0.0, delta))
	if state.boot_elapsed < DURATION: return false
	state.initialized = true
	state.dock_locked = false
	return true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.add_theme_font_override("normal_font", RVTerminalTheme.FONT)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_color_override("default_color", Color("eeeeee"))
	_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text.offset_left = 16
	_text.offset_top = 14
	_text.offset_right = -16
	_text.offset_bottom = -14
	add_child(_text)

func display(state: Dictionary) -> void:
	_state = state
	_render()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_blink += delta
	_render()

func _render() -> void:
	if _text == null: return
	var lines := "Civil Defense field console\nLocal terminal / tty1\n\n"
	if not _state.get("boot_started", false):
		lines += PROMPT + "\n"
	else:
		for index in BATCH_TIMES.size():
			if float(_state.get("boot_elapsed", 0.0)) >= BATCH_TIMES[index]: lines += BATCHES[index] + "\n"
	lines = lines.replace("[ OK ]", "[color=#70dc99][ OK ][/color]")
	_text.text = lines + ("█" if fmod(_blink, 1.0) < 0.5 else " ")
