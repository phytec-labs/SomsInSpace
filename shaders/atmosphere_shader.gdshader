shader_type canvas_item;

uniform vec4 current_color : source_color;
uniform vec4 target_color : source_color;
uniform float transition_progress : hint_range(0.0, 1.0) = 1.0;
uniform float gradient_size : hint_range(0.0, 1.0) = 0.1;

void fragment() {
    // Calculate the wipe threshold with gradient, add extra room for offscreen movement
    float threshold = transition_progress * 1.2; // Add 20% to allow movement below screen
    float position = UV.y;

    // Create smooth transition band
    float gradient_start = threshold - gradient_size;
    float gradient_end = threshold + gradient_size;

    if (position < gradient_start) {
        COLOR = target_color;
    } else if (position > gradient_end) {
        COLOR = current_color;
    } else {
        float t = (position - gradient_end) / (gradient_start - gradient_end);
        COLOR = mix(current_color, target_color, t);
    }
}
