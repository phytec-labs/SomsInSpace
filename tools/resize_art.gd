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
# parts that poke into the crop). Optional "pad" (fraction of the resized art's
# longer side) adds that much transparent margin on every side after resizing,
# with the art centered (e.g. room for a shader glow around it). Lanczos
# filtering, alpha preserved, output is RGBA8 PNG. Existing outputs are overwritten; their .import files (uid,
# mipmap settings) are kept, so scenes stay wired.
#
# A "sheet" entry repacks an animation strip whose frames are not on a uniform
# grid into a uniform horizontal sheet (see _process_sheet()): per frame a
# "span" (Vector2i(first, last) master column; everything outside it is cleared,
# which separates frames whose glows touch) and a "center" (Vector2i, master
# pixels: the point that must stay fixed across frames, e.g. a sphere's
# center). A square of "extent" master pixels around each center becomes one
# "cell" x "cell" output cell (Lanczos), cells packed left to right. The run
# fails if any frame's art comes closer than "pad" output pixels to its cell
# edge (enlarge "extent" then), so neighbouring frames cannot bleed into each
# other through filtering or mipmaps. Optional "alpha_floor" (0-255): master
# pixels with a lower alpha are cleared first (invisible haze / noise far
# outside the art that would otherwise count as art for the fit check).
#
# Conventions (docs/ART_SWAP_TRACKER.md): enemies and pickups 512 px tall,
# UFO / blimp / station 1024 px wide; ships stay at their 1024x1536 canvas (not
# listed).
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
	# Full sphere; 12% margin so the shield_bubble.gdshader rim glow has room
	{"src": "shield_dome_1.png", "dst": "shield_dome_1.png", "height": 512, "pad": 0.12},
	{"src": "space_station_1.png", "dst": "space_station_1.png", "width": 1024},
	# Shield pickup icon: 5-frame glow pulse (2172x724 master, frames not on a
	# grid; frames 1-3 have touching glows, split at the emptiest column
	# between them; alpha 1-4 haze, up to ~350 px out, is dropped). Centers are the hex sphere's rim-ring circle fit (ring
	# radii 180.7 / 176.7 / 180.9 / 180.3 / 178.9 master px: within 2.3%, so
	# no per-frame rescale). The largest glow reaches 239 px from its center
	# (frame 2, top); a 512 px extent (0.5x into 256 px cells) leaves >= 8 px of
	# padding per cell side. Output 1280x256, used by sprites/shield_icon.tres.
	{"src": "shield_icon_sprite_sheet.png", "dst": "shield_icon_sheet.png",
		"sheet": {"cell": 256, "extent": 512, "pad": 6, "alpha_floor": 5, "frames": [
			{"span": Vector2i(0, 416), "center": Vector2i(220, 370)},
			{"span": Vector2i(417, 866), "center": Vector2i(650, 369)},
			{"span": Vector2i(867, 1299), "center": Vector2i(1085, 370)},
			{"span": Vector2i(1300, 1741), "center": Vector2i(1519, 368)},
			{"span": Vector2i(1742, 2171), "center": Vector2i(1955, 369)},
		]}},
	# Health pickup icon: 5-frame "breathing" pulse (2172x724 master, frames
	# not on a grid, separated by empty columns; spans split mid-gap). The
	# canister grows 1.27x into frame 2 and back on purpose, so frames are not
	# rescaled; centers are the red cross centroids, so it pulses in place
	# (the base ring, fixed in the master, moves instead). The largest frame
	# reaches 268 px from its center (frame 2, top sparkle); a 576 px extent
	# (0.444x into 256 px cells) keeps >= 6 px padding per cell side. Output
	# 1280x256, used by sprites/health_pickup.tres.
	{"src": "health_pickup_sprite_sheet.png", "dst": "health_pickup_sheet.png",
		"sheet": {"cell": 256, "extent": 576, "pad": 6, "alpha_floor": 5, "frames": [
			{"span": Vector2i(0, 399), "center": Vector2i(200, 404)},
			{"span": Vector2i(400, 840), "center": Vector2i(625, 395)},
			{"span": Vector2i(841, 1331), "center": Vector2i(1086, 380)},
			{"span": Vector2i(1332, 1771), "center": Vector2i(1549, 394)},
			{"span": Vector2i(1772, 2171), "center": Vector2i(1968, 404)},
		]}},
	# Bomb pickup icon: 6-frame "core heats up, steam vents, settles" loop
	# (2172x724 master, frames separated by empty columns; spans split
	# mid-gap). Centers are the round body's center (middle of its widest row,
	# y = bottom - half width). Frame 3 is drawn 1.12x larger on purpose (body
	# 312 vs 278-294 master px wide); kept, not normalized. The farthest art
	# is frame 3's fuse flame, 260 px above its center; a 560 px extent
	# (0.457x into 256 px cells) leaves >= 6 px padding per cell side. Alpha
	# 1-4 haze is dropped. Output 1536x256, used by sprites/bomb_pickup.tres.
	{"src": "bomb_collectible_2.png", "dst": "bomb_pickup_sheet.png",
		"sheet": {"cell": 256, "extent": 560, "pad": 6, "alpha_floor": 5, "frames": [
			{"span": Vector2i(0, 310), "center": Vector2i(147, 397)},
			{"span": Vector2i(311, 652), "center": Vector2i(476, 397)},
			{"span": Vector2i(653, 1020), "center": Vector2i(830, 397)},
			{"span": Vector2i(1021, 1478), "center": Vector2i(1260, 391)},
			{"span": Vector2i(1479, 1854), "center": Vector2i(1666, 397)},
			{"span": Vector2i(1855, 2171), "center": Vector2i(2010, 397)},
		]}},
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
	if entry.has("sheet"):
		return _process_sheet(entry, img, dst_path)

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
	if entry.has("pad"):
		var margin := roundi(float(entry["pad"]) * maxi(tw, th))
		var padded := Image.create_empty(tw + 2 * margin, th + 2 * margin, false, Image.FORMAT_RGBA8)
		padded.fill(Color(0, 0, 0, 0))
		padded.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i(margin, margin))
		img = padded
		tw = img.get_width()
		th = img.get_height()
	var err := img.save_png(dst_path)
	if err != OK:
		push_error("resize_art: cannot write %s (error %d)" % [dst_path, err])
		return false
	print("resize_art: %s %dx%d -> %s %dx%d" % [entry["src"], src_size.x, src_size.y,
			entry["dst"], tw, th])
	return true

