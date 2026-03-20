# Black Magic Banana

## What it is
Black Magic Banana is a DaVinci Resolve UI plugin that brings AI image and video generation natively into your workflow. It allows you to rapidly generate media, manage a gallery of outputs, and use timeline references directly via the Gemini API without leaving DaVinci Resolve.

> [!WARNING]  
> **Compatibility Note:** This plugin has currently only been tested on an **Apple M4 running macOS Tahoe** and **DaVinci Resolve Studio 20**. It may require adjustments for Windows or older Resolve versions.

## Requirements
- **DaVinci Resolve Studio** (Scripting is restricted in the free version).
- macOS (paths below assume the standard user library location).
- A valid API Key entered into the script's Configuration tab. *(You can get a free Google Gemini key from [Google AI Studio](https://aistudio.google.com/app/apikey)).*

## Install
1. Download a `.zip` of this repository from GitHub and extract it.
2. Close DaVinci Resolve (or at least close the script panel).
3. Drag the entire extracted folder into your Resolve Fusion Scripts path:
   `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`
   *(**Mac Tip:** In Finder, press **Cmd + Shift + G** ("Go to Folder"), paste the path above, and hit Return to jump straight to this hidden folder. Alternatively, pressing **Cmd + Shift + Period** will expose all hidden files in Finder, including the Library folder!)*
4. Reopen the script via Resolve top menu: Workspace → Scripts → Utility → (Your Extracted Folder) → `Black Magic Banana.lua`.

## Troubleshooting
- If the script doesn’t appear in the menu, verify the target path exists and Resolve has been restarted.
- If UI looks stale, close and reopen the script panel; or try the "refresh UI" button. Resolve can cache geometry/styles between runs.
