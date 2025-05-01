# scoreboard_manager.gd
extends Node

# Constants
const SAVE_FILE_PATH = "user://highscores.save"
const MAX_SCORES = 5  # Maximum number of scores to store

# Score data structure
var high_scores = []

# Signal for when scores change
signal scores_updated

func _ready() -> void:
	# Load scores on startup
	load_scores()

# Add a new score to the high scores list
func add_score(player_name: String, height: float, points: int) -> bool:
	var new_score = {
		"name": player_name,
		"height": height,
		"points": points,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Add the new score
	high_scores.append(new_score)
	
	# Sort scores based on height (primary) and points (secondary)
	sort_scores()
	
	# Trim list to max number of scores
	if high_scores.size() > MAX_SCORES:
		high_scores.resize(MAX_SCORES)
	
	# Save to disk
	save_scores()
	
	# Emit signal
	scores_updated.emit()
	
	# Return true if the score made it onto the leaderboard
	return high_scores.has(new_score)

# Check if a score would make it onto the leaderboard
func would_make_leaderboard(height: float, points: int) -> bool:
	# If we don't have max scores yet, then yes
	if high_scores.size() < MAX_SCORES:
		return true
	
	# If high_scores array is empty (should never happen but let's be safe)
	if high_scores.is_empty():
		return true
		
	# Otherwise, check if it beats the lowest score
	var lowest_score = high_scores[high_scores.size() - 1]
	
	# Debug output to help diagnose issues
	print("New score: ", height, " pts: ", points, " vs lowest: ", 
		lowest_score.height, " pts: ", lowest_score.points)
		
	# Check if this score is higher than the lowest score on the board
	return is_score_higher(height, points, lowest_score.height, lowest_score.points)

# Sort scores based on height (primary) and points (secondary)
func sort_scores() -> void:
	high_scores.sort_custom(func(a, b):
		# First compare by height
		if a.height != b.height:
			return a.height > b.height  # Higher height is better
		
		# If heights are equal, compare by points
		if a.points != b.points:
			return a.points > b.points  # Higher points is better
		
		# If points are also equal, more recent scores are better
		return a.timestamp > b.timestamp
	)

# Helper to compare scores
func is_score_higher(height1: float, points1: int, height2: float, points2: int) -> bool:
	# First compare by height
	if height1 != height2:
		return height1 > height2
	
	# If heights are equal, compare by points
	return points1 > points2

# Save scores to disk
func save_scores() -> void:
	var save_file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if save_file:
		save_file.store_var(high_scores)
		save_file.close()

# Load scores from disk
func load_scores() -> void:
	if FileAccess.file_exists(SAVE_FILE_PATH):
		var save_file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
		if save_file:
			var loaded_data = save_file.get_var()
			save_file.close()
			
			# Validate the loaded data
			if loaded_data is Array:
				high_scores = loaded_data
				sort_scores()  # Ensure proper sorting
			else:
				# Invalid data, reset scores
				high_scores = []
	else:
		# No save file, start with empty list
		high_scores = []

# Clear all high scores
func clear_scores() -> void:
	high_scores = []
	save_scores()
	scores_updated.emit()

# Format a height value nicely
func format_height(height: float) -> String:
	return "%d m" % floor(height)

# Format a score value nicely
func format_points(points: int) -> String:
	return "%d points" % points

# Format a timestamp nicely
func format_timestamp(unix_time: float) -> String:
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%02d/%02d/%d" % [datetime.day, datetime.month, datetime.year]
