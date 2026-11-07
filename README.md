# autoclick

Sends one mouse action to Minecraft Java while it sits in the background on macOS: hold left/right, or click left/right every X seconds.

## Setup (once)
1. In Minecraft press **F3+P** so the game doesn't pause when it loses focus.
2. Give your terminal app (Terminal/iTerm) Accessibility access: System Settings → Privacy & Security → Accessibility. macOS prompts on first launch; restart the tool after granting.

## Run
```sh
swift autoclick.swift
# or compile once: swiftc -O autoclick.swift -o autoclick && ./autoclick
```
Pick the button and mode, press Start. Stop, closing the window, or Ctrl+C always releases the button.

## Notes
- Keep the Minecraft window open (not minimized); look at the target before switching away.
- Holding left to *mine* likely won't work in the background (Minecraft only mines with the mouse captured). Left-click every X and right-hold do.
- Single-player / your own servers only; most servers ban autoclickers.
