# extended-pins

A World of Warcraft interface addon designed to expand the native map pin functionality, allowing for multiple simultaneous waypoints, proximity-based auto-routing, and bulk importing.

## Features

* **Multi-Pin System:** Bypasses the native single-pin limit. Placing a standard map waypoint automatically adds it to your extended routing list instead of overwriting your current pin.
* **Proximity Auto-Routing:** The addon continuously tracks your position and automatically routes you to the nearest pin in your current zone. 
* **Auto-Clear on Arrival:** Waypoints are automatically removed from your map and routing list the moment you arrive at their exact coordinates.
* **Bulk Import Support:** Uses the `/way` command to support multi-line pasting in popular formats, allowing you to instantly import massive lists of coordinates at once.
* **Interactive Map Pins:** Green untracked pins on your world map can be interacted with directly to manage your current route.

## Installation

Download the latest release from the Releases page or use WowUp's `Install from URL` functionality for automatic updating.

## Usage

**Adding Pins:**
* Ctrl+Click on the World Map to add waypoints exactly as you normally would. They will pool together instead of overwriting each other.
* Paste one or multiple `/way [zoneid] <x> <y> [name]` commands into your chat. 

**Managing Pins on the World Map:**
* **Left-Click a Pin:** Force the routing engine to prioritize tracking that specific pin, overriding the proximity (nearest-first) behavior.
* **Ctrl + Left-Click a Pin:** Manually delete that specific pin from your map and route.

**Slash Commands:**
* `/way clear` - Instantly removes all active pins and clears your current route.

## Versioning

Version numbers follow the WoW patch they were built for, plus an addon revision: `<patch>.<revision>` — e.g. `12.1.0.1` is the first release for patch 12.1.0. The revision resets to `1` on each new patch. Git tags use the same string.
