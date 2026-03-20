# Black Magic Banana (DaVinci Image AI Clean Room)

## Install (manual copy)
1. Close DaVinci Resolve (or at least close the script panel).
2. Copy the script file into the Resolve Fusion Scripts path:
   - Source: `~/Documents/Black Magic Banana/Black Magic Banana.lua`
   - Target: `/path/to/Fusion/Scripts/Utility/Black Magic Banana/Black Magic Banana.lua`
   - Example command (already approved in this project):  
     ```bash
     cp "~/Documents/Black Magic Banana/Black Magic Banana.lua" "/path/to/Fusion/Scripts/Utility/Black Magic Banana/Black Magic Banana.lua"
     ```
3. Reopen the script via Resolve: Workspace → Scripts → Utility → Black Magic Banana → `Black Magic Banana.lua`.

## Update workflow we use
- Make changes in the source file above, then run the copy command to deploy.
- If Resolve was open, click “Refresh UI” in the panel or reopen the script to load the new version.

## Requirements
- DaVinci Resolve installed with Fusion scripting enabled.
- macOS paths above assume the default user library location.

## Troubleshooting
- If the script doesn’t appear in the menu, verify the target path exists and Resolve has been restarted.
- If UI looks stale, close and reopen the script panel; Resolve can cache geometry/styles between runs.
