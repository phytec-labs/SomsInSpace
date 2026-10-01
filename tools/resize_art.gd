# resize_art.gd
# Regenerates the downscaled game textures in sprites/ from the full-size
# masters in art_archive/masters/ (which Godot ignores via art_archive/.gdignore).
#
#   godot --headless --path . -s res://tools/resize_art.gd
#   godot --headless --path . --import      # then re-import the outputs
#
# Each ART entry: master path, output path, and either "height" or "width"
# (the other side follows the aspect ratio). Optional "crop" (Rect2i, master
# pixels) is applied first; optional "erase" (Array of Rect2i, master pixels)
# clears those areas to transparent before cropping (e.g. neighbouring sheet
# parts that poke into the crop). Lanczos filtering, alpha preserved, output is
# RGBA8 PNG. Existing outputs are overwritten; their .import files (uid,
# mipmap settings) are kept, so scenes stay wired.
#
# Conventions (docs/ART_SWAP_TRACKER.md): enemies and pickups 512 px tall,
# UFO / blimp 1024 px wide; ships stay at their 1024x1536 canvas (not listed).
extends SceneTree

const MASTERS := "res://art_archive/masters/"
const OUT := "res://sprites/"

var ART: Array[Dictionary] = [
	{"src": "jet_1.png", "dst": "jet_1.png", "height": 512},
	{"src": "jet_2.png", "dst": "jet_2.png", "height": 512},
	{"src": "jet_3.png", "dst": "jet_3.png", "height": 512},
	{"src": "drone_1.png", "dst": "drone_1.png", "height": 512},
	{"src": "mine_1.png", "dst": "mine_1.png", "height": 512},
	{"src": "ufo_1.png", "dst": "ufo_1.png", "width": 1024},
	# The master is a sheet: the zeppelin (top, nose to the right) plus six
	# weapon modules underneath. Only the zeppelin is cut out; the tips of the
	# two right-hand weapons reach into its rows and are erased first.
	{"src": "zeppelin_weapon_combined.png", "dst": "zeppelin_1.png", "width": 1024,
		"crop": Rect2i(0, 44, 1536, 590),
		"erase": [Rect2i(1085, 600, 451, 424)]},
	{"src": "bomb_collectible_1.png", "dst": "bomb_collectible_1.png", "height": 512},
	{"src": "shield_dome_1.png", "dst": "shield_dome_1.png", "height": 512},
]

func _init() -> void:
	var failures := 0
	for entry in ART:
		if not _process_entry(entry):
			failures += 1
	print("resize_art: %d written, %d failed" % [ART.size() - failures, failures])
	quit(1 if failures > 0 else 0)

func _process_entry(entry: Dictionary) -> bool:
	var src_path: String = ProjectSettings.globalize_path(MASTERS + entry["src"])
	var dst_path: String = ProjectSettings.globalize_path(OUT + entry["dst"])
	var img := Image.load_from_file(src_path)
	if img == null or img.is_empty():
		push_error("resize_art: cannot load %s" % src_path)
		return false
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var src_size := img.get_size()

	for r in entry.get("erase", []):
		img.fill_rect(r, Color(0, 0, 0, 0))
	if entry.has("crop"):
		img = img.get_region(entry["crop"])

	var w := img.get_width()
	var h := img.get_height()
	var tw: int
	var th: int
	if entry.has("height"):
		th = int(entry["height"])
		tw = maxi(1, roundi(float(w) * th / h))
	elif entry.has("width"):
		tw = int(entry["width"])
		th = maxi(1, roundi(float(h) * tw / w))
	else:
		push_error("resize_art: %s needs a height or width" % entry["src"])
		return false

	# Spread edge colours into the fully transparent pixels first, so the
	# filter does not pull the (arbitrary) colour of the transparent
	# background into the anti-aliased edges
	img.fix_alpha_edges()
	if tw != w or th != h:
		img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(dst_path)
	if err != OK:
		push_error("resize_art: cannot write %s (error %d)" % [dst_path, err])
		return false
	print("resize_art: %s %dx%d -> %s %dx%d" % [entry["src"], src_size.x, src_size.y,
			entry["dst"], tw, th])
	return true
