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
- A valid API Key entered into the script's Configuration tab. *(You can get a free Google Gemini key from [Google AI Studio](https://aistudio.google.com/api-keys)).*

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

## API Key Security
Your Gemini API key is stored in the **macOS Keychain** (not in a plaintext file). On first launch the script registers the key under the service name `BlackMagicBanana` in your login Keychain — you can inspect or delete it any time via **Keychain Access.app**.

If you had a previous version (before v0.5.0) that stored the key in the settings file, it is automatically migrated to Keychain on first launch. No manual action required.

You can also supply the key via environment variable as a fallback:
```bash
export DAVINCI_IMAGE_AI_API_KEY="your-key-here"
```

## Troubleshooting

**The script doesn't appear in the Workspace → Scripts menu.**
- Verify the install path exists and contains the `.lua` file directly inside the extracted folder.
- Restart DaVinci Resolve fully (Quit, not just close the panel).
- On macOS, confirm the Library folder is not read-only: `ls -la ~/Library/Application\ Support/Blackmagic\ Design/`

**The UI looks blank or stale after reopening.**
- Close the script panel entirely and reopen it via the menu. Resolve caches geometry between runs.
- If the problem persists, try the **Refresh UI** button if visible, or quit and relaunch Resolve.

**"Gemini API key is invalid or missing" / HTTP 401 error.**
- Double-check your key in the Configuration tab and hit **Save Settings**.
- Verify the key is active at [Google AI Studio](https://aistudio.google.com/api-keys).
- If you set the key via environment variable, make sure Resolve was launched from a shell that has it set (Resolve launched from the Dock may not inherit your shell environment).
- You can verify what's in the Keychain directly: open **Keychain Access.app** and search for `BlackMagicBanana`.

**"Rate limit exceeded" / HTTP 429 error.**
- You have hit your free-tier quota. Wait 60 seconds and try again. For heavy use, monitor your quota at [Google AI Studio](https://aistudio.google.com/api-keys).

**"Forbidden" / HTTP 403 on a specific model.**
- Some models (e.g. Veo 3.1) require allowlist access. Check your model access at Google AI Studio and apply for early access if needed.

**Video generation hangs or times out.**
- Veo operations can take 5–20 minutes. The script polls every 5 seconds up to 20 minutes. Do not close the script panel during generation.
- Check `~/Movies/DaVinci Resolve Studio/Black Magic Banana/Debug/` for `veo_poll_last.json` to see the last raw API response if you want to diagnose further.

**"No image payload found in response."**
- This usually means the safety filters blocked the generation silently. Try rephrasing your prompt. Check the debug directory for `veo_start_last.json` or the startup log for the raw response.

**Generated output files are not appearing in the gallery.**
- Confirm the output directory in the Configuration tab is writable. The default is `~/Movies/DaVinci Resolve Studio/Black Magic Banana/Output/`.

## Platform Support
Black Magic Banana is developed and tested on **macOS**. Several features use macOS-specific tools (`security` for Keychain, `pbcopy`, `sips`, `osascript`, QuickTime Player).

**Windows / Linux contributors welcome!** The core generation logic (Gemini API calls, Veo polling, gallery, history) is fully platform-agnostic. If you test on Windows or Linux and work out the platform-specific path handling, please open a pull request — even partial compatibility improvements are appreciated.

## Changelog
See [CHANGELOG.md](CHANGELOG.md) for a full version history.
