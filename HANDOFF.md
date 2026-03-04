# DaVinci Image AI Clean Room - Handoff

Use this file to restart work in a new chat without losing momentum.

## 1) Project Goal
Build and extend a clean-room DaVinci Resolve Lua plugin that supports:
- Image generation and editing workflows
- Movie generation workflows (Veo)
- Configurable providers/endpoints/keys
- Gallery/history and reference management

## 2) Primary Files
- Main editable source:
  - `~/Documents/Black Magic Banana/Black Magic Banana.lua`
- Live Resolve script (deployed copy):
  - `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/DaVinci Banana.lua`

## 3) Deploy Step (after edits)
Copy updated source into Resolve script path:

```bash
cp "~/Documents/Black Magic Banana/Black Magic Banana.lua" "~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/DaVinci Banana.lua"
```

## 4) Current Known State (latest checkpoint)
- Plugin launches again after earlier startup nil crashes were fixed.
- Version string seen recently: `0.3.9`.
- Gemini image and movie flows are mostly wired.
- Veo failures often traced to safety filtering or missing URI return; last poll debug file:
  - `/tmp/davinci-image-ai-clean/veo_poll_last.json`
- User requested OpenAI support in-config and in generation tabs.
- OpenAI config fields were added, but model loading/generation wiring is incomplete.

## 5) Highest Priority Next Tasks
1. Finish OpenAI provider wiring end-to-end.
2. Make OpenAI models appear in generation tabs.
3. Route generation by provider:
   - Gemini path unchanged
   - OpenAI image generation path implemented with robust response parsing
4. Improve error message specificity (show API error body where possible).

## 6) UI/Workflow Expectations from User
- Keep strong visual layout for ImageGen/MovieGen/Configuration tabs.
- Gallery should be useful in both Image and Movie tabs.
- Delete-selected must actually remove from gallery lists.
- Clipboard paste should populate reference slots and enter recent references.
- Window behavior should stay non-disruptive while editing in Resolve.

## 7) Quick Smoke Test List
After each patch:
1. Script launches without Lua stack trace.
2. Switch tabs without flicker/crash.
3. Grab frame populates lowest empty reference slot.
4. Generate image returns and preview updates.
5. Movie generate starts and polling stops cleanly (no infinite running state).
6. Gallery updates and delete-selected works.
7. Save config persists across relaunch.

## 8) Fresh Chat Prompt Template
Paste this into a new chat:

```text
Continue from previous DaVinci plugin work.

Primary file:
~/Documents/Black Magic Banana/Black Magic Banana.lua

Deploy target:
~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/DaVinci Banana.lua

Read ~/Documents/New project/HANDOFF.md first.

Before editing, summarize your understanding in 5 bullets, then implement.
Current task:
[PASTE ONE CONCRETE TASK]

Latest logs:
[PASTE LOGS]
```

## 9) Notes
- Do not include real API keys in logs/prompts.
- Keep changes in the clean-room source file, then deploy by copy.
