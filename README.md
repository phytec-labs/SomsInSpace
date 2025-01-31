# Soms In Space!

A PHYTEC demo project where you play as a PHYTEC SoM making your way to outer space. This project showcases capabilities of our various products and serves as a conversation starter for trade shows.

## Running the Game

### Launching with OpenGL3
```bash
/home/Soms-In-Space.sh --rendering-driver opengl3
```

### Rotating Weston Display
To rotate the display, you'll need to edit the weston.ini file and add an output configuration.

On the phyBOARD LYRA AM62x, weston.ini can be found at:
```bash
/etc/xdg/weston/weston.ini
```

Add the following configuration to the bottom of the file:
```ini
[output]
name=HDMI-A-1
mode=1920x1080@60.0
transform=rotate-90
```

Restart the service to apply changes:
```bash
systemctl restart weston.service
```

**Note:** This configuration works for HDMI. LVDS/MIPI-DSI outputs will require different config names.

### Enabling Debug
```bash
export WAYLAND_DEBUG=1
```

## Configuration File Locations
According to Weston documentation, the config file can be found in these locations (in order of priority):

1. `$XDG_CONFIG_HOME/weston.ini` (if `$XDG_CONFIG_HOME` is set)
2. `$HOME/.config/weston.ini` (if `$HOME` is set)
3. `weston/weston.ini` in each `$XDG_CONFIG_DIR` (if `$XDG_CONFIG_DIRS` is set)
4. `/etc/xdg/weston/weston.ini` (if `$XDG_CONFIG_DIRS` is not set)
