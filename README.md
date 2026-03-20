# Black Magic Banana

## Requirements
- **DaVinci Resolve Studio** (Scripting is restricted in the free version).
- macOS (paths below assume the standard user library location).
- A valid API Key (e.g., Google Gemini) entered into the script's Configuration tab.

## Install
1. Download a `.zip` of this repository from GitHub and extract it.
2. Close DaVinci Resolve (or at least close the script panel).
3. Drag the entire extracted folder into your Resolve Fusion Scripts path:
   `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`
4. Reopen the script via Resolve top menu: Workspace → Scripts → Utility → (Your Extracted Folder) → `Black Magic Banana.lua`.

## Update workflow we use
- Ensure the script panel is closed in DaVinci Resolve.
- Replace the files in your `Utility` folder with the new versions from GitHub.
- Reopen the script to load the new version.

## Troubleshooting
- If the script doesn’t appear in the menu, verify the target path exists and Resolve has been restarted.
- If UI looks stale, close and reopen the script panel; Resolve can cache geometry/styles between runs.
