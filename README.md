# Black Magic Banana

## What it is
Black Magic Banana is a DaVinci Resolve UI plugin that brings AI image and video generation natively into your workflow. It allows you to rapidly generate media, manage a gallery of outputs, and use timeline references directly via the Gemini API without leaving DaVinci Resolve.

![Configuration Details](assets/BMB%20Screenshot%2001.jpg)
![Movie Generation](assets/BMB%20Screenshot%2002.jpg)
![Image Generation Options](assets/BMB%20Screenshot%2003.jpg)

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

## How to Use
1. **Connect:** Open the plugin's **Configuration** tab and paste your API Key.
2. **Set Parameters:** Switch to either the **ImageGen** or **MovieGen** tab. Select your desired AI Model, Aspect Ratio, and Resolution.
3. **Add References (Optional):** If you want your generation influenced by an existing image, either click **Grab Current Frame** (to pull directly from your Resolve timeline), select one from your Gallery, or right-click one of the 8 empty "Original" slots to manually paste or load an image path.
4. **Prompt:** Type a descriptive prompt describing what you want the AI to generate.
5. **Generate:** Hit the **Generate** button! The status box at the bottom will keep you updated.
6. **Import:** Once generated, the result will appear as a thumbnail. Click **Add to Media Pool** to cleanly inject it directly into your active DaVinci project bin!

## Troubleshooting
- If the script doesn’t appear in the menu, verify the target path exists and Resolve has been restarted.
- If UI looks stale, close and reopen the script panel; or try the "refresh UI" button. Resolve can cache geometry/styles between runs.
