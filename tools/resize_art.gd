# resize_art.gd
# Regenerates the downscaled game textures in sprites/ from the full-size
# masters in art_archive/masters/ (which Godot ignores via art_archive/.gdignore).
#
#   godot --headless --path . -s res://tools/resize_art.gd
#   godot --headless --path . --import      # then re-import the outputs
#
# Each ART entry: master path, output path, and either "height" or "width"
# (the other side follows the aspect ratio, of the rotated art when "rotate"
# is set). Optional "crop" (Rect2i, master pixels) is applied first; optional "erase" (Array of Rect2i, master pixels)
# clears those areas to transparent before cropping (e.g. neighbouring sheet
# parts that poke into the crop). Optional "rotate" (degrees counter-clockwise:
# 90, 180 or 270 = -90) turns the cropped art before resizing, e.g. 90 turns a
# missile drawn nose-right into nose-up. Optional "pad" (fraction of the resized art's
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
# Optional "columns" (int): output cells per row, rows filled top to bottom
# (default: all frames in one row).
#
# Instead of "frames", a sheet may give "grid" (Vector2i(columns, rows)) for
# a master with separate pieces laid out roughly on a grid (read left to right,
# top row first) whose bounding boxes overlap their neighbours' rows and
# columns. Each piece is isolated as connected alpha islands (8-connected,
# after "alpha_floor"): a frame is every island of at least "min_island"
# master pixels (default 200; smaller specks are dropped) whose alpha-weighted
# centroid lies in that frame's cell of a uniform grid over the master, so no
# sliver of a neighbour comes along. The frame's center is the islands'
# bounding-box center, or their alpha centroid with "center": "centroid"
# (steadier for a tumbling animation whose silhouette changes), or with
# "center": "top_band" the alpha centroid of only the top "band" master rows
# of the frame (from its topmost art pixel down): for art whose upper part
# stays put while the lower part moves (the mothership's dome over its walking
# legs), so the still part is what gets registered. Optional "refine" (int,
# master pixels) then moves each frame's center by the whole-pixel shift, up
# to that far, that best lays its top band over frame 0's (least alpha and
# luma difference; needs "band"): exact when the still part is redrawn a
# little differently per frame, where a centroid is only close. Optional
# "center_offset" (Vector2i, master pixels) is added to every frame's center:
# it moves the art inside its cells (e.g. to balance a top-band anchor)
# without changing the registration. The run fails if a grid cell holds no island. Centers are
# printed.
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
	# Scout saucer: second-colour render of ufo_1 (same canvas and silhouette:
	# visible bounds within 1% wide / 2.4% tall), so the scout keeps its scale
	{"src": "ufo_2.png", "dst": "ufo_2.png", "width": 1024},
	# Sidewinder missile, drawn nose-right on a 2172x724 canvas: cropped to the
	# visible art (alpha >= 5: x 117..2100, y 18..687) plus a 16 px margin,
	# turned nose-up (the missile scenes face -y along their velocity), 512 px
	# along its length. Red/white livery: the zeppelin's missile (untinted).
	{"src": "side_winder_missile_1.png", "dst": "side_winder_missile_1.png", "height": 512,
		"crop": Rect2i(101, 2, 2016, 702), "rotate": 90},
	# Same sidewinder in the blue/white livery (same 2172x724 canvas, nose
	# right): visible art (alpha >= 5) x 60..2122, y 12..691, cropped with a
	# 16 px margin along its length and 12 px across (the canvas top), turned
	# nose-up, 512 px long. Its visible length in the game copy (504 px) matches
	# side_winder_missile_1 within 0.1%, so the scenes keep their scale. Used by
	# the player missile and the missile pickup icon.
	{"src": "side_winder_missile_2.png", "dst": "side_winder_missile_2.png", "height": 512,
		"crop": Rect2i(44, 0, 2095, 704), "rotate": 90},
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
	# Splitting asteroid, large: 8-frame tumble (1774x887 master, 4x2 rocks
	# not on an exact grid, read left to right, top row first). Centers are the
	# alpha centroids: frame to frame the silhouette overlaps better than with
	# bounding-box centers (mean IoU of neighbouring frames 0.889 vs 0.876),
	# so the rock does not jitter. The farthest art is 233 px from its center
	# (frame 0, left); a 544 px extent (0.471x into 256 px cells) leaves
	# >= 18 px padding per cell side, so neither mipmaps (down to the ~0.40x
	# the game draws it at) nor the rim light can reach the next cell. Alpha
	# 1-4 haze and specks under 200 px are dropped. Output 2048x256, used by
	# sprites/asteroid.tres ("large_1").
	{"src": "meteor_animated_large_1.png", "dst": "asteroid_large_sheet.png",
		"sheet": {"cell": 256, "extent": 544, "pad": 12, "alpha_floor": 5,
			"grid": Vector2i(4, 2), "center": "centroid"}},
	# Splitting asteroid, large rock 2: a second 8-frame tumble, same layout
	# and treatment as rock 1 (the master keeps the user's name). The rocks sit
	# tight (neighbours nearly touch), so the islands matter here. Same extent
	# as rock 1, so both rocks keep their relative size under one sprite scale.
	# Nothing reaches the master's edge (art x 12..1767). >= 21 px padding per
	# cell. Output 2048x256, used by sprites/asteroid.tres ("large_2").
	{"src": "asteroid_large_sheet_2.png", "dst": "asteroid_large_sheet_2.png",
		"sheet": {"cell": 256, "extent": 544, "pad": 12, "alpha_floor": 5,
			"grid": Vector2i(4, 2), "center": "centroid"}},
	# Splitting asteroid, medium: 8 different chunks (not an animation;
	# 1774x887 master, 4x2, neighbours' bounding boxes overlap, so each chunk
	# is cut out as its own alpha island). Centers are the bounding-box
	# centers (the code spins them). The widest chunk (frame 4, 462 px) gets
	# >= 17 px padding per cell side at the same 544 px extent as the large
	# rocks. Output 2048x256, used by sprites/asteroid.tres ("medium").
	{"src": "meteor_medium_chunks.png", "dst": "asteroid_chunks_sheet.png",
		"sheet": {"cell": 256, "extent": 544, "pad": 12, "alpha_floor": 5,
			"grid": Vector2i(4, 2)}},
	# Splitting asteroid, small: 18 different shards (1774x887 master, 6x3,
	# packed tight, cut out as alpha islands like the chunks). Shown at about
	# 30 px, so 128 px cells in a 6x3 output grid (768x384) instead of one
	# 4608 px row. A 416 px extent (0.308x) leaves >= 10 px padding per cell
	# side (the game draws them at ~0.33x of this copy). Output 768x384, used
	# by sprites/asteroid.tres ("small").
	{"src": "meteor_small_shards_various_1.png", "dst": "asteroid_shards_sheet.png",
		"sheet": {"cell": 128, "extent": 416, "pad": 8, "alpha_floor": 5,
			"grid": Vector2i(6, 3), "columns": 6}},
	# Boss mothership: 8-frame leg cycle (1774x887 master, 4x2 not on an
	# exact grid, neighbours 10-15 px apart, so each frame is cut out as its
	# own alpha islands). The dome and spikes stay put while the six legs
	# walk, so frames are registered on the dome: the alpha centroid of the
	# top 200 master rows (spike tip down to just above the dome rim), then
	# refined by up to 3 px to the best dome match with frame 0 (the dome is
	# redrawn a little differently per frame). Measured on the output, the
	# dome's (upper 45% of the cell) best-fit shift against frame 1 is at most
	# 0.52 px. The centroid sits ~141 px below the spike tip, so
	# center_offset moves it 75 px up in the cell: the art then reaches 216 px
	# above and at most 213 px below the cell center and 218 px to the sides.
	# One 480 px extent for all frames (0.8x, no per-frame rescale) leaves
	# >= 16 px padding per cell side. Alpha 1-4 haze is dropped. Output
	# 1536x768 (384 px cells, 4 per row), used by sprites/mothership.tres.
	{"src": "mothership_1.png", "dst": "mothership_sheet.png",
		"sheet": {"cell": 384, "extent": 480, "pad": 12, "alpha_floor": 5,
			"grid": Vector2i(4, 2), "columns": 4,
			"center": "top_band", "band": 200, "refine": 3,
			"center_offset": Vector2i(0, 75)}},
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
	match posmod(int(entry.get("rotate", 0)), 360):
		0:
			pass
		90:
			img.rotate_90(COUNTERCLOCKWISE)
		180:
			img.rotate_180()
		270:
			img.rotate_90(CLOCKWISE)
		_:
			push_error("resize_art: %s rotate must be a multiple of 90" % entry["src"])
			return false

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

