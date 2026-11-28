extends "res://addons/gd-plug/plug.gd"

# More info: https://github.com/imjp94/gd-plug

func _plugging():
	# {"dev": true} can be excluded or uninstalled with "production" command

	# Aseprite Wizard (Version v9.8.0-4)
	plug("viniciusgerevini/godot-aseprite-wizard", {"tag": "v9.8.0-4", "dev": true})
	
	# Unit test
	plug("bitwes/Gut", {"tag": "v9.7.1", "dev": true})
	
	# Godot MCP (editor plugin + MCP server bridge, 386 tools)
	plug("yanhuifair/godot-mcp", {"tag": "v1.12.18", "dev": true})
