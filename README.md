# Black Magic Banana

## Requirements
- **DaVinci Resolve Studio** (Scripting is restricted in the free version).
- macOS (paths above assume the default user library location).
- A valid API Key (e.g., Google Gemini) entered into the script's Configuration tab.

## Install (manual copy)
1. Close DaVinci Resolve (or at least close the script panel).
2. Copy the script file into the Resolve Fusion Scripts path:
   - Source: `Black Magic Banana.lua` (from this repository)
   - Target: `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Black Magic Banana/Black Magic Banana.lua`
   - Example command:  
     ```bash
     mkdir -p "~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Black Magic Banana"
     cp "Black Magic Banana.lua" "~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Black Magic Banana/Black Magic Banana.lua"
     ```
3. Reopen the script via Resolve: Workspace → Scripts → Utility → Black Magic Banana → `Black Magic Banana.lua`.

## Update workflow we use
- Make changes in the source file above, then run the copy command to deploy.
- If Resolve was open, click “Refresh UI” in the panel or reopen the script to load the new version.

## Troubleshooting
- If the script doesn’t appear in the menu, verify the target path exists and Resolve has been restarted.
- If UI looks stale, close and reopen the script panel; Resolve can cache geometry/styles between runs.