# Repack a non-uniform animation strip into a uniform horizontal sheet (see the
# header comment for the "sheet" entry keys)
func _process_sheet(entry: Dictionary, img: Image, dst_path: String) -> bool:
	var sheet: Dictionary = entry["sheet"]
	var cell: int = sheet["cell"]
	var extent: int = sheet["extent"]
	var pad: int = sheet.get("pad", 0)
	var frames: Array = sheet["frames"]
	var floor_a: int = sheet.get("alpha_floor", 0)
	if floor_a > 0:
		var data := img.get_data()
		for p in range(3, data.size(), 4):
			if data[p] < floor_a:
				data[p - 3] = 0
				data[p - 2] = 0
				data[p - 1] = 0
				data[p] = 0
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var out := Image.create_empty(cell * frames.size(), cell, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var min_margin := cell
	for i in frames.size():
		var span: Vector2i = frames[i]["span"]
		var center: Vector2i = frames[i]["center"]
		# Only this frame's columns, placed so its center lands mid-canvas
		var canvas := Image.create_empty(extent, extent, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		var src_rect := Rect2i(span.x, 0, span.y - span.x + 1, img.get_height())
		var origin := center - Vector2i(extent / 2, extent / 2)
		# Art that would land outside the canvas would be clipped: refuse
		var used := img.get_region(src_rect).get_used_rect()
		used.position += src_rect.position
		if not Rect2i(origin, Vector2i(extent, extent)).encloses(used):
			push_error("resize_art: %s frame %d art %s does not fit the %d px extent around %s"
					% [entry["src"], i, used, extent, center])
			return false
		canvas.blit_rect(img, src_rect, src_rect.position - origin)
		canvas.fix_alpha_edges()
		if extent != cell:
			canvas.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		var art := canvas.get_used_rect()
		var margin := mini(mini(art.position.x, art.position.y),
				mini(cell - art.end.x, cell - art.end.y))
		min_margin = mini(min_margin, margin)
		out.blit_rect(canvas, Rect2i(0, 0, cell, cell), Vector2i(i * cell, 0))
	if min_margin < pad:
		push_error("resize_art: %s cell padding %d px < %d px; enlarge the extent"
				% [entry["src"], min_margin, pad])
		return false
	var err := out.save_png(dst_path)
	if err != OK:
		push_error("resize_art: cannot write %s (error %d)" % [dst_path, err])
		return false
	print("resize_art: %s %dx%d -> %s %dx%d (%d frames, %d px cells, min padding %d px)" % [
			entry["src"], img.get_width(), img.get_height(), entry["dst"],
			out.get_width(), out.get_height(), frames.size(), cell, min_margin])
	return true