# Repack a non-uniform animation strip (or a loose grid of pieces) into a
# uniform sheet (see the header comment for the "sheet" entry keys)
func _process_sheet(entry: Dictionary, img: Image, dst_path: String) -> bool:
	var sheet: Dictionary = entry["sheet"]
	var cell: int = sheet["cell"]
	var extent: int = sheet["extent"]
	var pad: int = sheet.get("pad", 0)
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
	# Per frame: the master image holding only that frame's art, the master
	# rect to copy and the center
	var frames: Array = []
	if sheet.has("grid"):
		frames = _island_frames(entry, img)
		if frames.is_empty():
			return false
	else:
		for f in sheet["frames"]:
			var span: Vector2i = f["span"]
			frames.append({"image": img, "center": f["center"],
					"rect": Rect2i(span.x, 0, span.y - span.x + 1, img.get_height())})
	var columns: int = sheet.get("columns", frames.size())
	var rows: int = ceili(float(frames.size()) / columns)
	var out := Image.create_empty(cell * columns, cell * rows, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var min_margin := cell
	for i in frames.size():
		var src: Image = frames[i]["image"]
		var src_rect: Rect2i = frames[i]["rect"]
		var center: Vector2i = frames[i]["center"]
		# Only this frame's art, placed so its center lands mid-canvas
		var canvas := Image.create_empty(extent, extent, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		var origin := center - Vector2i(extent / 2, extent / 2)
		# Art that would land outside the canvas would be clipped: refuse
		var used := src.get_region(src_rect).get_used_rect()
		used.position += src_rect.position
		if not Rect2i(origin, Vector2i(extent, extent)).encloses(used):
			push_error("resize_art: %s frame %d art %s does not fit the %d px extent around %s"
					% [entry["src"], i, used, extent, center])
			return false
		canvas.blit_rect(src, src_rect, src_rect.position - origin)
		canvas.fix_alpha_edges()
		if extent != cell:
			canvas.resize(cell, cell, Image.INTERPOLATE_LANCZOS)
		var art := canvas.get_used_rect()
		var margin := mini(mini(art.position.x, art.position.y),
				mini(cell - art.end.x, cell - art.end.y))
		min_margin = mini(min_margin, margin)
		out.blit_rect(canvas, Rect2i(0, 0, cell, cell),
				Vector2i((i % columns) * cell, (i / columns) * cell))
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

# "grid" sheets: label the master's connected alpha islands (8-connected) and
# give every grid cell the islands whose centroid lies in it. Returns one
# {"image", "rect", "center"} per cell (reading order), [] on failure.
func _island_frames(entry: Dictionary, img: Image) -> Array:
	var sheet: Dictionary = entry["sheet"]
	var grid: Vector2i = sheet["grid"]
	var min_island: int = sheet.get("min_island", 200)
	var center_mode: String = sheet.get("center", "bbox")
	var band: int = sheet.get("band", 0)
	var center_offset: Vector2i = sheet.get("center_offset", Vector2i.ZERO)
	var refine: int = sheet.get("refine", 0)
	if (center_mode == "top_band" or refine > 0) and band <= 0:
		push_error("resize_art: %s \"top_band\" / \"refine\" need a \"band\" > 0" % entry["src"])
		return []
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var labels := PackedInt32Array()
	labels.resize(w * h)
	labels.fill(-1)
	# Per island: pixel count, bounding box, alpha-weighted coordinate sums
	var islands: Array[Dictionary] = []
	var stack := PackedInt32Array()
	for start in w * h:
		if labels[start] != -1 or data[start * 4 + 3] == 0:
			continue
		var id := islands.size()
		var isl := {"count": 0, "x0": w, "y0": h, "x1": -1, "y1": -1, "sx": 0.0, "sy": 0.0, "sa": 0.0}
		labels[start] = id
		stack.append(start)
		while not stack.is_empty():
			var p: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var px := p % w
			var py := p / w
			var a := float(data[p * 4 + 3])
			isl["count"] += 1
			isl["x0"] = mini(isl["x0"], px)
			isl["x1"] = maxi(isl["x1"], px)
			isl["y0"] = mini(isl["y0"], py)
			isl["y1"] = maxi(isl["y1"], py)
			isl["sx"] += px * a
			isl["sy"] += py * a
			isl["sa"] += a
			for qy in range(maxi(py - 1, 0), mini(py + 2, h)):
				for qx in range(maxi(px - 1, 0), mini(px + 2, w)):
					var q := qy * w + qx
					if labels[q] == -1 and data[q * 4 + 3] != 0:
						labels[q] = id
						stack.append(q)
		islands.append(isl)
	var cell_size := Vector2(float(w) / grid.x, float(h) / grid.y)
	var frames: Array = []
	for i in grid.x * grid.y:
		var cell_rect := Rect2(Vector2(i % grid.x, i / grid.x) * cell_size, cell_size)
		var keep := {}
		var bbox := Rect2i()
		var sx := 0.0
		var sy := 0.0
		var sa := 0.0
		for id in islands.size():
			var isl: Dictionary = islands[id]
			if isl["count"] < min_island:
				continue
			var centroid: Vector2 = Vector2(isl["sx"], isl["sy"]) / float(isl["sa"])
			if not cell_rect.has_point(centroid):
				continue
			keep[id] = true
			var r := Rect2i(isl["x0"], isl["y0"], isl["x1"] - isl["x0"] + 1, isl["y1"] - isl["y0"] + 1)
			bbox = r if keep.size() == 1 else bbox.merge(r)
			sx += isl["sx"]
			sy += isl["sy"]
			sa += isl["sa"]
		if keep.is_empty():
			push_error("resize_art: %s grid cell %d holds no island" % [entry["src"], i])
			return []
		# The frame's own pixels only (neighbours' slivers inside its bounding
		# box are cleared)
		var piece := PackedByteArray()
		piece.resize(bbox.size.x * bbox.size.y * 4)
		piece.fill(0)
		for y in bbox.size.y:
			var row := (bbox.position.y + y) * w + bbox.position.x
			for x in bbox.size.x:
				if keep.has(labels[row + x]):
					var s := (row + x) * 4
					var d := (y * bbox.size.x + x) * 4
					piece[d] = data[s]
					piece[d + 1] = data[s + 1]
					piece[d + 2] = data[s + 2]
					piece[d + 3] = data[s + 3]
		var piece_img := Image.create_from_data(bbox.size.x, bbox.size.y, false, Image.FORMAT_RGBA8, piece)
		var center: Vector2i
		if center_mode == "centroid":
			center = Vector2i(roundi(sx / sa), roundi(sy / sa)) - bbox.position
		elif center_mode == "top_band":
			# Alpha centroid of the piece's top `band` rows (bbox top = topmost
			# art pixel)
			var bx := 0.0
			var by := 0.0
			var ba := 0.0
			for y in mini(band, bbox.size.y):
				for x in bbox.size.x:
					var pa := float(piece[(y * bbox.size.x + x) * 4 + 3])
					bx += x * pa
					by += y * pa
					ba += pa
			center = Vector2i(roundi(bx / ba), roundi(by / ba))
		else:
			center = Vector2i(bbox.size.x / 2, bbox.size.y / 2)
		frames.append({"image": piece_img, "rect": Rect2i(Vector2i.ZERO, bbox.size),
				"center": center, "data": piece, "origin": bbox.position})
	if refine > 0:
		for i in range(1, frames.size()):
			frames[i]["center"] += _best_shift(frames[0], frames[i], band, refine)
	for i in frames.size():
		var f: Dictionary = frames[i]
		f["center"] += center_offset
		print("resize_art: %s frame %d: art %s, center %s" % [entry["src"], i,
				Rect2i(f["origin"], f["rect"].size), f["center"] + f["origin"]])
	return frames

# "refine": the integer shift (within +-radius master px) that best lays
# frame f's top band over frame 0's: least sum of absolute alpha and luma
# differences over frame 0's top `band` rows (every 2nd pixel), compared
# around each frame's center
func _best_shift(ref: Dictionary, f: Dictionary, band: int, radius: int) -> Vector2i:
	var ref_size: Vector2i = ref["rect"].size
	var ref_c: Vector2i = ref["center"]
	var f_size: Vector2i = f["rect"].size
	var best := Vector2i.ZERO
	var best_cost := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cost := 0.0
			var off: Vector2i = f["center"] + Vector2i(dx, dy) - ref_c
			for y in range(0, mini(band, ref_size.y), 2):
				for x in range(0, ref_size.x, 2):
					var a := _alpha_luma(ref["data"], ref_size, x, y)
					var b := _alpha_luma(f["data"], f_size, x + off.x, y + off.y)
					cost += absf(a.x - b.x) + absf(a.y - b.y)
			if cost < best_cost:
				best_cost = cost
				best = Vector2i(dx, dy)
	return best

# (alpha, luma) of a piece pixel, (0, 0) outside the piece
func _alpha_luma(data: PackedByteArray, size: Vector2i, x: int, y: int) -> Vector2:
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return Vector2.ZERO
	var p := (y * size.x + x) * 4
	return Vector2(data[p + 3], 0.299 * data[p] + 0.587 * data[p + 1] + 0.114 * data[p + 2])
