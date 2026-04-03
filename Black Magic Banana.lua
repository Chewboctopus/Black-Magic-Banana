-- DaVinci Image AI (Clean Room) - Rebuild Baseline
-- Rebuilt from conversation requirements after corrupted intermediate versions.

math.randomseed(os.time())

local App = {}
local HOME_DIR = os.getenv("HOME") or ""
local DEFAULT_STORAGE_ROOT = HOME_DIR .. "/Movies/DaVinci Resolve Studio/Black Magic Banana/"
local DEFAULT_REFS_DIR = DEFAULT_STORAGE_ROOT .. "Refs/"
local DEFAULT_TEMP_DIR = DEFAULT_STORAGE_ROOT .. "Temp/"
local DEFAULT_OUTPUT_DIR = DEFAULT_STORAGE_ROOT .. "Output/"
local DEFAULT_MEDIA_POOL_DIR = DEFAULT_STORAGE_ROOT .. "Media Pool/"
local DEFAULT_DEBUG_DIR = DEFAULT_STORAGE_ROOT .. "Debug/"
local LEGACY_TEMP_DIR = "/tmp/davinci-image-ai-clean/"
local LEGACY_OUTPUT_DIR = "/tmp/davinci-image-ai-clean/output/"

App.Config = {
    script_name = "Black Magic Banana",
    script_version = "0.5.0",
    refs_dir = DEFAULT_REFS_DIR,
    temp_dir = DEFAULT_TEMP_DIR,
    output_dir = DEFAULT_OUTPUT_DIR,
    media_pool_dir = DEFAULT_MEDIA_POOL_DIR,
    debug_dir = DEFAULT_DEBUG_DIR,

    gemini_api_url = "https://generativelanguage.googleapis.com/v1beta",
    gemini_api_key = os.getenv("DAVINCI_IMAGE_AI_API_KEY") or "",
    image_model = "gemini-2.5-flash-image",
    image_aspect_ratio = "16:9",
    image_size = "1K",

    movie_model = "veo-3.1-generate-preview",
    movie_ref_mode = "frames",
    movie_aspect_ratio = "16:9",
    movie_resolution = "720p",
    movie_duration = "8",
    movie_negative_prompt = "",

    max_http_seconds = 360,
    max_poll_seconds = 1200,

    ref_preview_max = 800,
    result_preview_max = 1400,

    history_limit = 300
}

App.Paths = {
    settings_path = (os.getenv("HOME") or "") .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Black Magic Banana_v000/Black Magic Banana/cleanroom_settings.conf",
    history_path = (os.getenv("HOME") or "") .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/Black Magic Banana_v000/Black Magic Banana/cleanroom_history.conf",
    startup_log = DEFAULT_DEBUG_DIR .. "startup.log"
}

App.State = {
    ui = nil,
    win = nil,
    items = nil,

    current_tab = "image",

    image_refs = {nil, nil, nil, nil, nil, nil, nil, nil},
    image_ref_meta = {nil, nil, nil, nil, nil, nil, nil, nil},
    image_max_refs = 8,

    movie_refs = {nil, nil, nil, nil, nil, nil, nil, nil},
    movie_ref_meta = {nil, nil, nil, nil, nil, nil, nil, nil},
    movie_max_refs = 2,

    last_image_path = nil,
    last_movie_path = nil,
    last_movie_uri = nil,
    image_generating = false,
    movie_generating = false,

    preview_cache = {},

    history = {},

    image_gallery_list = {},
    movie_gallery_list = {},
    image_gallery_index = 1,
    movie_gallery_index = 1,
    image_gallery_offset = 1,
    movie_gallery_offset = 1,
    image_gallery_page_size = 4,
    movie_gallery_page_size = 4,
    gallery_button_count = 12,
    gallery_scroll_sync = false,
    gallery_browser_open = false,
    image_wheel_accum = 0,
    movie_wheel_accum = 0,

    image_prompt_cursor = nil,
    movie_prompt_cursor = nil,

    image_models = {},
    movie_models = {},
    ui_updating = false,
    ui_refreshing = false,
    -- Undo last cleared ref slot: {tab, slot_index, path}
    last_cleared_ref = nil
}

App.Core = {}
App.Core.resolve = resolve
if not App.Core.resolve and type(Resolve) == "function" then
    local ok, r = pcall(function() return Resolve() end)
    if ok then
        App.Core.resolve = r
    end
end
App.Core.fusion = App.Core.resolve and App.Core.resolve:Fusion()
App.Core.ui = App.Core.fusion and App.Core.fusion.UIManager
App.Core.disp = (App.Core.ui and bmd and bmd.UIDispatcher) and bmd.UIDispatcher(App.Core.ui) or nil

local function append_startup_log(line)
    local debug_dir = tostring(App.Config.debug_dir or DEFAULT_DEBUG_DIR):gsub("'", "'\\''")
    os.execute("mkdir -p '" .. debug_dir .. "' >/dev/null 2>&1")
    local f = io.open(App.Paths.startup_log, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(line) .. "\n")
        f:close()
    end
end

local function log(msg)
    local line = "[" .. App.Config.script_name .. "] " .. tostring(msg)
    print(line)
    append_startup_log(line)
end

local function trim(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function ensure_dir_suffix(path)
    path = trim(path)
    if path ~= "" and path:sub(-1) ~= "/" then
        path = path .. "/"
    end
    return path
end

local function is_legacy_tmp_path(path)
    path = ensure_dir_suffix(path)
    return path == ensure_dir_suffix(LEGACY_TEMP_DIR) or path == ensure_dir_suffix(LEGACY_OUTPUT_DIR)
end

local function shell_quote(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function cfg_quote(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\r", " ")
    s = s:gsub("\n", " ")
    return "\"" .. s .. "\""
end

local function file_exists(path)
    if not path or path == "" then return false end
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_file(path, mode)
    local f = io.open(path, mode or "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_file(path, data, mode)
    local f = io.open(path, mode or "wb")
    if not f then return false end
    f:write(data or "")
    f:close()
    return true
end

local function mkdir_p(path)
    os.execute("mkdir -p " .. shell_quote(path) .. " >/dev/null 2>&1")
end

local function apply_storage_defaults()
    App.Config.refs_dir = ensure_dir_suffix(App.Config.refs_dir or DEFAULT_REFS_DIR)
    App.Config.temp_dir = ensure_dir_suffix(App.Config.temp_dir or DEFAULT_TEMP_DIR)
    App.Config.debug_dir = ensure_dir_suffix(App.Config.debug_dir or DEFAULT_DEBUG_DIR)

    local out_dir = ensure_dir_suffix(App.Config.output_dir or "")
    if out_dir == "" or is_legacy_tmp_path(out_dir) then
        App.Config.output_dir = DEFAULT_OUTPUT_DIR
    else
        App.Config.output_dir = out_dir
    end

    local pool_dir = ensure_dir_suffix(App.Config.media_pool_dir or "")
    if pool_dir == "" or is_legacy_tmp_path(pool_dir) then
        App.Config.media_pool_dir = DEFAULT_MEDIA_POOL_DIR
    else
        App.Config.media_pool_dir = pool_dir
    end

    if is_legacy_tmp_path(App.Config.temp_dir) then
        App.Config.temp_dir = DEFAULT_TEMP_DIR
    end
    if is_legacy_tmp_path(App.Config.refs_dir) then
        App.Config.refs_dir = DEFAULT_REFS_DIR
    end
    if is_legacy_tmp_path(App.Config.debug_dir) then
        App.Config.debug_dir = DEFAULT_DEBUG_DIR
    end

    App.Paths.startup_log = App.Config.debug_dir .. "startup.log"
end

local function basename(path)
    path = tostring(path or "")
    local n = path:match("([^/]+)$")
    return n or path
end

local function split_ext(path)
    local dir = path:match("^(.*)/") or ""
    local base = basename(path)
    local stem, ext = base:match("^(.*)%.([A-Za-z0-9]+)$")
    if not stem then
        stem = base
        ext = ""
    end
    if dir ~= "" then dir = dir .. "/" end
    return dir, stem, ext
end

local function sanitize_name(s)
    s = trim(s)
    if s == "" then return "Project" end
    s = s:gsub("[^A-Za-z0-9_%-]", "_")
    s = s:gsub("_+", "_")
    s = s:gsub("^_+", "")
    s = s:gsub("_+$", "")
    if s == "" then s = "Project" end
    return s
end

local function sanitize_token(s)
    s = trim(s)
    if s == "" then return "" end
    s = s:gsub("[^A-Za-z0-9_%-]", "_")
    s = s:gsub("_+", "_")
    s = s:gsub("^_+", "")
    s = s:gsub("_+$", "")
    return s
end

local function json_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    s = s:gsub("\b", "\\b")
    s = s:gsub("\f", "\\f")
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function urlencode(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function urldecode(s)
    s = tostring(s or "")
    s = s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return s
end

local function now_ms()
    -- Use os.clock() fractional part for sub-millisecond uniqueness on rapid calls,
    -- combined with os.time() epoch so values stay monotonically large.
    local frac = math.floor((os.clock() % 1) * 1000)
    return os.time() * 1000 + frac + math.random(0, 9)
end

local function timestamp_compact()
    return os.date("%Y_%m_%d_%H%M%S")
end

local function run_shell_ok(cmd)
    local ok, why, code = os.execute(cmd)
    if type(ok) == "number" then
        return ok == 0, ok
    end
    if ok == true then
        return true, tonumber(code) or 0
    end
    return false, tonumber(code) or -1
end

local has_cmd
local ensure_png
local unique_path
local sanitize_ref_slots_for_limits

local function open_in_preview(path)
    if not path or path == "" then return false end
    if not file_exists(path) then return false end
    local ok = run_shell_ok("open -a Preview " .. shell_quote(path) .. " >/dev/null 2>&1")
    if ok then return true end
    return run_shell_ok("open " .. shell_quote(path) .. " >/dev/null 2>&1")
end

-- Open any file: images go to Preview, videos go to QuickTime Player
local function open_file(path)
    if not path or path == "" then return false end
    if not file_exists(path) then return false end
    local p = path:lower()
    if p:match("%.mp4$") or p:match("%.mov$") or p:match("%.m4v$") or p:match("%.avi$") then
        local ok = run_shell_ok("open -a 'QuickTime Player' " .. shell_quote(path) .. " >/dev/null 2>&1")
        if ok then return true end
    end
    return run_shell_ok("open " .. shell_quote(path) .. " >/dev/null 2>&1")
end

local function reveal_in_finder(path)
    if not path or path == "" then return false end
    if not file_exists(path) then return false end
    return run_shell_ok("open -R " .. shell_quote(path) .. " >/dev/null 2>&1")
end

local function is_image_path(path)
    local p = tostring(path or ""):lower()
    return p:match("%.png$") or p:match("%.jpg$") or p:match("%.jpeg$")
        or p:match("%.tif$") or p:match("%.tiff$") or p:match("%.bmp$")
        or p:match("%.gif$") or p:match("%.webp$") or p:match("%.heic$")
end

local function copy_text_to_clipboard(txt)
    if not has_cmd("pbcopy") then return false end
    local tmp = unique_path(App.Config.temp_dir, "clipboard_text", "txt")
    write_file(tmp, tostring(txt or ""), "wb")
    local ok = run_shell_ok("cat " .. shell_quote(tmp) .. " | pbcopy")
    os.remove(tmp)
    return ok
end

local function copy_image_to_clipboard(path)
    if not has_cmd("osascript") then return false end
    if not path or path == "" or not file_exists(path) then return false end
    local png = ensure_png(path)
    if not png or not file_exists(png) then return false end

    local script_path = unique_path(App.Config.temp_dir, "clipboard_image", "applescript")
    local script = [[
on run argv
    set p to item 1 of argv
    set f to open for access (POSIX file p)
    try
        set d to read f as «class PNGf»
        close access f
    on error errMsg number errNum
        try
            close access f
        end try
        error errMsg number errNum
    end try
    set the clipboard to d
end run
]]
    write_file(script_path, script, "wb")
    local ok = run_shell_ok("osascript " .. shell_quote(script_path) .. " " .. shell_quote(png) .. " >/dev/null 2>&1")
    os.remove(script_path)
    return ok
end

local function copy_media_to_clipboard(path)
    if is_image_path(path) and copy_image_to_clipboard(path) then
        return true, "Copied image to clipboard."
    end
    if copy_text_to_clipboard(path) then
        return true, "Copied path to clipboard."
    end
    return false, "Clipboard copy failed."
end

has_cmd = function(cmd)
    local ok = run_shell_ok("command -v " .. cmd .. " >/dev/null 2>&1")
    return ok
end

local function current_project_name()
    local pm = App.Core.resolve and App.Core.resolve:GetProjectManager()
    local project = pm and pm:GetCurrentProject()
    if project and project.GetName then
        local ok, name = pcall(function() return project:GetName() end)
        if ok and name and name ~= "" then
            return tostring(name)
        end
    end
    return "Project"
end

local function project_prefix()
    return sanitize_name(current_project_name())
end

unique_path = function(dir, prefix, ext)
    mkdir_p(dir)
    local base = prefix .. "_" .. tostring(now_ms())
    local path = dir .. base .. "." .. ext
    return path
end

local function build_media_path(dir, prefix, ext)
    local safe_prefix = sanitize_name(prefix or "media")
    local base = project_prefix() .. "_" .. safe_prefix .. "_" .. timestamp_compact()
    mkdir_p(dir)
    local p = dir .. base .. "." .. ext
    local idx = 1
    while file_exists(p) do
        p = dir .. base .. "_" .. tostring(idx) .. "." .. ext
        idx = idx + 1
    end
    return p
end

local function build_output_path(kind, ext)
    return build_media_path(App.Config.output_dir, kind or "output", ext)
end

local function build_ref_path(kind, ext)
    return build_media_path(App.Config.refs_dir, kind or "ref", ext)
end

local function combo_set_items(combo, list, default_value)
    if not combo then return end
    local arr = list or {}
    combo:Clear()
    local set_idx = 0
    for i, v in ipairs(arr) do
        combo:AddItem(tostring(v))
        if default_value and tostring(v) == tostring(default_value) then
            set_idx = i - 1
        end
    end
    if #arr > 0 then
        combo.CurrentIndex = set_idx
    end
end

local function combo_current_text(combo)
    if not combo then return "" end
    return trim(combo.CurrentText or "")
end

local function parse_keyval_lines(txt)
    local out = {}
    for line in tostring(txt or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Za-z0-9_]+)=(.*)$")
        if k then
            out[k] = urldecode(v)
        end
    end
    return out
end

local function encode_keyval_lines(tbl, keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local v = tbl[k]
        if v ~= nil then
            lines[#lines + 1] = k .. "=" .. urlencode(tostring(v))
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------
-- macOS Keychain helpers
-- The API key is stored in the user's login Keychain rather than plaintext.
-- Falls back gracefully if the `security` tool is unavailable (non-macOS).
-- ---------------------------------------------------------------------------
local KEYCHAIN_SERVICE = "BlackMagicBanana"
local KEYCHAIN_ACCOUNT = os.getenv("USER") or "user"

local function keychain_read_key()
    if not has_cmd("security") then return nil end
    local tmp = unique_path(App.Config.temp_dir or "/tmp", "kc_read", "txt")
    local cmd = string.format(
        "security find-generic-password -a %s -s %s -w > %s 2>/dev/null",
        shell_quote(KEYCHAIN_ACCOUNT),
        shell_quote(KEYCHAIN_SERVICE),
        shell_quote(tmp)
    )
    run_shell_ok(cmd)
    local val = read_file(tmp, "rb")
    pcall(function() os.remove(tmp) end)
    if val then val = trim(val) end
    if val and val ~= "" then return val end
    return nil
end

local function keychain_write_key(key_value)
    if not has_cmd("security") then return false end
    key_value = tostring(key_value or "")
    -- Delete any existing entry first so the add never fails.
    run_shell_ok(string.format(
        "security delete-generic-password -a %s -s %s > /dev/null 2>&1",
        shell_quote(KEYCHAIN_ACCOUNT),
        shell_quote(KEYCHAIN_SERVICE)
    ))
    if key_value == "" then return true end -- deletion was the goal
    local ok = run_shell_ok(string.format(
        "security add-generic-password -U -a %s -s %s -w %s > /dev/null 2>&1",
        shell_quote(KEYCHAIN_ACCOUNT),
        shell_quote(KEYCHAIN_SERVICE),
        shell_quote(key_value)
    ))
    return ok
end

local function keychain_delete_key()
    if not has_cmd("security") then return end
    run_shell_ok(string.format(
        "security delete-generic-password -a %s -s %s > /dev/null 2>&1",
        shell_quote(KEYCHAIN_ACCOUNT),
        shell_quote(KEYCHAIN_SERVICE)
    ))
end

local function load_settings()
    local txt = read_file(App.Paths.settings_path, "rb")
    if txt and txt ~= "" then
        local kv = parse_keyval_lines(txt)

        App.Config.gemini_api_url = kv.gemini_api_url or App.Config.gemini_api_url
        -- Legacy: migrate plaintext key from conf file into Keychain on first load.
        if kv.gemini_api_key and kv.gemini_api_key ~= "" then
            keychain_write_key(kv.gemini_api_key)
            log("Migrated API key from settings file to macOS Keychain.")
        end

        App.Config.output_dir = kv.output_dir or App.Config.output_dir
        App.Config.media_pool_dir = kv.media_pool_dir or App.Config.media_pool_dir

        App.Config.image_model = kv.image_model or App.Config.image_model
        App.Config.image_aspect_ratio = kv.image_aspect_ratio or App.Config.image_aspect_ratio
        App.Config.image_size = kv.image_size or App.Config.image_size

        App.Config.movie_model = kv.movie_model or App.Config.movie_model
        App.Config.movie_ref_mode = kv.movie_ref_mode or App.Config.movie_ref_mode
        App.Config.movie_aspect_ratio = kv.movie_aspect_ratio or App.Config.movie_aspect_ratio
        App.Config.movie_resolution = kv.movie_resolution or App.Config.movie_resolution
        App.Config.movie_duration = kv.movie_duration or App.Config.movie_duration
        App.Config.movie_negative_prompt = kv.movie_negative_prompt or App.Config.movie_negative_prompt
    end

    -- Always load the API key from Keychain (preferred), then fall back to
    -- the DAVINCI_IMAGE_AI_API_KEY env var, then keep whatever is already set.
    local kc_key = keychain_read_key()
    if kc_key and kc_key ~= "" then
        App.Config.gemini_api_key = kc_key
    end

    apply_storage_defaults()
end

local function save_settings()
    apply_storage_defaults()
    -- Persist the API key to Keychain, not to the conf file.
    keychain_write_key(App.Config.gemini_api_key)
    local keys = {
        "gemini_api_url",
        -- NOTE: gemini_api_key intentionally omitted — stored in Keychain.
        "output_dir", "media_pool_dir",
        "image_model", "image_aspect_ratio", "image_size",
        "movie_model", "movie_ref_mode", "movie_aspect_ratio", "movie_resolution", "movie_duration", "movie_negative_prompt"
    }
    local txt = encode_keyval_lines(App.Config, keys)
    write_file(App.Paths.settings_path, txt, "wb")
end

local function load_history()
    App.State.history = {}
    local txt = read_file(App.Paths.history_path, "rb")
    if not txt or txt == "" then return end
    for line in txt:gmatch("[^\r\n]+") do
        local kind, project, path, ts, sidecar = line:match("^([^\t]+)\t([^\t]*)\t([^\t]+)\t([^\t]+)\t?(.*)$")
        if kind and path then
            App.State.history[#App.State.history + 1] = {
                kind = kind,
                project = project or "",
                path = path,
                ts = tonumber(ts) or 0,
                sidecar = sidecar or ""
            }
        end
    end
end

local function save_history()
    table.sort(App.State.history, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
    end)

    local deduped = {}
    local seen = {}
    for _, e in ipairs(App.State.history) do
        local p = tostring(e.path or "")
        if p ~= "" and (not seen[p]) then
            seen[p] = true
            deduped[#deduped + 1] = e
        end
    end
    App.State.history = deduped

    local limit = App.Config.history_limit or 300
    if #App.State.history > limit then
        local trimmed = {}
        for i = 1, limit do
            trimmed[i] = App.State.history[i]
        end
        App.State.history = trimmed
    end

    local lines = {}
    for _, e in ipairs(App.State.history) do
        lines[#lines + 1] = table.concat({
            e.kind or "",
            e.project or "",
            e.path or "",
            tostring(e.ts or 0),
            e.sidecar or ""
        }, "\t")
    end
    write_file(App.Paths.history_path, table.concat(lines, "\n") .. (next(lines) and "\n" or ""), "wb")
end

local function add_history(kind, path, sidecar)
    if not path or path == "" then return end
    if not file_exists(path) then return end
    local deduped = {}
    for _, e in ipairs(App.State.history or {}) do
        if e.path ~= path then
            deduped[#deduped + 1] = e
        end
    end
    App.State.history = deduped
    App.State.history[#App.State.history + 1] = {
        kind = kind,
        project = project_prefix(),
        path = path,
        ts = now_ms(),
        sidecar = sidecar or ""
    }
    save_history()
end

local function delete_history_path(path)
    local kept = {}
    for _, e in ipairs(App.State.history) do
        if e.path ~= path then
            kept[#kept + 1] = e
        end
    end
    App.State.history = kept
    save_history()
end

local function sidecar_path_for(path)
    return tostring(path or "") .. ".json"
end

local function write_generation_sidecar(path, meta)
    local refs = meta.refs or {}
    local ref_lines = {}
    for i, r in ipairs(refs) do
        ref_lines[#ref_lines + 1] = "    \"" .. tostring(i) .. "\": \"" .. json_escape(r) .. "\""
    end

    local txt = "{\n"
        .. "  \"project\": \"" .. json_escape(project_prefix()) .. "\",\n"
        .. "  \"created_at\": \"" .. json_escape(os.date("!%Y-%m-%dT%H:%M:%SZ")) .. "\",\n"
        .. "  \"provider\": \"" .. json_escape(meta.provider or "") .. "\",\n"
        .. "  \"model\": \"" .. json_escape(meta.model or "") .. "\",\n"
        .. "  \"kind\": \"" .. json_escape(meta.kind or "") .. "\",\n"
        .. "  \"ref_mode\": \"" .. json_escape(meta.ref_mode or "") .. "\",\n"
        .. "  \"prompt\": \"" .. json_escape(meta.prompt or "") .. "\",\n"
        .. "  \"negative_prompt\": \"" .. json_escape(meta.negative_prompt or "") .. "\",\n"
        .. "  \"aspect_ratio\": \"" .. json_escape(meta.aspect_ratio or "") .. "\",\n"
        .. "  \"size_or_resolution\": \"" .. json_escape(meta.size_or_resolution or "") .. "\",\n"
        .. "  \"duration\": \"" .. json_escape(meta.duration or "") .. "\",\n"
        .. "  \"refs\": {\n"
        .. table.concat(ref_lines, ref_lines[1] and ",\n" or "")
        .. "\n  }\n"
        .. "}\n"

    local sp = sidecar_path_for(path)
    write_file(sp, txt, "wb")

    if path:lower():match("%.png$") and has_cmd("exiftool") then
        local comment = "provider=" .. tostring(meta.provider or "")
            .. " model=" .. tostring(meta.model or "")
            .. " prompt=" .. tostring(meta.prompt or "")
        local cmd = "exiftool -overwrite_original -Comment=" .. shell_quote(comment) .. " " .. shell_quote(path) .. " >/dev/null 2>&1"
        run_shell_ok(cmd)
    end

    return sp
end

local function read_generation_sidecar(path)
    local sp = sidecar_path_for(path)
    local txt = read_file(sp, "rb")
    if not txt or txt == "" then return nil end

    local out = {
        sidecar = sp,
        provider = txt:match('"provider"%s*:%s*"([^"]*)"') or "",
        model = txt:match('"model"%s*:%s*"([^"]*)"') or "",
        kind = txt:match('"kind"%s*:%s*"([^"]*)"') or "",
        ref_mode = txt:match('"ref_mode"%s*:%s*"([^"]*)"') or "",
        prompt = txt:match('"prompt"%s*:%s*"([^"]*)"') or "",
        negative_prompt = txt:match('"negative_prompt"%s*:%s*"([^"]*)"') or "",
        aspect_ratio = txt:match('"aspect_ratio"%s*:%s*"([^"]*)"') or "",
        size_or_resolution = txt:match('"size_or_resolution"%s*:%s*"([^"]*)"') or "",
        duration = txt:match('"duration"%s*:%s*"([^"]*)"') or "",
        refs = {}
    }

    for _, v in txt:gmatch('"%d+"%s*:%s*"([^"]+)"') do
        out.refs[#out.refs + 1] = v
    end
    return out
end

local function get_project_history(filter_kind)
    local p = project_prefix()
    local out = {}
    for _, e in ipairs(App.State.history) do
        local kind_ok = (filter_kind == "all")
            or (filter_kind == "refs" and e.kind == "ref")
            or (filter_kind == "images" and e.kind == "image_gen")
            or (filter_kind == "videos" and e.kind == "video_gen")
        if kind_ok and (e.project == p or e.project == "") and file_exists(e.path) then
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
    end)
    return out
end

local function gallery_filter_kind(label)
    local l = trim(label or ""):lower()
    if l:find("all", 1, true) then return "all" end
    if l:find("video", 1, true) then return "videos" end
    if l:find("image", 1, true) then return "images" end
    if l:find("ref", 1, true) then return "refs" end
    return "refs"
end

local HTTP_STATUS_HINTS = {
    [400] = "Bad request — check your prompt or model settings.",
    [401] = "Unauthorised — your API key is invalid or missing.",
    [403] = "Forbidden — your API key does not have access to this model or endpoint.",
    [404] = "Not found — the model or API endpoint does not exist. Check your API URL.",
    [429] = "Rate limit exceeded — you have hit your quota. Wait a moment and try again.",
    [500] = "Gemini server error — the API returned an internal error. Try again shortly.",
    [503] = "Gemini service unavailable — the API is temporarily down. Try again later.",
}

local function parse_http_error_message(body, status)
    -- Try to extract the developer message from the JSON body first.
    local msg = body:match('"message"%s*:%s*"([^"]+)"')
    if msg and trim(msg) ~= "" then
        -- Append a plain-English hint when we have one, unless the API message
        -- already explains the situation clearly.
        local hint = status and HTTP_STATUS_HINTS[tonumber(status)]
        if hint and not msg:lower():find("quota") and not msg:lower():find("key") then
            return msg .. "\nHint: " .. hint
        end
        return msg
    end
    -- Fall back to a plain-English hint if we at least know the status code.
    if status then
        local hint = HTTP_STATUS_HINTS[tonumber(status)]
        if hint then return hint end
    end
    return trim(body)
end

local function curl_config_request(url, headers, body_path, timeout_seconds)
    mkdir_p(App.Config.temp_dir)
    local cfg_path = unique_path(App.Config.temp_dir, "curl_req", "cfg")
    local out_path = unique_path(App.Config.temp_dir, "curl_resp", "body")
    local err_path = unique_path(App.Config.temp_dir, "curl_resp", "err")
    local code_path = unique_path(App.Config.temp_dir, "curl_resp", "status")

    local lines = {}
    lines[#lines + 1] = "url = " .. cfg_quote(url)
    lines[#lines + 1] = "request = POST"
    lines[#lines + 1] = "header = " .. cfg_quote("Content-Type: application/json")
    for _, h in ipairs(headers or {}) do
        lines[#lines + 1] = "header = " .. cfg_quote(h)
    end
    if body_path and body_path ~= "" then
        lines[#lines + 1] = "data-binary = " .. cfg_quote("@" .. body_path)
    end

    if not write_file(cfg_path, table.concat(lines, "\n") .. "\n", "wb") then
        return false, 0, "", "Failed writing curl config."
    end

    local cmd = string.format(
        "curl -sS -L --http1.1 --no-keepalive -m %d --config %s -o %s -w '%%{http_code}' > %s 2> %s",
        timeout_seconds or App.Config.max_http_seconds,
        shell_quote(cfg_path),
        shell_quote(out_path),
        shell_quote(code_path),
        shell_quote(err_path)
    )
    run_shell_ok(cmd)

    local status_raw = (read_file(code_path, "rb") or ""):gsub("%s+", "")
    local status = tonumber(status_raw) or 0
    local body = read_file(out_path, "rb") or ""
    local err = read_file(err_path, "rb") or ""
    -- Clean up every temp file we created (previously leaked on every call)
    pcall(function() os.remove(cfg_path) end)
    pcall(function() os.remove(out_path) end)
    pcall(function() os.remove(err_path) end)
    pcall(function() os.remove(code_path) end)
    if status == 0 and trim(err) ~= "" then
        return false, status, body, err
    end
    return true, status, body, err
end

local function curl_get(url, headers, timeout_seconds)
    mkdir_p(App.Config.temp_dir)
    local out_path = unique_path(App.Config.temp_dir, "curl_get", "body")
    local err_path = unique_path(App.Config.temp_dir, "curl_get", "err")
    local code_path = unique_path(App.Config.temp_dir, "curl_get", "status")

    local cmd_parts = {
        "curl -sS -L --http1.1 --no-keepalive",
        "-m " .. tostring(timeout_seconds or App.Config.max_http_seconds)
    }
    for _, h in ipairs(headers or {}) do
        cmd_parts[#cmd_parts + 1] = "-H " .. shell_quote(h)
    end
    cmd_parts[#cmd_parts + 1] = shell_quote(url)
    cmd_parts[#cmd_parts + 1] = "-o " .. shell_quote(out_path)
    cmd_parts[#cmd_parts + 1] = "-w '%{http_code}' > " .. shell_quote(code_path)
    cmd_parts[#cmd_parts + 1] = "2> " .. shell_quote(err_path)

    run_shell_ok(table.concat(cmd_parts, " "))

    local status_raw = (read_file(code_path, "rb") or ""):gsub("%s+", "")
    local status = tonumber(status_raw) or 0
    local body = read_file(out_path, "rb") or ""
    local err = read_file(err_path, "rb") or ""
    -- Clean up every temp file we created (previously leaked on every call)
    pcall(function() os.remove(out_path) end)
    pcall(function() os.remove(err_path) end)
    pcall(function() os.remove(code_path) end)
    return status, body, err
end

local function encode_file_base64(path)
    local out = unique_path(App.Config.temp_dir, "b64", "txt")
    local cmd = "openssl base64 -A -in " .. shell_quote(path) .. " -out " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd) and file_exists(out) then
        local txt = read_file(out, "rb") or ""
        os.remove(out)
        return txt:gsub("%s+", "")
    end
    return nil
end

local function decode_base64_to_file(payload, out_path)
    local in_path = unique_path(App.Config.temp_dir, "decode", "b64")
    write_file(in_path, payload or "", "wb")

    local cmd1 = "base64 -d -i " .. shell_quote(in_path) .. " -o " .. shell_quote(out_path) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd1) and file_exists(out_path) then
        os.remove(in_path)
        return true
    end

    local cmd2 = "openssl base64 -d -A -in " .. shell_quote(in_path) .. " -out " .. shell_quote(out_path) .. " >/dev/null 2>&1"
    local ok = run_shell_ok(cmd2) and file_exists(out_path)
    os.remove(in_path)
    return ok
end

local function image_mime_from_ext(path)
    local ext = (path:match("%.([A-Za-z0-9]+)$") or ""):lower()
    if ext == "png" then return "image/png" end
    if ext == "jpg" or ext == "jpeg" then return "image/jpeg" end
    if ext == "webp" then return "image/webp" end
    return "image/png"
end

ensure_png = function(src_path)
    if src_path:lower():match("%.png$") then
        return src_path
    end
    local out = unique_path(App.Config.temp_dir, "conv", "png")
    local cmd = "sips -s format png " .. shell_quote(src_path) .. " --out " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd) and file_exists(out) then
        return out
    end
    return src_path
end

local function ensure_jpeg(src_path)
    if src_path:lower():match("%.jpe?g$") then
        return src_path
    end
    local out = unique_path(App.Config.temp_dir, "conv", "jpg")
    local cmd = "sips -s format jpeg " .. shell_quote(src_path) .. " --out " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd) and file_exists(out) then
        return out
    end
    return src_path
end

local function parse_image_from_response(body)
    local mime, b64 = body:match('"inlineData"%s*:%s*%{[^}]-"mimeType"%s*:%s*"([^"]+)"[^}]-"data"%s*:%s*"([A-Za-z0-9+/=_%-%s]+)"')
    if not b64 then
        mime, b64 = body:match('"inline_data"%s*:%s*%{[^}]-"mime_type"%s*:%s*"([^"]+)"[^}]-"data"%s*:%s*"([A-Za-z0-9+/=_%-%s]+)"')
    end
    if not b64 then
        b64 = body:match('"b64_json"%s*:%s*"([A-Za-z0-9+/=_%-%s]+)"')
        if b64 then mime = "image/png" end
    end
    if not b64 then
        local dmime, db64 = body:match("data:([^;]+);base64,([A-Za-z0-9+/=_%-%s]+)")
        if db64 and db64 ~= "" then
            mime = dmime or "image/png"
            b64 = db64
        end
    end

    if b64 and #b64 > 100 then
        b64 = b64:gsub("%s+", ""):gsub("%%2B", "+"):gsub("%%2F", "/"):gsub("%%3D", "=")
        return mime or "image/png", b64
    end

    local url = body:match('"url"%s*:%s*"(https://[^"]+)"')
    if url then
        return "url", url
    end

    return nil, nil
end

local function download_file(url, headers, out_path)
    local parts = {
        "curl -sS -L --http1.1 --no-keepalive",
        "-m " .. tostring(App.Config.max_http_seconds)
    }
    for _, h in ipairs(headers or {}) do
        parts[#parts + 1] = "-H " .. shell_quote(h)
    end
    parts[#parts + 1] = shell_quote(url)
    parts[#parts + 1] = "-o " .. shell_quote(out_path)
    parts[#parts + 1] = ">/dev/null 2>&1"
    local ok = run_shell_ok(table.concat(parts, " "))
    return ok and file_exists(out_path)
end

local function resolve_project_and_pool()
    local pm = App.Core.resolve and App.Core.resolve:GetProjectManager()
    local project = pm and pm:GetCurrentProject()
    local pool = project and project:GetMediaPool()
    return project, pool
end

local function import_to_media_pool(path)
    local _, pool = resolve_project_and_pool()
    if not pool then
        return false, "Media pool unavailable."
    end
    local ok, err = pcall(function()
        pool:ImportMedia({path})
    end)
    if not ok then
        return false, tostring(err)
    end
    return true, nil
end

local function stage_and_import(path)
    local src = path
    if App.Config.media_pool_dir and trim(App.Config.media_pool_dir) ~= "" then
        mkdir_p(App.Config.media_pool_dir)
        local dst = App.Config.media_pool_dir .. basename(path)
        local cmd = "cp " .. shell_quote(path) .. " " .. shell_quote(dst)
        if run_shell_ok(cmd) and file_exists(dst) then
            src = dst
        end
    end
    local ok, err = import_to_media_pool(src)
    return ok, err, src
end

local function is_right_click_event(ev)
    if type(ev) ~= "table" then return false end
    local fields = {"Button", "button", "MouseButton", "mouseButton", "Buttons", "buttons"}
    for _, k in ipairs(fields) do
        local v = ev[k]
        if type(v) == "string" and v:lower():find("right", 1, true) then
            return true
        end
        if tonumber(v) == 2 then
            return true
        end
        if type(v) == "table" then
            if tonumber(v[2]) == 2 or tostring(v.RightButton or v.right):lower() == "true" then
                return true
            end
        end
    end
    return false
end

local function run_media_context_action(path, action)
    if not path or path == "" or not file_exists(path) then
        return false, "No file available for this action."
    end

    action = trim(action or "")
    if action == "Copy" then
        return copy_media_to_clipboard(path)
    elseif action == "Preview Full Screen" then
        if open_in_preview(path) then
            return true, "Opened in Preview:\n" .. tostring(path)
        end
        return false, "Failed to open Preview."
    elseif action == "Show in Finder" then
        if reveal_in_finder(path) then
            return true, "Revealed in Finder:\n" .. tostring(path)
        end
        return false, "Failed to reveal file in Finder."
    elseif action == "Add to Media Pool" then
        local ok, err, staged = stage_and_import(path)
        if ok then
            return true, "Added to Media Pool:\n" .. tostring(staged or path)
        end
        return false, "Add to Media Pool failed:\n" .. tostring(err)
    end
    return false, "Unknown action."
end

local function show_media_context_menu(path, title_hint, status_setter)
    local status = status_setter or log
    if not path or path == "" or (not file_exists(path)) then
        status("No media in this slot.")
        return
    end

    local actions = {"Copy", "Preview Full Screen", "Show in Finder", "Add to Media Pool"}
    local chosen = actions[1]
    local asked = false

    if App.Core.fusion and App.Core.fusion.AskUser then
        local ask_ok, resp = pcall(function()
            return App.Core.fusion:AskUser("Actions: " .. (title_hint or basename(path)), {
                {"ctx_action", "Dropdown", Name = "Action", Options = actions, Default = 0}
            })
        end)
        if ask_ok then
            asked = true
            if not resp then
                return
            end
            local idx = tonumber(resp.ctx_action) or 0
            if idx < 1 then idx = idx + 1 end
            chosen = actions[idx] or actions[1]
        end
    end

    if (not asked) then
        chosen = "Preview Full Screen"
    end

    local ok, msg = run_media_context_action(path, chosen)
    status(msg)
    if not ok then
        log("Context action failed: " .. tostring(chosen) .. " | " .. tostring(msg))
    end
end

local IMAGE_MODEL_CAPS = {
    ["gemini-2.5-flash-image"] = {alias = "Nano Banana", max_refs = 8, sizes = {"1K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-3.1-flash-image-preview"] = {alias = "Nano Banana 2", max_refs = 4, sizes = {"1K", "2K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-3-pro-image-preview"] = {alias = "Nano Banana Pro", max_refs = 8, sizes = {"1K", "2K", "4K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-2.0-flash-exp-image-generation"] = {alias = "Gemini 2 Flash Image", max_refs = 0, sizes = {"1K"}, aspects = {"16:9", "9:16", "1:1"}, enabled = false}
}

local MOVIE_MODEL_CAPS = {
    ["veo-3.1-generate-preview"] = {alias = "Veo 3.1", max_refs = 2, supports_last_frame = true, supports_reference_images = true, reference_image_max_refs = 3, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p", "4k"}, durations = {"4", "6", "8"}},
    ["veo-3.1-fast-generate-preview"] = {alias = "Veo 3.1 Fast", max_refs = 1, supports_last_frame = false, supports_reference_images = false, reference_image_max_refs = 0, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p"}, durations = {"4", "6", "8"}},
    ["veo-3-generate-preview"] = {alias = "Veo 3", max_refs = 2, supports_last_frame = true, supports_reference_images = false, reference_image_max_refs = 0, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p", "4k"}, durations = {"4", "6", "8"}},
    ["veo-3.0-generate-001"] = {alias = "Veo 3.0", max_refs = 2, supports_last_frame = true, supports_reference_images = false, reference_image_max_refs = 0, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p", "4k"}, durations = {"4", "6", "8"}},
    ["veo-3.0-fast-generate-001"] = {alias = "Veo 3.0 Fast", max_refs = 1, supports_last_frame = false, supports_reference_images = false, reference_image_max_refs = 0, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p"}, durations = {"4", "6", "8"}},
    ["veo-2"] = {alias = "Veo 2", max_refs = 2, supports_last_frame = true, supports_reference_images = false, reference_image_max_refs = 0, aspects = {"16:9", "9:16"}, resolutions = {"720p"}, durations = {"5", "6", "8"}}
}

local MOVIE_REF_MODE_LABELS = {
    frames = "First / Last Frame",
    ingredients = "Ingredients"
}

local DEFAULT_IMAGE_MODELS = {
    "gemini-2.5-flash-image",
    "gemini-3.1-flash-image-preview",
    "gemini-3-pro-image-preview"
}

local SUPPORTED_IMAGE_MODEL_SET = {}
for _, m in ipairs(DEFAULT_IMAGE_MODELS) do
    SUPPORTED_IMAGE_MODEL_SET[m] = true
end

local DEFAULT_MOVIE_MODELS = {
    "veo-3.1-generate-preview",
    "veo-3.1-fast-generate-preview",
    "veo-3-generate-preview"
}

local function image_model_display(model)
    local caps = IMAGE_MODEL_CAPS[model]
    if caps and caps.alias then
        return caps.alias .. " (" .. model .. ")"
    end
    return model
end

local function movie_model_display(model)
    local caps = MOVIE_MODEL_CAPS[model]
    if caps and caps.alias then
        return caps.alias .. " (" .. model .. ")"
    end
    return model
end

local function display_to_model(text)
    local m = text:match("%(([^%(%)]+)%)")
    if m and m ~= "" then return m end
    return trim(text)
end

local function list_contains(list, value)
    value = tostring(value or "")
    for _, v in ipairs(list or {}) do
        if tostring(v) == value then return true end
    end
    return false
end

local function is_supported_image_model(model)
    return SUPPORTED_IMAGE_MODEL_SET[tostring(model or "")] == true
end

local function filter_supported_image_models(list)
    local out = {}
    for _, m in ipairs(list or {}) do
        if is_supported_image_model(m) and (not list_contains(out, m)) then
            out[#out + 1] = m
        end
    end
    if #out == 0 then
        for _, m in ipairs(DEFAULT_IMAGE_MODELS) do
            out[#out + 1] = m
        end
    end
    return out
end

local function get_image_caps(model)
    local caps = IMAGE_MODEL_CAPS[model]
    if caps then return caps end
    return {
        max_refs = 4,
        sizes = {"1K"},
        aspects = {"16:9", "9:16", "1:1"}
    }
end

local function get_movie_caps(model)
    local caps = MOVIE_MODEL_CAPS[model]
    if caps then return caps end

    local lower = tostring(model or ""):lower()
    local is_fast = lower:find("fast", 1, true) ~= nil
    local is_veo2 = lower:find("veo%-2") ~= nil
    local out = {
        max_refs = is_fast and 1 or 2,
        supports_last_frame = not is_fast,
        supports_reference_images = false,
        reference_image_max_refs = 0,
        aspects = {"16:9", "9:16"},
        resolutions = is_fast and {"720p", "1080p"} or {"720p", "1080p", "4k"},
        durations = is_veo2 and {"5", "6", "8"} or {"4", "6", "8"}
    }
    if is_veo2 then
        out.resolutions = {"720p"}
    end
    return out
end

local function movie_ref_mode_display(mode)
    return MOVIE_REF_MODE_LABELS[mode] or MOVIE_REF_MODE_LABELS.frames
end

local function movie_ref_mode_from_text(text)
    local lower = trim(text or ""):lower()
    if lower:find("ingredient", 1, true) then
        return "ingredients"
    end
    return "frames"
end

local function get_effective_movie_ref_mode(caps)
    local mode = trim(App.Config.movie_ref_mode or "")
    if mode == "ingredients" and caps and caps.supports_reference_images then
        return "ingredients"
    end
    return "frames"
end

local function get_effective_movie_ref_limit(caps)
    local mode = get_effective_movie_ref_mode(caps or {})
    if mode == "ingredients" then
        return math.max(0, tonumber((caps or {}).reference_image_max_refs) or 3)
    end
    return math.max(0, tonumber((caps or {}).max_refs) or 0)
end

local function get_movie_slot_label(slot_index, supported)
    if not supported then
        return "N/A " .. tostring(slot_index)
    end

    local caps = get_movie_caps(App.Config.movie_model)
    local mode = get_effective_movie_ref_mode(caps)
    if mode == "ingredients" then
        return "Ingredient " .. tostring(slot_index)
    end
    if slot_index == 1 then
        return "First Frame"
    end
    if slot_index == 2 and caps.supports_last_frame then
        return "Last Frame"
    end
    return "Empty " .. tostring(slot_index)
end

local function load_preview_for_image(path, max_size, key_prefix)
    if not path or not file_exists(path) then return nil end
    local key = (key_prefix or "img") .. "|" .. path .. "|" .. tostring(max_size)
    local cached = App.State.preview_cache[key]
    if cached and file_exists(cached) then
        return cached
    end

    local out = unique_path(App.Config.temp_dir, key_prefix or "preview", "png")
    local src = ensure_png(path)
    local cmd = "sips -s format png -Z " .. tostring(max_size or 800) .. " " .. shell_quote(src) .. " --out " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd) and file_exists(out) then
        App.State.preview_cache[key] = out
        return out
    end
    return src
end

local function load_preview_for_video(path, max_size, key_prefix)
    if not path or not file_exists(path) then return nil end
    local key = (key_prefix or "vid") .. "|" .. path .. "|" .. tostring(max_size)
    local cached = App.State.preview_cache[key]
    if cached and file_exists(cached) then
        return cached
    end

    local out = unique_path(App.Config.temp_dir, key_prefix or "vidpreview", "png")
    local ok = false

    if has_cmd("ffmpeg") then
        local cmd = "ffmpeg -y -ss 0.2 -i " .. shell_quote(path)
            .. " -frames:v 1 -vf scale='min(" .. tostring(max_size or 800) .. ":iw):-2' "
            .. shell_quote(out) .. " >/dev/null 2>&1"
        ok = run_shell_ok(cmd) and file_exists(out)
    end

    if not ok and has_cmd("qlmanage") then
        local tmpdir = unique_path(App.Config.temp_dir, "ql", "dir")
        os.remove(tmpdir)
        mkdir_p(tmpdir)
        local cmd = "qlmanage -t -s " .. tostring(max_size or 800) .. " -o " .. shell_quote(tmpdir) .. " " .. shell_quote(path) .. " >/dev/null 2>&1"
        if run_shell_ok(cmd) then
            local cand = tmpdir .. "/" .. basename(path) .. ".png"
            if file_exists(cand) then
                local cp = "cp " .. shell_quote(cand) .. " " .. shell_quote(out)
                ok = run_shell_ok(cp) and file_exists(out)
            end
        end
    end

    if ok then
        App.State.preview_cache[key] = out
        return out
    end
    return nil
end

local function extract_video_last_frame(path)
    if not path or not file_exists(path) then return nil end
    if not has_cmd("ffmpeg") then return nil end
    local out = unique_path(App.Config.temp_dir, "vext_frame", "png")
    -- Seek 1 second from end and grab a single frame
    local cmd = "ffmpeg -y -sseof -1 -i " .. shell_quote(path)
        .. " -frames:v 1 " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd) and file_exists(out) then
        return out
    end
    -- Fallback: grab first frame if end-seek fails
    local cmd2 = "ffmpeg -y -i " .. shell_quote(path)
        .. " -frames:v 1 " .. shell_quote(out) .. " >/dev/null 2>&1"
    if run_shell_ok(cmd2) and file_exists(out) then
        return out
    end
    return nil
end

local function get_widget_size(widget)
    if not widget then return 0, 0 end
    local w, h = 0, 0

    pcall(function()
        local g = widget.Geometry
        if type(g) == "table" then
            w = tonumber(g[3]) or tonumber(g.Width) or tonumber(g.width) or w
            h = tonumber(g[4]) or tonumber(g.Height) or tonumber(g.height) or h
        end
    end)

    pcall(function()
        local _, _, gw, gh = widget:GetGeometry()
        if tonumber(gw) then w = tonumber(gw) end
        if tonumber(gh) then h = tonumber(gh) end
    end)

    pcall(function() w = tonumber(widget.Width) or w end)
    pcall(function() h = tonumber(widget.Height) or h end)

    return math.max(0, math.floor(w)), math.max(0, math.floor(h))
end

local function quantize_preview_size(px)
    local n = tonumber(px) or 0
    if n < 256 then n = 512 end
    local q = 128
    return math.floor((n + q - 1) / q) * q
end

local function purge_preview_cache_for_path(path)
    if not path or path == "" then return end
    local base = basename(path)
    for k, _ in pairs(App.State.preview_cache or {}) do
        if type(k) == "string" and k:find(base, 1, true) then
            App.State.preview_cache[k] = nil
        end
    end
end

local function set_button_square_style(btn, border_css, radius_px, max_icon_w, max_icon_h)
    if not btn then return end
    local w, h = get_widget_size(btn)
    local fallback_w = tonumber(max_icon_w) or 120
    local fallback_h = tonumber(max_icon_h) or 68
    local icon_w = (w > 8) and (w - 8) or fallback_w
    local icon_h = (h > 8) and (h - 8) or fallback_h
    if tonumber(max_icon_w) and icon_w > tonumber(max_icon_w) then
        icon_w = tonumber(max_icon_w)
    end
    if tonumber(max_icon_h) and icon_h > tonumber(max_icon_h) then
        icon_h = tonumber(max_icon_h)
    end
    if icon_w < 24 then icon_w = 24 end
    if icon_h < 24 then icon_h = 24 end
    local radius = tonumber(radius_px) or 0
    local css = "border-radius: " .. tostring(radius) .. "px; padding: 0px; margin: 0px;"
    if not border_css or border_css == "" then
        border_css = "border: 1px solid #5A607A;"
    end
    if border_css and border_css ~= "" then
        css = css .. border_css
    end
    css = css
        .. "icon-size: " .. tostring(icon_w) .. "px " .. tostring(icon_h) .. "px;"
        .. "qproperty-iconSize: " .. tostring(icon_w) .. "px " .. tostring(icon_h) .. "px;"
    pcall(function() btn.StyleSheet = css end)
    pcall(function() btn.IconSize = {icon_w, icon_h} end)
    pcall(function() btn.IconSize = {Width = icon_w, Height = icon_h} end)
    pcall(function() btn:SetIconSize({icon_w, icon_h}) end)
    pcall(function() btn:SetIconSize({Width = icon_w, Height = icon_h}) end)
end

local function clear_button_icon(btn)
    if not btn then return end
    pcall(function() btn.Icon = nil end)
    pcall(function() btn:SetIcon(nil) end)
    pcall(function() btn.IconSize = {0, 0} end)
    pcall(function() btn.IconSize = {Width = 0, Height = 0} end)
    pcall(function() btn:SetIconSize({0, 0}) end)
    pcall(function() btn:SetIconSize({Width = 0, Height = 0}) end)
end

local function set_button_empty_state(btn, label, supported)
    if not btn then return end
    clear_button_icon(btn)
    pcall(function() btn.Text = label or "" end)
    pcall(function() btn.ToolTip = "" end)
    local base_border = supported and "border: 1px solid #6B6F85;" or "border: 2px solid #AA3333;"
    local text_color = supported and "color: #8A92AE;" or "color: #C77575;"
    local css = "border-radius: 0px; padding: 0px; margin: 0px;"
        .. base_border
        .. " background-color: #1A1F2C; "
        .. text_color
        .. " text-align: center; icon-size: 0px 0px; qproperty-iconSize: 0px 0px;"
    pcall(function() btn.StyleSheet = css end)
end

local function set_control_square_style(ctrl, extra_css)
    if not ctrl then return end
    local css = "border-radius: 0px; border: 1px solid #5A607A; padding: 2px 6px;"
    if extra_css and extra_css ~= "" then
        css = css .. extra_css
    end
    pcall(function() ctrl.StyleSheet = css end)
end

local function set_scroll_macos_style(ctrl)
    if not ctrl then return end
    local css = [[
    QScrollBar:vertical {
        background: #191d29;
        width: 12px;
        margin: 2px 2px 2px 0px;
        border: 0px;
        border-radius: 6px;
    }
    QScrollBar::handle:vertical {
        background: #a7b8ff;
        min-height: 36px;
        border-radius: 6px;
    }
    QScrollBar::handle:vertical:hover {
        background: #c4d0ff;
    }
    QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
        height: 0px;
    }
    QSlider::groove:vertical {
        background: #191d29;
        width: 12px;
        border-radius: 6px;
        margin: 2px;
    }
    QSlider::handle:vertical {
        background: #a7b8ff;
        border: 0px;
        height: 32px;
        margin: -4px;
        border-radius: 10px;
    }
    QSpinBox {
        border: 1px solid #5A607A;
        border-radius: 6px;
        padding: 2px 6px;
        background: #191d29;
        color: #d6dcf0;
    }
    ]]
    pcall(function() ctrl.StyleSheet = css end)
end

local function style_action_button(btn, is_active)
    if not btn then return end
    local css
    if is_active then
        css = "border-radius: 0px; border: 2px solid #A7B3DB; background-color: #30384D; color: #EEF2FF; padding: 2px 8px;"
    else
        css = "border-radius: 0px; border: 1px solid #5A607A; background-color: #232734; color: #D3D8E6; padding: 2px 8px;"
    end
    pcall(function() btn.StyleSheet = css end)
end

local function refresh_tab_button_styles()
    local items = App.State.items
    if not items then return end
    style_action_button(items.tabImageBtn, App.State.current_tab == "image")
    style_action_button(items.tabMovieBtn, App.State.current_tab == "movie")
    style_action_button(items.tabConfigBtn, App.State.current_tab == "config")
end

local function set_button_image(btn, path, fallback_text, kind)
    if not btn then return end
    clear_button_icon(btn)

    local bw, bh = get_widget_size(btn)
    local target_preview = 0
    if bw > 0 and bh > 0 then
        target_preview = quantize_preview_size(math.max(bw, bh) * 2)
    end

    local preview = nil
    if path and path ~= "" and file_exists(path) then
        local max_size = target_preview
        if max_size <= 0 then
            if kind == "video" then
                max_size = App.Config.result_preview_max
            else
                max_size = App.Config.ref_preview_max
            end
        end
        if kind == "video" or path:lower():match("%.mp4$") or path:lower():match("%.mov$") then
            preview = load_preview_for_video(path, max_size, "vprev")
        else
            preview = load_preview_for_image(path, max_size, "iprev")
        end
    end

    local icon_set = false
    if preview and App.Core.ui then
        local ok, icon = pcall(function()
            return App.Core.ui:Icon({File = preview})
        end)
        if (not ok) or (not icon) then
            ok, icon = pcall(function()
                return App.Core.ui:Icon{File = preview}
            end)
        end
        if ok and icon then
            local ok_set = pcall(function()
                btn.Icon = icon
                btn.Text = ""
                btn.ToolTip = path or ""
            end)
            icon_set = ok_set
        end
    end

    if not icon_set then
        btn.Text = fallback_text or ""
        btn.ToolTip = path or ""
        clear_button_icon(btn)
    end
end

local function media_pool_clip_property(item, key)
    if not item or not key or key == "" then return "" end
    local value = nil
    local ok = pcall(function()
        value = item:GetClipProperty(key)
    end)
    if not ok then
        return ""
    end
    if type(value) == "table" then
        value = value[key]
    end
    return trim(value or "")
end

local function current_source_clip_info(timeline)
    local out = {
        source_path = "",
        source_name = "",
        timeline_item = nil,
        media_pool_item = nil
    }
    if not timeline then
        return out
    end

    local timeline_item = nil
    pcall(function()
        timeline_item = timeline:GetCurrentVideoItem()
    end)

    local media_pool_item = nil
    if timeline_item then
        pcall(function()
            media_pool_item = timeline_item:GetMediaPoolItem()
        end)
    end

    local source_path = media_pool_clip_property(media_pool_item, "File Path")
    local source_name = ""
    if source_path ~= "" then
        local _, stem = split_ext(source_path)
        source_name = stem or ""
    end

    if source_name == "" then
        source_name = media_pool_clip_property(media_pool_item, "Clip Name")
    end
    if source_name == "" and media_pool_item and media_pool_item.GetName then
        pcall(function()
            source_name = trim(media_pool_item:GetName() or "")
        end)
    end
    if source_name == "" and timeline_item and timeline_item.GetName then
        pcall(function()
            source_name = trim(timeline_item:GetName() or "")
        end)
    end

    out.source_path = source_path
    out.source_name = sanitize_token(source_name)
    out.timeline_item = timeline_item
    out.media_pool_item = media_pool_item
    return out
end

local function parse_numeric_frame(value)
    local txt = trim(value or "")
    if txt == "" then
        return nil
    end
    txt = txt:gsub(",", "")
    local num = tonumber(txt)
    if num == nil then
        return nil
    end
    return math.floor(num + 0.5)
end

local function parse_timecode_to_frames(tc, fps)
    tc = trim(tc or "")
    fps = tonumber(fps) or 0
    if tc == "" or fps <= 0 then
        return nil
    end

    local h, m, s, f = tc:match("^(%d+):(%d+):(%d+):(%d+)$")
    if not h then
        return nil
    end

    h = tonumber(h) or 0
    m = tonumber(m) or 0
    s = tonumber(s) or 0
    f = tonumber(f) or 0
    local fps_int = math.max(1, math.floor(fps + 0.5))
    return (((h * 60) + m) * 60 + s) * fps_int + f
end

local function get_timeline_frame_rate(project, timeline, media_pool_item)
    local candidates = {}

    if timeline and timeline.GetSetting then
        pcall(function()
            candidates[#candidates + 1] = timeline:GetSetting("timelineFrameRate")
        end)
        pcall(function()
            candidates[#candidates + 1] = timeline:GetSetting("timelinePlaybackFrameRate")
        end)
    end
    if project and project.GetSetting then
        pcall(function()
            candidates[#candidates + 1] = project:GetSetting("timelineFrameRate")
        end)
        pcall(function()
            candidates[#candidates + 1] = project:GetSetting("timelinePlaybackFrameRate")
        end)
    end
    if media_pool_item then
        candidates[#candidates + 1] = media_pool_clip_property(media_pool_item, "FPS")
    end

    for _, candidate in ipairs(candidates) do
        local fps = tonumber(trim(candidate or ""))
        if fps and fps > 0 then
            return fps
        end
    end
    return nil
end

local function get_current_timeline_frame(project, timeline, media_pool_item)
    if not timeline then
        return nil
    end

    local direct_frame = nil
    pcall(function()
        direct_frame = timeline:GetCurrentFrame()
    end)
    direct_frame = parse_numeric_frame(direct_frame)
    if direct_frame ~= nil then
        return direct_frame
    end

    local fps = get_timeline_frame_rate(project, timeline, media_pool_item)
    if not fps then
        return nil
    end

    local current_tc = ""
    local start_tc = ""
    local start_frame = nil
    pcall(function() current_tc = timeline:GetCurrentTimecode() or "" end)
    pcall(function() start_tc = timeline:GetStartTimecode() or "" end)
    pcall(function() start_frame = timeline:GetStartFrame() end)

    start_frame = parse_numeric_frame(start_frame) or 0
    local current_tc_frames = parse_timecode_to_frames(current_tc, fps)
    local start_tc_frames = parse_timecode_to_frames(start_tc, fps)
    if current_tc_frames == nil or start_tc_frames == nil then
        return nil
    end

    return start_frame + (current_tc_frames - start_tc_frames)
end

local function compute_source_frame_number(project, timeline, clip_info)
    if not timeline or not clip_info then
        return nil
    end

    local timeline_item = clip_info.timeline_item
    local media_pool_item = clip_info.media_pool_item
    if not timeline_item or not media_pool_item then
        return nil
    end

    local current_timeline_frame = get_current_timeline_frame(project, timeline, media_pool_item)
    local item_start = nil
    local left_offset = nil
    pcall(function() item_start = timeline_item:GetStart() end)
    pcall(function() left_offset = timeline_item:GetLeftOffset() end)

    item_start = parse_numeric_frame(item_start)
    left_offset = parse_numeric_frame(left_offset) or 0
    local source_start = parse_numeric_frame(media_pool_clip_property(media_pool_item, "Start"))

    if current_timeline_frame == nil or item_start == nil or source_start == nil then
        return nil
    end

    local clip_offset = current_timeline_frame - item_start
    if clip_offset < 0 then
        clip_offset = 0
    end

    return source_start + left_offset + clip_offset
end

local function get_current_timeline_meta()
    local out = {
        timeline = "",
        timecode = "",
        frame = "",
        source_path = "",
        source_name = "",
        source_frame = ""
    }
    local project, _ = resolve_project_and_pool()
    local timeline = project and project:GetCurrentTimeline()
    if timeline then
        local ok_name, tname = pcall(function() return timeline:GetName() end)
        if ok_name and tname then out.timeline = tostring(tname) end

        local ok_tc, tc = pcall(function() return timeline:GetCurrentTimecode() end)
        if ok_tc and tc then out.timecode = tostring(tc) end

        local clip_info = current_source_clip_info(timeline)
        out.source_path = clip_info.source_path or ""
        out.source_name = clip_info.source_name or ""

        local current_frame = get_current_timeline_frame(project, timeline, clip_info.media_pool_item)
        if current_frame ~= nil then
            out.frame = tostring(current_frame)
        end

        local source_frame = compute_source_frame_number(project, timeline, clip_info)
        if source_frame ~= nil then
            out.source_frame = tostring(source_frame)
        end
    end
    return out
end

local function build_grab_ref_path(meta)
    mkdir_p(App.Config.refs_dir)
    local source_name = sanitize_token((meta and meta.source_name) or "")
    if source_name == "" then
        source_name = "grab"
    end

    local frame = sanitize_token((meta and meta.source_frame) or "")
    if frame == "" then
        frame = sanitize_token((meta and meta.frame) or "")
    end
    local has_stable_frame = (frame ~= "")
    if frame == "" then
        frame = tostring(now_ms())
    end

    local base = project_prefix() .. "_" .. source_name .. "_" .. frame
    local path = App.Config.refs_dir .. base .. ".png"
    if has_stable_frame then
        return path, file_exists(path)
    end
    local idx = 1
    while file_exists(path) do
        path = App.Config.refs_dir .. base .. "_" .. tostring(idx) .. ".png"
        idx = idx + 1
    end
    return path, false
end

local function export_current_frame_png(path)
    local project, _ = resolve_project_and_pool()
    if not project then
        return false, "No active project."
    end

    local ok, ret = pcall(function()
        return project:ExportCurrentFrameAsStill(path)
    end)
    if not ok then
        return false, "ExportCurrentFrameAsStill call failed."
    end
    if not ret or not file_exists(path) then
        return false, "Resolve did not create still file."
    end
    return true, nil
end

local function lowest_empty_slot(slots, max_slots)
    for i = 1, max_slots do
        if not slots[i] or slots[i] == "" then
            return i
        end
    end
    return nil
end

local function set_widget_visible(widget, visible)
    if not widget then return end
    pcall(function() widget.Visible = visible end)
    pcall(function() widget.Hidden = not visible end)
    pcall(function() widget.Enabled = visible end)
    if visible then
        pcall(function() widget.MaximumSize = {16777215, 16777215} end)
    else
        -- Keep width unconstrained when hidden; collapsing width can clamp parent window resize.
        pcall(function() widget.MaximumSize = {16777215, 0} end)
    end
end

local function update_ref_grid_geometry(tab)
    local items = App.State.items
    if not items then return end

    local row1 = items[(tab == "movie") and "movieRefRow1" or "imgRefRow1"]
    if not row1 then return end

    local w, _ = get_widget_size(row1)
    w = tonumber(w) or 0
    local slot_w = math.max(80, math.floor((w - 6) / 2))
    local slot_h = math.floor((slot_w * 9) / 16)
    if slot_h < 60  then slot_h = 60  end
    if slot_h > 200 then slot_h = 200 end

    local prefix = (tab == "movie") and "movieRefBtn" or "imgRefBtn"
    for i = 1, 8 do
        local btn = items[prefix .. tostring(i)]
        if btn then
            pcall(function() btn.MinimumSize = {0, slot_h} end)
            pcall(function() btn.MaximumSize = {16777215, slot_h} end)
        end
    end
end

local function update_gallery_layout(tab)
    local items = App.State.items
    if not items then return end

    local list_group = items[(tab == "movie") and "movieGalleryListGroup" or "imgGalleryListGroup"]
    if not list_group then return end

    local _, list_h = get_widget_size(list_group)
    local min_thumb_h = 110
    local max_thumb_h = 180
    local max_buttons = App.State.gallery_button_count or 12
    local page_size = math.floor((math.max(0, list_h) + 4) / (min_thumb_h + 4))
    if page_size < 4 then page_size = 4 end
    if page_size > max_buttons then page_size = max_buttons end

    local thumb_h = math.floor((math.max(0, list_h) - ((page_size - 1) * 4)) / page_size)
    if thumb_h < min_thumb_h then thumb_h = min_thumb_h end
    if thumb_h > max_thumb_h then thumb_h = max_thumb_h end

    if tab == "movie" then
        App.State.movie_gallery_page_size = page_size
    else
        App.State.image_gallery_page_size = page_size
    end

    local prefix = (tab == "movie") and "movieGalleryBtn" or "imgGalleryBtn"
    for i = 1, max_buttons do
        local btn = items[prefix .. tostring(i)]
        if btn then
            local visible = i <= page_size
            set_widget_visible(btn, visible)
            if visible then
                pcall(function() btn.MinimumSize = {0, thumb_h} end)
                pcall(function() btn.MaximumSize = {16777215, thumb_h} end)
            end
        end
    end
end

local function refresh_slot_buttons()
    local items = App.State.items
    if not items then return end

    sanitize_ref_slots_for_limits()
    update_ref_grid_geometry("image")
    update_ref_grid_geometry("movie")

    local img_max = App.State.image_max_refs or 0

    for i = 1, 8 do
        local btn = items["imgRefBtn" .. tostring(i)]
        local p = App.State.image_refs[i]
        local supported = i <= (App.State.image_max_refs or 0)
        if supported and p and p ~= "" then
            set_button_image(btn, p, tostring(i), "image")
            set_button_square_style(btn, "border: 1px solid #6B6F85;", 0)
        else
            local label = supported and ("Empty " .. tostring(i)) or ("N/A " .. tostring(i))
            set_button_empty_state(btn, label, supported)
        end
    end

    local mov_max = App.State.movie_max_refs or 0

    for i = 1, 8 do
        local btn = items["movieRefBtn" .. tostring(i)]
        local p = App.State.movie_refs[i]
        local supported = i <= (App.State.movie_max_refs or 0)
        if supported and p and p ~= "" then
            set_button_image(btn, p, tostring(i), "image")
            set_button_square_style(btn, "border: 1px solid #6B6F85;", 0)
        else
            local label = get_movie_slot_label(i, supported)
            set_button_empty_state(btn, label, supported)
        end
    end

    local function set_token_button_state(btn, supported, has_ref, token)
        if not btn then return end
        pcall(function() btn.Text = token or "" end)
        -- Always keep token buttons visible so the row always has width.
        -- Hiding them (MaximumSize height=0) collapses the row to zero, which
        -- removes the layout's minimum-width anchor and locks the window narrow.
        pcall(function() btn.Visible = true  end)
        pcall(function() btn.Hidden  = false end)
        if not supported then
            -- Model doesn't support this slot at all — hide completely
            pcall(function() btn.Visible = false end)
            pcall(function() btn.Hidden  = true  end)
            pcall(function() btn.MaximumSize = {0, 0} end)
        elseif has_ref then
            -- Slot has a ref — bright/active
            pcall(function() btn.MaximumSize = {16777215, 16777215} end)
            pcall(function() btn.Enabled = true end)
            style_action_button(btn, false)
        else
            -- Slot supported but empty — show dimmed as placeholder
            pcall(function() btn.MaximumSize = {16777215, 16777215} end)
            pcall(function() btn.Enabled = false end)
            pcall(function() btn.StyleSheet = "border-radius: 0px; border: 1px solid #3A3F52; background-color: #1A1F2C; color: #4B5270; padding: 2px 8px;" end)
        end
    end

    local max_img = App.State.image_max_refs or 0
    local img_map = {
        items.imgToken1Btn, items.imgToken2Btn, items.imgToken3Btn, items.imgToken4Btn,
        items.imgToken5Btn, items.imgToken6Btn, items.imgToken7Btn, items.imgToken8Btn
    }
    for i = 1, 8 do
        local supported = i <= max_img
        local has_ref = supported and (App.State.image_refs[i] ~= nil and App.State.image_refs[i] ~= "")
        set_token_button_state(img_map[i], supported, has_ref, "@image" .. tostring(i))
    end

    local max_mov = App.State.movie_max_refs or 0
    local movie_token_map = {items.movieToken1Btn, items.movieToken2Btn, items.movieToken3Btn}
    for i = 1, 3 do
        set_token_button_state(movie_token_map[i], (max_mov >= i), (max_mov >= i) and (App.State.movie_refs[i] ~= nil and App.State.movie_refs[i] ~= ""), "@image" .. tostring(i))
    end

    if items.imgResultBtn then
        if App.State.image_generating then
            -- Show "Generating..." centered in the result frame itself, not just the hint label
            set_button_empty_state(items.imgResultBtn, "Generating...", true)
            if items.imgResultHintLabel then
                items.imgResultHintLabel.Text = ""
            end
        elseif App.State.last_image_path and file_exists(App.State.last_image_path) then
            set_button_image(items.imgResultBtn, App.State.last_image_path, "Result", "image")
            set_button_square_style(items.imgResultBtn, "border: 1px solid #6B6F85;")
            if items.imgResultHintLabel then
                items.imgResultHintLabel.Text = "Click to view"
            end
        else
            set_button_empty_state(items.imgResultBtn, "Result", true)
            if items.imgResultHintLabel then
                items.imgResultHintLabel.Text = "No result yet"
            end
        end
    end

    if items.movieResultBtn then
        if App.State.movie_generating then
            set_button_empty_state(items.movieResultBtn, "Generating...", true)
            if items.movieResultHintLabel then
                items.movieResultHintLabel.Text = ""
            end
        elseif App.State.last_movie_path and file_exists(App.State.last_movie_path) then
            local poster = load_preview_for_video(App.State.last_movie_path, App.Config.result_preview_max, "movie_result")
            set_button_image(items.movieResultBtn, poster or App.State.last_movie_path, "Video Ready", "video")
            set_button_square_style(items.movieResultBtn, "border: 1px solid #6B6F85;")
            if items.movieResultHintLabel then
                items.movieResultHintLabel.Text = "Click to view"
            end
        else
            set_button_empty_state(items.movieResultBtn, "Result", true)
            if items.movieResultHintLabel then
                items.movieResultHintLabel.Text = "No result yet"
            end
        end
    end
end

local function set_image_status(msg)
    local items = App.State.items
    if items and items.imgStatusBox then
        items.imgStatusBox.PlainText = tostring(msg or "")
    end
    log(msg)
end

local function set_movie_status(msg)
    local items = App.State.items
    if items and items.movieStatusBox then
        items.movieStatusBox.PlainText = tostring(msg or "")
    end
    log(msg)
end

local function set_config_status(msg)
    local items = App.State.items
    if items and items.cfgStatusBox then
        items.cfgStatusBox.Text = tostring(msg or "")
    end
    log(msg)
end

local function refresh_image_capabilities_label()
    local items = App.State.items
    if not items or not items.imgCapsLabel then return end

    local model = App.Config.image_model
    local caps = get_image_caps(model)

    App.State.image_max_refs = caps.max_refs or 4
    sanitize_ref_slots_for_limits()
    local aspects = table.concat(caps.aspects or {}, ",")
    local sizes = table.concat(caps.sizes or {}, ",")
    items.imgCapsLabel.Text = "Capabilities: refs up to " .. tostring(App.State.image_max_refs) .. " | aspect: " .. aspects .. " | size: " .. sizes
end

local function refresh_movie_capabilities_label()
    local items = App.State.items
    if not items or not items.movieCapsLabel then return end

    local model = App.Config.movie_model
    local caps = get_movie_caps(model)
    local ref_mode = get_effective_movie_ref_mode(caps)

    App.State.movie_max_refs = get_effective_movie_ref_limit(caps)
    sanitize_ref_slots_for_limits()
    local parts = {}
    parts[#parts + 1] = "Capabilities: refs up to " .. tostring(App.State.movie_max_refs)
    parts[#parts + 1] = "aspect: " .. table.concat(caps.aspects or {}, ",")
    parts[#parts + 1] = "resolution: " .. table.concat(caps.resolutions or {}, ",")
    parts[#parts + 1] = "duration: " .. table.concat(caps.durations or {}, ",")
    if caps.supports_last_frame then
        parts[#parts + 1] = "frames: slot1=first | slot2=last"
    else
        parts[#parts + 1] = "frames: slot1=first"
    end
    if caps.supports_reference_images then
        parts[#parts + 1] = "ingredients: up to " .. tostring(caps.reference_image_max_refs or 3) .. " refs"
        parts[#parts + 1] = "ingredient rules: 16:9, 8s"
    end
    parts[#parts + 1] = "active mode: " .. movie_ref_mode_display(ref_mode)
    items.movieCapsLabel.Text = table.concat(parts, " | ")
end

local function sync_controls_from_config()
    local items = App.State.items
    if not items then return end

    items.cfgGeminiUrlEdit.Text = App.Config.gemini_api_url
    items.cfgGeminiKeyEdit.Text = App.Config.gemini_api_key
    items.cfgSaveDirEdit.Text = App.Config.output_dir
    items.cfgPoolDirEdit.Text = App.Config.media_pool_dir
end

local function apply_config_from_controls()
    local items = App.State.items
    if not items then return end

    App.Config.gemini_api_url = trim(items.cfgGeminiUrlEdit.Text or App.Config.gemini_api_url)
    App.Config.gemini_api_key = trim(items.cfgGeminiKeyEdit.Text or App.Config.gemini_api_key)

    local out = trim(items.cfgSaveDirEdit.Text or "")
    if out ~= "" then
        if out:sub(-1) ~= "/" then out = out .. "/" end
        App.Config.output_dir = out
    end

    local pool = trim(items.cfgPoolDirEdit.Text or "")
    if pool ~= "" and pool:sub(-1) ~= "/" then
        pool = pool .. "/"
    end
    App.Config.media_pool_dir = pool
end

local function test_gemini_key()
    local url = trim(App.Config.gemini_api_url)
    if url == "" then
        return false, "Gemini API URL is required."
    end
    if trim(App.Config.gemini_api_key) == "" then
        return false, "Gemini API key is required."
    end

    local req = url .. "/models?key=" .. urlencode(App.Config.gemini_api_key)
    local status, body, err = curl_get(req, nil, 60)
    if status >= 200 and status < 300 then
        return true, "Gemini key test passed."
    end
    local msg = parse_http_error_message(body, status)
    if trim(msg) == "" then msg = trim(err) end
    return false, "Gemini key test failed: HTTP " .. tostring(status) .. "\n" .. msg
end

local function fetch_gemini_models()
    local key = trim(App.Config.gemini_api_key)
    if key == "" then
        return false, "Gemini API key is required to refresh models."
    end
    local req = trim(App.Config.gemini_api_url) .. "/models?key=" .. urlencode(key)
    local status, body, err = curl_get(req, nil, 90)
    if status < 200 or status >= 300 then
        local msg = parse_http_error_message(body, status)
        if trim(msg) == "" then msg = trim(err) end
        return false, "HTTP " .. tostring(status) .. ". " .. msg
    end

    local image_models = {}
    local movie_models = {}
    local seen_movie = {}
    local seen_image = {}

    for name in body:gmatch('"name"%s*:%s*"models/([^"]+)"') do
        local lower = name:lower()
        if lower:find("veo", 1, true) then
            if not seen_movie[name] then
                movie_models[#movie_models + 1] = name
                seen_movie[name] = true
            end
        elseif lower:find("image", 1, true) then
            if is_supported_image_model(name) and not seen_image[name] then
                image_models[#image_models + 1] = name
                seen_image[name] = true
            elseif not is_supported_image_model(name) then
                log("Skipping unsupported image model: " .. tostring(name))
            end
        end
    end

    image_models = filter_supported_image_models(image_models)
    if #movie_models == 0 then
        movie_models = DEFAULT_MOVIE_MODELS
    end

    App.State.image_models = image_models
    App.State.movie_models = movie_models
    return true, "Gemini models refreshed."
end

local function refresh_model_combos()
    local items = App.State.items
    if not items then return end
    if App.State.ui_updating or App.State.ui_refreshing then return end
    App.State.ui_refreshing = true
    App.State.ui_updating = true

    local ok, err = pcall(function()
        App.State.image_models = filter_supported_image_models(App.State.image_models)
        if #App.State.movie_models == 0 then
            App.State.movie_models = DEFAULT_MOVIE_MODELS
        end
        local img_display = {}
        for _, m in ipairs(App.State.image_models) do
            img_display[#img_display + 1] = image_model_display(m)
        end
        App.Config.image_model = display_to_model(App.Config.image_model)
        if not is_supported_image_model(App.Config.image_model) then
            App.Config.image_model = App.State.image_models[1]
        end
        combo_set_items(items.imgModelCombo, img_display, image_model_display(App.Config.image_model))
        App.Config.image_model = display_to_model(combo_current_text(items.imgModelCombo))
        if not is_supported_image_model(App.Config.image_model) then
            App.Config.image_model = App.State.image_models[1]
            combo_set_items(items.imgModelCombo, img_display, image_model_display(App.Config.image_model))
        end

        local movie_display = {}
        for _, m in ipairs(App.State.movie_models) do
            movie_display[#movie_display + 1] = movie_model_display(m)
        end
        App.Config.movie_model = display_to_model(App.Config.movie_model)
        combo_set_items(items.movieModelCombo, movie_display, movie_model_display(App.Config.movie_model))
        App.Config.movie_model = display_to_model(combo_current_text(items.movieModelCombo))

        local image_caps = get_image_caps(App.Config.image_model)
        local movie_caps = get_movie_caps(App.Config.movie_model)
        local movie_ref_mode_options = {movie_ref_mode_display("frames")}
        if movie_caps.supports_reference_images then
            movie_ref_mode_options[#movie_ref_mode_options + 1] = movie_ref_mode_display("ingredients")
        end
        App.Config.movie_ref_mode = get_effective_movie_ref_mode(movie_caps)
        combo_set_items(items.movieRefModeCombo, movie_ref_mode_options, movie_ref_mode_display(App.Config.movie_ref_mode))
        App.Config.movie_ref_mode = movie_ref_mode_from_text(combo_current_text(items.movieRefModeCombo))
        App.Config.movie_ref_mode = get_effective_movie_ref_mode(movie_caps)

        combo_set_items(items.imgAspectCombo, image_caps.aspects or {"16:9"}, App.Config.image_aspect_ratio)
        App.Config.image_aspect_ratio = combo_current_text(items.imgAspectCombo)
        if App.Config.image_aspect_ratio == "" then App.Config.image_aspect_ratio = (image_caps.aspects or {"16:9"})[1] or "16:9" end

        combo_set_items(items.imgSizeCombo, image_caps.sizes or {"1K"}, App.Config.image_size)
        App.Config.image_size = combo_current_text(items.imgSizeCombo)
        if App.Config.image_size == "" then App.Config.image_size = (image_caps.sizes or {"1K"})[1] or "1K" end

        local movie_aspects = movie_caps.aspects or {"16:9"}
        local movie_durations = movie_caps.durations or {"8"}
        if App.Config.movie_ref_mode == "ingredients" and movie_caps.supports_reference_images then
            movie_aspects = {"16:9"}
            movie_durations = {"8"}
        end

        combo_set_items(items.movieAspectCombo, movie_aspects, App.Config.movie_aspect_ratio)
        App.Config.movie_aspect_ratio = combo_current_text(items.movieAspectCombo)
        if App.Config.movie_aspect_ratio == "" then App.Config.movie_aspect_ratio = movie_aspects[1] or "16:9" end

        combo_set_items(items.movieResolutionCombo, movie_caps.resolutions or {"720p"}, App.Config.movie_resolution)
        App.Config.movie_resolution = combo_current_text(items.movieResolutionCombo)
        if App.Config.movie_resolution == "" then App.Config.movie_resolution = (movie_caps.resolutions or {"720p"})[1] or "720p" end

        combo_set_items(items.movieDurationCombo, movie_durations, App.Config.movie_duration)
        App.Config.movie_duration = combo_current_text(items.movieDurationCombo)
        if App.Config.movie_duration == "" then App.Config.movie_duration = movie_durations[1] or "8" end

        refresh_image_capabilities_label()
        refresh_movie_capabilities_label()
        refresh_slot_buttons()
    end)
    App.State.ui_updating = false
    App.State.ui_refreshing = false
    if not ok then
        log("refresh_model_combos failed: " .. tostring(err))
    end
end

local function is_video_file(path)
    local lower = (path or ""):lower()
    return lower:match("%.mp4$") or lower:match("%.mov$") or lower:match("%.webm$") or lower:match("%.mkv$") ~= nil
end

local function fill_ref_slot(tab, path, meta)
    if tab == "movie" then
        if is_video_file(path) then
            return nil, "Video files cannot be used as references. Use 'Extend Movie' to continue from a generated video."
        end
        local max_slots = App.State.movie_max_refs or 2
        local idx = lowest_empty_slot(App.State.movie_refs, max_slots) or 1
        App.State.movie_refs[idx] = path
        App.State.movie_ref_meta[idx] = meta or {}
        return idx
    end

    local max_slots = App.State.image_max_refs or 8
    local idx = lowest_empty_slot(App.State.image_refs, max_slots) or 1
    App.State.image_refs[idx] = path
    App.State.image_ref_meta[idx] = meta or {}
    return idx
end

local function clear_ref_slot(tab, idx)
    local removed
    if tab == "movie" then
        removed = App.State.movie_refs[idx]
        App.State.movie_refs[idx] = nil
        App.State.movie_ref_meta[idx] = nil
    else
        removed = App.State.image_refs[idx]
        App.State.image_refs[idx] = nil
        App.State.image_ref_meta[idx] = nil
    end
    -- Record for undo
    if removed and removed ~= "" then
        App.State.last_cleared_ref = {tab = tab, idx = idx, path = removed}
    end
    purge_preview_cache_for_path(removed)
    return removed
end

sanitize_ref_slots_for_limits = function()
    local img_max = math.max(0, tonumber(App.State.image_max_refs) or 0)
    for i = img_max + 1, 8 do
        clear_ref_slot("image", i)
    end

    local mov_max = math.max(0, tonumber(App.State.movie_max_refs) or 0)
    for i = mov_max + 1, 8 do
        clear_ref_slot("movie", i)
    end
end

local function clear_all_refs(tab)
    if tab == "movie" then
        for i = 1, 8 do
            clear_ref_slot("movie", i)
        end
    else
        for i = 1, 8 do
            clear_ref_slot("image", i)
        end
    end
end

local function grab_current_frame_into(tab)
    mkdir_p(App.Config.refs_dir)
    local meta = get_current_timeline_meta()
    if trim(meta.source_frame or "") == "" then
        log("Grab naming fallback: source frame unavailable; using timeline frame or timestamp.")
    end
    local out, already_exists = build_grab_ref_path(meta)
    if not already_exists then
        local ok, err = export_current_frame_png(out)
        if not ok then
            return false, err
        end
    end

    local idx = fill_ref_slot(tab, out, meta)
    add_history("ref", out)
    refresh_gallery_ui()
    refresh_slot_buttons()
    if already_exists then
        return true, "Reused grabbed frame in slot " .. tostring(idx) .. ": " .. basename(out)
    end
    return true, "Grabbed frame into slot " .. tostring(idx) .. ": " .. basename(out)
end

local function paste_clipboard_image_png(out_path)
    if not out_path or out_path == "" then
        return false, "Output path missing."
    end

    if has_cmd("pngpaste") then
        local cmd = "pngpaste " .. shell_quote(out_path) .. " >/dev/null 2>&1"
        if run_shell_ok(cmd) and file_exists(out_path) then
            return true, nil
        end
    end

    if has_cmd("osascript") then
        local script_path = unique_path(App.Config.temp_dir, "clip_img", "applescript")
        local script = [[
on run argv
    set outPath to item 1 of argv
    set outFile to POSIX file outPath
    set clipData to missing value
    try
        set clipData to (the clipboard as «class PNGf»)
    on error
        error "Clipboard does not contain PNG image data."
    end try
    set f to open for access outFile with write permission
    try
        set eof of f to 0
        write clipData to f
        close access f
    on error errMsg number errNum
        try
            close access f
        end try
        error errMsg number errNum
    end try
end run
]]
        write_file(script_path, script, "wb")
        local cmd = "osascript " .. shell_quote(script_path) .. " " .. shell_quote(out_path) .. " >/dev/null 2>&1"
        local ok = run_shell_ok(cmd) and file_exists(out_path)
        os.remove(script_path)
        if ok then
            return true, nil
        end
    end

    return false, "Clipboard image paste unavailable. Install `pngpaste` or copy an image with PNG data."
end

local function paste_clipboard_into(tab)
    mkdir_p(App.Config.refs_dir)
    local out = build_ref_path("paste", "png")
    local ok_paste, err_paste = paste_clipboard_image_png(out)
    if not ok_paste or not file_exists(out) then
        return false, err_paste or "Clipboard does not contain an image."
    end

    local idx = fill_ref_slot(tab, out, {timeline = "Clipboard", timecode = "", frame = ""})
    add_history("ref", out)
    refresh_gallery_ui()
    refresh_slot_buttons()
    return true, "Pasted image into slot " .. tostring(idx)
end

local function current_image_refs()
    local out = {}
    for i = 1, (App.State.image_max_refs or 8) do
        local p = App.State.image_refs[i]
        if p and p ~= "" and file_exists(p) then
            out[#out + 1] = p
        end
    end
    return out
end

local function current_movie_refs()
    local out = {}
    for i = 1, (App.State.movie_max_refs or 2) do
        local p = App.State.movie_refs[i]
        if p and p ~= "" and file_exists(p) then
            out[#out + 1] = p
        end
    end
    return out
end

local function generate_image_gemini(prompt, refs)
    local url = trim(App.Config.gemini_api_url)
    local key = trim(App.Config.gemini_api_key)
    local model = trim(App.Config.image_model)

    if key == "" then return false, "Gemini API key is required." end
    if url == "" then return false, "Gemini API URL is required." end
    if model == "" then return false, "Image model is required." end

    local parts = {}
    parts[#parts + 1] = '{"text":"' .. json_escape(prompt) .. '"}'

    for _, p in ipairs(refs or {}) do
        local png = ensure_png(p)
        local b64 = encode_file_base64(png)
        if b64 and b64 ~= "" then
            local mime = image_mime_from_ext(png)
            parts[#parts + 1] = '{"inlineData":{"mimeType":"' .. mime .. '","data":"' .. b64 .. '"}}'
        end
    end

    local payload = "{"
        .. '"contents":[{"role":"user","parts":[' .. table.concat(parts, ",") .. ']}],'
        .. '"safetySettings":['
        .. '{"category":"HARM_CATEGORY_HARASSMENT","threshold":"BLOCK_NONE"},'
        .. '{"category":"HARM_CATEGORY_HATE_SPEECH","threshold":"BLOCK_NONE"},'
        .. '{"category":"HARM_CATEGORY_SEXUALLY_EXPLICIT","threshold":"BLOCK_NONE"},'
        .. '{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","threshold":"BLOCK_NONE"}'
        .. '],'
        .. '"generationConfig":{'
        .. '"responseModalities":["TEXT","IMAGE"],'
        .. '"imageConfig":{'
        .. '"aspectRatio":"' .. json_escape(App.Config.image_aspect_ratio) .. '"'
        .. '}'
        .. '}'
        .. "}"

    local payload_path = unique_path(App.Config.temp_dir, "img_payload", "json")
    write_file(payload_path, payload, "wb")

    local req = url .. "/models/" .. model .. ":generateContent?key=" .. urlencode(key)
        local ok_req, status, body, err = curl_config_request(req, {["Content-Type"] = "application/json"}, payload_path, App.Config.max_http_seconds)
    log("[cURL stats] " .. tostring(status) .. " size=" .. tostring(#(body or "")))

    if not ok_req then
        return false, "Network error — could not reach the Gemini API. Check your internet connection.\nDetail: " .. tostring(err)
    end
    if status < 200 or status >= 300 then
        return false, "HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body, status)
    end

    local mime, data = parse_image_from_response(body)
    if not data then
        return false, "No image payload found in response."
    end

    local out_png = build_output_path("image", "png")
    if mime == "url" then
        local tmp = unique_path(App.Config.temp_dir, "img_dl", "bin")
        if not download_file(data, nil, tmp) then
            return false, "Image URL returned but download failed."
        end
        local png = ensure_png(tmp)
        if png ~= out_png then
            run_shell_ok("cp " .. shell_quote(png) .. " " .. shell_quote(out_png))
        end
    else
        local tmp = unique_path(App.Config.temp_dir, "img_dec", "bin")
        if not decode_base64_to_file(data, tmp) then
            return false, "Failed decoding image payload."
        end
        local png = ensure_png(tmp)
        if png ~= out_png then
            run_shell_ok("cp " .. shell_quote(png) .. " " .. shell_quote(out_png))
        else
            run_shell_ok("mv " .. shell_quote(tmp) .. " " .. shell_quote(out_png))
        end
    end

    if not file_exists(out_png) then
        return false, "Generation completed but output file was not saved."
    end

    local sidecar = write_generation_sidecar(out_png, {
        provider = "gemini",
        model = model,
        kind = "image",
        prompt = prompt,
        aspect_ratio = App.Config.image_aspect_ratio,
        size_or_resolution = App.Config.image_size,
        refs = refs
    })
    add_history("image_gen", out_png, sidecar)

    return true, out_png
end

local function image_blob_json(path, mode)
    local img = ensure_png(path)
    local b64 = encode_file_base64(img)
    if not b64 then return nil end
    local mime = image_mime_from_ext(img)
    local m = mode or "bytesBase64Encoded"
    if m == "imageBytes" then
        return '{"imageBytes":"' .. b64 .. '","mimeType":"' .. mime .. '"}'
    end
    return '{"bytesBase64Encoded":"' .. b64 .. '","mimeType":"' .. mime .. '"}'
end

local function build_veo_payload(prompt, refs, caps, mode, use_last_frame, use_reference_images, person_generation_mode)
    local instance_parts = {'"prompt":"' .. json_escape(prompt) .. '"'}
    local params_parts = {}

    if use_reference_images and #refs > 0 then
        local arr = {}
        local max_ref_imgs = math.min(#refs, tonumber(caps.reference_image_max_refs) or 3)
        for i = 1, max_ref_imgs do
            local ref_path = refs[i]
            local lower = (ref_path or ""):lower()
            if lower:match("%.mp4$") or lower:match("%.mov$") or lower:match("%.webm$") then
                ref_path = extract_video_last_frame(ref_path) or ref_path
            end
            local blob = image_blob_json(ref_path, mode)
            if blob then
                arr[#arr + 1] = '{"referenceType":"asset","image":' .. blob .. '}'
            end
        end
        if #arr > 0 then
            instance_parts[#instance_parts + 1] = '"referenceImages":[' .. table.concat(arr, ",") .. ']'
        end
    else
        local first = refs[1]
        if first and file_exists(first) then
            local blob = image_blob_json(first, mode)
            if blob then
                instance_parts[#instance_parts + 1] = '"image":' .. blob
            end
        end

        if use_last_frame and refs[2] and file_exists(refs[2]) then
            local blob2 = image_blob_json(refs[2], mode)
            if blob2 then
                -- Veo expects lastFrame at instance level, not parameters.
                instance_parts[#instance_parts + 1] = '"lastFrame":' .. blob2
            end
        end
    end

    if App.Config.movie_aspect_ratio ~= "" then
        params_parts[#params_parts + 1] = '"aspectRatio":"' .. json_escape(App.Config.movie_aspect_ratio) .. '"'
    end
    if App.Config.movie_resolution ~= "" then
        params_parts[#params_parts + 1] = '"resolution":"' .. json_escape(App.Config.movie_resolution) .. '"'
    end
    if App.Config.movie_duration ~= "" then
        params_parts[#params_parts + 1] = '"durationSeconds":' .. tostring(tonumber(App.Config.movie_duration) or 8)
    end
    if trim(App.Config.movie_negative_prompt) ~= "" then
        params_parts[#params_parts + 1] = '"negativePrompt":"' .. json_escape(App.Config.movie_negative_prompt) .. '"'
    end

    if person_generation_mode and trim(person_generation_mode) ~= "" then
        params_parts[#params_parts + 1] = '"personGeneration":"' .. json_escape(person_generation_mode) .. '"'
    end

    local payload = "{"
        .. '"instances":[{' .. table.concat(instance_parts, ",") .. '}],'
        .. '"parameters":{' .. table.concat(params_parts, ",") .. '}'
        .. "}"

    return payload
end

local function start_veo_operation(payload)
    local model = trim(App.Config.movie_model)
    local req = trim(App.Config.gemini_api_url) .. "/models/" .. model .. ":predictLongRunning?key=" .. urlencode(App.Config.gemini_api_key)

    local payload_path = unique_path(App.Config.temp_dir, "veo_payload", "json")
    write_file(payload_path, payload, "wb")
    pcall(function()
        mkdir_p(App.Config.debug_dir)
        write_file(App.Config.debug_dir .. "veo_payload_last.json", payload, "wb")
    end)

    local ok_req, status, body, err = curl_config_request(req, {"Content-Type: application/json"}, payload_path, App.Config.max_http_seconds)
    log("[cURL stats] " .. tostring(status) .. " size=" .. tostring(#(body or "")))

    if not ok_req then
        return false, nil, "Network error — could not reach the Veo API. Check your internet connection.\nDetail: " .. tostring(err)
    end
    if status < 200 or status >= 300 then
        pcall(function()
            mkdir_p(App.Config.debug_dir)
            write_file(App.Config.debug_dir .. "veo_start_last.json", body or "", "wb")
        end)
        return false, nil, "HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body, status)
    end

    local op = body:match('"name"%s*:%s*"([^"]+)"')
    if not op or op == "" then
        return false, nil, "Veo start did not return operation name: " .. trim(body)
    end

    return true, op, body
end

local function poll_veo_operation(op_name)
    local start_ts = os.time()
    local poll_url = trim(App.Config.gemini_api_url) .. "/" .. op_name .. "?key=" .. urlencode(App.Config.gemini_api_key)

    while os.difftime(os.time(), start_ts) < App.Config.max_poll_seconds do
        local status, body, err = curl_get(poll_url, nil, 90)
        if status < 200 or status >= 300 then
            return false, "Poll failed: HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body ~= "" and body or err, status)
        end

        pcall(function()
            mkdir_p(App.Config.debug_dir)
            write_file(App.Config.debug_dir .. "veo_poll_last.json", body, "wb")
        end)

        local done = body:match('"done"%s*:%s*true') ~= nil
        if done then
            local err_msg = body:match('"error"%s*:%s*%{.-"message"%s*:%s*"([^"]+)"')
            if err_msg and err_msg ~= "" then
                return false, err_msg
            end

            local filtered = tonumber(body:match('"raiMediaFilteredCount"%s*:%s*(%d+)') or "0") or 0
            if filtered > 0 then
                local reason = body:match('"raiMediaFilteredReasons"%s*:%s*%[%s*"([^"]+)"') or "Safety filters blocked the result."
                return false, "Blocked by safety filter: " .. tostring(reason)
            end

            local uri = body:match('"video"%s*:%s*%{[^}]-"uri"%s*:%s*"([^"]+)"')
            if not uri then
                uri = body:match('"uri"%s*:%s*"([^"]+googleapis[^"]+)"')
            end
            if not uri then
                return false, "Veo operation completed but no video URI was returned."
            end
            return true, uri
        end

        os.execute("sleep 5")
    end

    return false, "Timed out waiting for Veo operation."
end

local function generate_movie_extension_gemini(prompt, video_uri)
    local key = trim(App.Config.gemini_api_key)
    if key == "" then return false, "Gemini API key is required." end

    local model = trim(App.Config.movie_model)
    if model == "" then return false, "Movie model is required." end

    -- Native Veo extension: pass the video URI directly; resolution locked to 720p
    local instance_parts = {'"prompt":"' .. json_escape(prompt) .. '"'}
    instance_parts[#instance_parts + 1] = '"video":{"uri":"' .. json_escape(video_uri) .. '"}'

    local params_parts = {'"resolution":"720p"'}

    local payload = "{"
        .. '"instances":[{' .. table.concat(instance_parts, ",") .. '}],'
        .. '"parameters":{' .. table.concat(params_parts, ",") .. '}'
        .. "}"

    local ok, op_name, body_or_err = start_veo_operation(payload)
    if not ok then
        return false, "Veo extension failed: " .. tostring(body_or_err)
    end

    set_movie_status("Movie extension started. Polling...")
    local ok_poll, uri_or_err = poll_veo_operation(op_name)
    if not ok_poll then
        return false, tostring(uri_or_err)
    end

    local new_uri = uri_or_err
    App.State.last_movie_uri = new_uri

    local out_mp4 = build_output_path("movie", "mp4")
    local ok_dl = download_file(new_uri, {"x-goog-api-key: " .. key}, out_mp4)
    if not ok_dl then
        return false, "Extension video URI returned but download failed."
    end
    if not file_exists(out_mp4) then
        return false, "Extension download reported success but file missing."
    end

    local sidecar = write_generation_sidecar(out_mp4, {
        provider = "gemini",
        model = model,
        kind = "movie",
        ref_mode = "extend",
        prompt = prompt,
        aspect_ratio = App.Config.movie_aspect_ratio,
        size_or_resolution = "720p",
        video_uri = new_uri
    })
    add_history("video_gen", out_mp4, sidecar)

    return true, out_mp4
end

local function generate_movie_gemini(prompt, refs)
    local key = trim(App.Config.gemini_api_key)
    if key == "" then return false, "Gemini API key is required." end

    local model = trim(App.Config.movie_model)
    if model == "" then return false, "Movie model is required." end

    local caps = get_movie_caps(model)
    local mode = "bytesBase64Encoded"
    local ref_mode = get_effective_movie_ref_mode(caps)
    local use_refs = (ref_mode == "ingredients") and caps.supports_reference_images
    if use_refs and #refs > (caps.reference_image_max_refs or 3) then
        local trimmed = {}
        for i = 1, (caps.reference_image_max_refs or 3) do
            trimmed[#trimmed + 1] = refs[i]
        end
        refs = trimmed
    end
    if use_refs then
        App.Config.movie_aspect_ratio = "16:9"
        App.Config.movie_duration = "8"
    end
    local use_last = (not use_refs) and caps.supports_last_frame and refs[2] ~= nil
    local person_mode = ((use_refs and #refs > 0) or ((not use_refs) and #refs > 0)) and "allow_adult" or "allow_all"

    local tries = 0
    local op_name = nil
    local last_err = ""

    while tries < 6 do
        tries = tries + 1
        local payload = build_veo_payload(prompt, refs, caps, mode, use_last, use_refs, person_mode)
        local ok, op_or_nil, body_or_err = start_veo_operation(payload)
        if ok then
            op_name = op_or_nil
            break
        end

        local msg = tostring(body_or_err or "")
        last_err = msg

        if msg:find("`inlineData`", 1, true) then
            mode = "bytesBase64Encoded"
            log("Veo fallback: retrying with image blob format `bytesBase64Encoded` (inlineData unsupported)")
        elseif msg:find("`imageBytes`", 1, true) or msg:find("`bytesBase64Encoded`", 1, true) then
            mode = (mode == "bytesBase64Encoded") and "imageBytes" or "bytesBase64Encoded"
            log("Veo fallback: retrying with image blob format `" .. mode .. "`")
        elseif msg:find("`lastFrame`", 1, true) then
            use_last = false
            log("Veo fallback: `lastFrame` unsupported; retrying without it.")
        elseif msg:find("`referenceImages`", 1, true) then
            use_refs = false
            log("Veo fallback: retrying without unsupported field `referenceImages`")
        elseif msg:find("allow_all for personGeneration is currently not supported", 1, true) then
            person_mode = "allow_adult"
            log("Veo fallback: retrying with `personGeneration=allow_adult`")
        elseif msg:find("`personGeneration`", 1, true) and msg:find("unsupported", 1, true) then
            person_mode = nil
            log("Veo fallback: retrying without unsupported field `personGeneration`")
        elseif msg:find("for `resolution` is invalid", 1, true) then
            local first_res = (caps.resolutions and caps.resolutions[1]) or "720p"
            if App.Config.movie_resolution ~= first_res then
                App.Config.movie_resolution = first_res
                log("Veo fallback: retrying with resolution `" .. tostring(first_res) .. "`")
            else
                break
            end
        elseif msg:find("for `durationSeconds` is invalid", 1, true) then
            local first_dur = (caps.durations and caps.durations[1]) or "8"
            if App.Config.movie_duration ~= first_dur then
                App.Config.movie_duration = first_dur
                log("Veo fallback: retrying with duration `" .. tostring(first_dur) .. "`")
            else
                break
            end
        else
            break
        end
    end

    if not op_name then
        return false, "Veo start failed: " .. tostring(last_err)
    end

    set_movie_status("Movie generation started. Polling...")
    local ok_poll, uri_or_err = poll_veo_operation(op_name)
    if not ok_poll then
        return false, tostring(uri_or_err)
    end

    local video_uri = uri_or_err
    App.State.last_movie_uri = video_uri

    local out_mp4 = build_output_path("movie", "mp4")
    local ok_dl = download_file(video_uri, {"x-goog-api-key: " .. key}, out_mp4)
    if not ok_dl then
        return false, "Video URI returned but download failed."
    end

    if not file_exists(out_mp4) then
        return false, "Video download reported success but file missing."
    end

    local sidecar = write_generation_sidecar(out_mp4, {
        provider = "gemini",
        model = model,
        kind = "movie",
        ref_mode = App.Config.movie_ref_mode,
        prompt = prompt,
        negative_prompt = App.Config.movie_negative_prompt,
        aspect_ratio = App.Config.movie_aspect_ratio,
        size_or_resolution = App.Config.movie_resolution,
        duration = App.Config.movie_duration,
        refs = refs,
        video_uri = video_uri
    })
    add_history("video_gen", out_mp4, sidecar)

    return true, out_mp4
end

local function refresh_gallery_buttons(tab)
    local items = App.State.items
    if not items then return end
    update_gallery_layout(tab)

    local list = (tab == "movie") and App.State.movie_gallery_list or App.State.image_gallery_list
    local pos_label = items[(tab == "movie") and "movieGalleryScrollPosLabel" or "imgGalleryScrollPosLabel"]
    local up_btn   = items[(tab == "movie") and "movieGalleryScrollUp" or "imgGalleryScrollUp"]
    local dn_btn   = items[(tab == "movie") and "movieGalleryScrollDn" or "imgGalleryScrollDn"]
    local sel = (tab == "movie") and App.State.movie_gallery_index or App.State.image_gallery_index
    local offset = (tab == "movie") and App.State.movie_gallery_offset or App.State.image_gallery_offset
    local page_size = (tab == "movie") and (App.State.movie_gallery_page_size or 4) or (App.State.image_gallery_page_size or 4)
    local button_count = App.State.gallery_button_count or 12

    if #list == 0 then
        local prefix = (tab == "movie") and "movieGalleryBtn" or "imgGalleryBtn"
        for i = 1, button_count do
            local btn = items[prefix .. tostring(i)]
            if btn then
                set_widget_visible(btn, i == 1)
                set_button_empty_state(btn, (i == 1) and "Empty" or "", true)
                pcall(function() btn.Enabled = false end)
                pcall(function() btn.ToolTip = "" end)
            end
        end
        if tab == "movie" then
            App.State.movie_gallery_index = 0
            App.State.movie_gallery_offset = 1
        else
            App.State.image_gallery_index = 0
            App.State.image_gallery_offset = 1
        end
        if up_btn then pcall(function() up_btn.Enabled = false end) end
        if dn_btn then pcall(function() dn_btn.Enabled = false end) end
        if pos_label then pcall(function() pos_label.Text = "0/0" end) end
        return
    end

    local max_offset = math.max(1, (#list - page_size) + 1)
    if offset < 1 then offset = 1 end
    if offset > max_offset then offset = max_offset end
    if tab == "movie" then
        App.State.movie_gallery_offset = offset
    else
        App.State.image_gallery_offset = offset
    end

    local start_idx = offset
    local prefix = (tab == "movie") and "movieGalleryBtn" or "imgGalleryBtn"
    for i = 1, button_count do
        local btn = items[prefix .. tostring(i)]
        if btn then
            local show = i <= page_size
            set_widget_visible(btn, show)
            if show then
                local abs_idx = start_idx + i - 1
                local e = list[abs_idx]
                if e and e.path and file_exists(e.path) then
                    local kind = (e.kind == "video_gen") and "video" or "image"
                    set_button_image(btn, e.path, tostring(i), kind)
                    pcall(function() btn.Enabled = true end)
                    if abs_idx == sel then
                        set_button_square_style(btn, "border: 2px solid #A7B3DB;", 0)
                    else
                        set_button_square_style(btn, "border: 1px solid #5A607A;", 0)
                    end
                    pcall(function() btn.ToolTip = basename(e.path) end)
                else
                    set_button_empty_state(btn, "", true)
                    pcall(function() btn.ToolTip = "" end)
                    pcall(function() btn.Enabled = false end)
                end
            end
        end
    end

    -- ▲/▼ step buttons: enabled only when there is room to scroll
    if up_btn then pcall(function() up_btn.Enabled = offset > 1 end) end
    if dn_btn then pcall(function() dn_btn.Enabled = offset < max_offset end) end
    if pos_label then
        local visible_end = math.min(#list, offset + page_size - 1)
        pcall(function() pos_label.Text = tostring(offset) .. "-" .. tostring(visible_end) .. "/" .. tostring(#list) end)
    end
end

local function extract_wheel_delta(ev)
    if type(ev) ~= "table" then return 0 end
    local d = ev.delta or ev.Delta or ev.wheelDelta or ev.WheelDelta or ev.y or ev.Y
    if type(d) == "table" then
        d = d[2] or d.y or d.Y or d.delta or d.Delta
    end
    d = tonumber(d) or 0
    if d == 0 and ev.deltaY then
        d = tonumber(ev.deltaY) or 0
    end
    return d
end

local function on_gallery_wheel(tab, ev)
    local delta = extract_wheel_delta(ev)
    if delta == 0 then return end
    local list = (tab == "movie") and App.State.movie_gallery_list or App.State.image_gallery_list
    if not list or #list == 0 then return end
    local page = (tab == "movie") and (App.State.movie_gallery_page_size or 4) or (App.State.image_gallery_page_size or 4)
    local max_offset = math.max(1, (#list - page) + 1)
    local cur = (tab == "movie") and (App.State.movie_gallery_offset or 1) or (App.State.image_gallery_offset or 1)
    local accum_key = (tab == "movie") and "movie_wheel_accum" or "image_wheel_accum"
    local wheel_unit = 40
    App.State[accum_key] = (tonumber(App.State[accum_key]) or 0) + delta
    local raw_steps = math.floor(math.abs(App.State[accum_key]) / wheel_unit)
    if raw_steps < 1 then return end
    local accum_sign = (App.State[accum_key] < 0) and -1 or 1
    local dir = (App.State[accum_key] < 0) and 1 or -1
    App.State[accum_key] = (tonumber(App.State[accum_key]) or 0) - (accum_sign * raw_steps * wheel_unit)
    local step = dir * raw_steps
    local new_off = cur + step
    if new_off < 1 then new_off = 1 end
    if new_off > max_offset then new_off = max_offset end
    if new_off == cur then return end
    if tab == "movie" then
        App.State.movie_gallery_offset = new_off
    else
        App.State.image_gallery_offset = new_off
    end
    refresh_gallery_buttons(tab)
end

local function set_gallery_selection(tab, idx)
    idx = tonumber(idx) or 0
    if tab == "movie" then
        if idx < 1 or idx > #App.State.movie_gallery_list then
            return false, "No gallery item in slot " .. tostring(idx) .. "."
        end
        App.State.movie_gallery_index = idx
        local off = App.State.movie_gallery_offset or 1
        local page_size = App.State.movie_gallery_page_size or 4
        if idx < off then
            App.State.movie_gallery_offset = idx
        elseif idx > (off + page_size - 1) then
            App.State.movie_gallery_offset = idx - (page_size - 1)
        end
        refresh_gallery_buttons("movie")
        local e = App.State.movie_gallery_list[idx]
        return true, "Selected gallery: " .. basename(e.path or "")
    end
    if idx < 1 or idx > #App.State.image_gallery_list then
        return false, "No gallery item in slot " .. tostring(idx) .. "."
    end
    App.State.image_gallery_index = idx
    local off = App.State.image_gallery_offset or 1
    local page_size = App.State.image_gallery_page_size or 4
    if idx < off then
        App.State.image_gallery_offset = idx
    elseif idx > (off + page_size - 1) then
        App.State.image_gallery_offset = idx - (page_size - 1)
    end
    refresh_gallery_buttons("image")
    local e = App.State.image_gallery_list[idx]
    return true, "Selected gallery: " .. basename(e.path or "")
end

local function set_gallery_selection_visible(tab, visible_idx)
    local offset = (tab == "movie") and App.State.movie_gallery_offset or App.State.image_gallery_offset
    local page_size = (tab == "movie") and (App.State.movie_gallery_page_size or 4) or (App.State.image_gallery_page_size or 4)
    local idx = (math.max(1, offset) - 1) + math.min(page_size, math.max(1, tonumber(visible_idx) or 1))
    return set_gallery_selection(tab, idx)
end

local function gallery_path_from_visible_slot(tab, visible_idx)
    local offset = (tab == "movie") and App.State.movie_gallery_offset or App.State.image_gallery_offset
    local page_size = (tab == "movie") and (App.State.movie_gallery_page_size or 4) or (App.State.image_gallery_page_size or 4)
    local idx = (math.max(1, offset) - 1) + math.min(page_size, math.max(1, tonumber(visible_idx) or 1))
    local list = (tab == "movie") and App.State.movie_gallery_list or App.State.image_gallery_list
    local e = list and list[idx] or nil
    if e and e.path and file_exists(e.path) then
        return e.path
    end
    return nil
end

function refresh_gallery_ui()
    local items = App.State.items
    if not items then return end
    if App.State.ui_refreshing then return end

    local img_filter = combo_current_text(items.imgGalleryFilterCombo)
    if img_filter == "" then img_filter = "Recent References" end
    local img_kind = gallery_filter_kind(img_filter)

    local img_hist = get_project_history(img_kind)
    App.State.image_gallery_list = img_hist
    if App.State.image_gallery_offset < 1 then App.State.image_gallery_offset = 1 end
    if #img_hist == 0 then
        App.State.image_gallery_index = 0
    elseif App.State.image_gallery_index < 1 then
        App.State.image_gallery_index = 1
    elseif App.State.image_gallery_index > #img_hist then
        App.State.image_gallery_index = 1
    end

    local movie_filter = combo_current_text(items.movieGalleryFilterCombo)
    if movie_filter == "" then movie_filter = "Recent References" end
    local mov_kind = gallery_filter_kind(movie_filter)

    local mov_hist = get_project_history(mov_kind)
    App.State.movie_gallery_list = mov_hist
    if App.State.movie_gallery_offset < 1 then App.State.movie_gallery_offset = 1 end
    if #mov_hist == 0 then
        App.State.movie_gallery_index = 0
    elseif App.State.movie_gallery_index < 1 then
        App.State.movie_gallery_index = 1
    elseif App.State.movie_gallery_index > #mov_hist then
        App.State.movie_gallery_index = 1
    end

    refresh_gallery_buttons("image")
    refresh_gallery_buttons("movie")
end

local function current_gallery_entry(tab)
    if tab == "movie" then
        local idx = App.State.movie_gallery_index or 0
        return App.State.movie_gallery_list[idx]
    end
    local idx = App.State.image_gallery_index or 0
    return App.State.image_gallery_list[idx]
end

local function load_settings_from_gallery(tab)
    local entry = current_gallery_entry(tab)
    if not entry or not entry.path then
        return false, "No gallery item selected."
    end

    local meta = read_generation_sidecar(entry.path)
    if not meta then
        return false, "No sidecar settings found for selected item."
    end

    if tab == "movie" then
        if meta.model and meta.model ~= "" then App.Config.movie_model = meta.model end
        if meta.ref_mode and meta.ref_mode ~= "" then App.Config.movie_ref_mode = meta.ref_mode end
        if meta.aspect_ratio and meta.aspect_ratio ~= "" then App.Config.movie_aspect_ratio = meta.aspect_ratio end
        if meta.size_or_resolution and meta.size_or_resolution ~= "" then App.Config.movie_resolution = meta.size_or_resolution end
        if meta.duration and meta.duration ~= "" then App.Config.movie_duration = meta.duration end
        if meta.negative_prompt and meta.negative_prompt ~= "" then App.Config.movie_negative_prompt = meta.negative_prompt end

        local items = App.State.items
        if items and items.moviePromptEdit then
            items.moviePromptEdit.PlainText = meta.prompt or ""
        end

        refresh_model_combos()
        clear_all_refs("movie")
        local mov_refs_loaded = 0
        log("[LoadSettings] movie sidecar has " .. tostring(#(meta.refs or {})) .. " ref(s). movie_max_refs=" .. tostring(App.State.movie_max_refs))
        for i, p in ipairs(meta.refs or {}) do
            log("[LoadSettings] ref[" .. i .. "] = " .. tostring(p) .. " | exists=" .. tostring(file_exists(p)))
            if i <= (App.State.movie_max_refs or 3) and not is_video_file(p) then
                local resolved = p
                if not file_exists(resolved) then
                    local alt = App.Config.refs_dir .. basename(p)
                    log("[LoadSettings] fallback path: " .. tostring(alt) .. " | exists=" .. tostring(file_exists(alt)))
                    if file_exists(alt) then resolved = alt end
                end
                if file_exists(resolved) then
                    App.State.movie_refs[i] = resolved
                    mov_refs_loaded = mov_refs_loaded + 1
                end
            end
        end

        refresh_slot_buttons()
        refresh_gallery_ui()
        local mov_ref_note = (#(meta.refs or {}) > 0)
            and (" | " .. tostring(mov_refs_loaded) .. "/" .. tostring(#(meta.refs or {})) .. " refs restored")
            or ""
        return true, "Loaded movie settings from metadata: " .. basename(entry.path) .. mov_ref_note
    end

    if meta.model and meta.model ~= "" then App.Config.image_model = meta.model end
    if meta.aspect_ratio and meta.aspect_ratio ~= "" then App.Config.image_aspect_ratio = meta.aspect_ratio end
    if meta.size_or_resolution and meta.size_or_resolution ~= "" then App.Config.image_size = meta.size_or_resolution end

    local items = App.State.items
    if items and items.imgPromptEdit then
        items.imgPromptEdit.PlainText = meta.prompt or ""
    end

    refresh_model_combos()
    clear_all_refs("image")
    local img_refs_loaded = 0
    for i, p in ipairs(meta.refs or {}) do
        if i <= (App.State.image_max_refs or 8) then
            local resolved = p
            if not file_exists(resolved) then
                local alt = App.Config.refs_dir .. basename(p)
                if file_exists(alt) then resolved = alt end
            end
            if file_exists(resolved) then
                App.State.image_refs[i] = resolved
                img_refs_loaded = img_refs_loaded + 1
            end
        end
    end

    refresh_slot_buttons()
    refresh_gallery_ui()
    local img_ref_note = (#(meta.refs or {}) > 0)
        and (" | " .. tostring(img_refs_loaded) .. "/" .. tostring(#(meta.refs or {})) .. " refs restored")
        or ""
    return true, "Loaded image settings from metadata: " .. basename(entry.path) .. img_ref_note
end

local function keep_editing(tab)
    if tab == "movie" then
        if not App.State.last_movie_path or not file_exists(App.State.last_movie_path) then
            return false, "No movie result available."
        end
        clear_all_refs("movie")
        App.State.movie_refs[1] = App.State.last_movie_path
        refresh_slot_buttons()
        return true, "Loaded last movie result into slot 1."
    end

    if not App.State.last_image_path or not file_exists(App.State.last_image_path) then
        return false, "No image result available."
    end
    clear_all_refs("image")
    App.State.image_refs[1] = App.State.last_image_path
    refresh_slot_buttons()
    return true, "Loaded last image result into slot 1."
end

local function delete_selected_gallery(tab)
    local entry = current_gallery_entry(tab)
    if not entry or not entry.path then
        return false, "No gallery item selected."
    end
    local p = entry.path
    local sp = sidecar_path_for(p)

    if file_exists(p) then
        os.remove(p)
    end
    if file_exists(sp) then
        os.remove(sp)
    end

    delete_history_path(p)
    refresh_gallery_ui()
    return true, "Deleted: " .. basename(p)
end

local function use_selected_gallery_as_ref(tab)
    local entry = current_gallery_entry(tab)
    if not entry or not entry.path then
        return false, "No gallery item selected."
    end
    if not file_exists(entry.path) then
        return false, "Selected file no longer exists."
    end

    local idx, err = fill_ref_slot(tab, entry.path, {timeline = "Gallery", timecode = "", frame = ""})
    if not idx then
        return false, err or "Cannot load this file as a reference."
    end
    add_history("ref", entry.path)
    refresh_gallery_ui()
    refresh_slot_buttons()
    return true, "Loaded gallery image into slot " .. tostring(idx)
end

local function add_selected_gallery_to_pool(tab)
    local entry = current_gallery_entry(tab)
    if not entry or not entry.path then
        return false, "No gallery item selected."
    end
    if not file_exists(entry.path) then
        return false, "Selected file no longer exists."
    end
    local ok, err, staged = stage_and_import(entry.path)
    if ok then
        return true, "Added selected item to Media Pool:\n" .. tostring(staged or entry.path)
    end
    return false, "Import failed:\n" .. tostring(err)
end

local function set_group_visible(group, is_visible)
    if not group then return end
    pcall(function() group.Visible = is_visible end)
    pcall(function() group.Hidden = not is_visible end)
    pcall(function() group.Enabled = is_visible end)
    pcall(function() group.Weight = is_visible and 1 or 0 end)
    if is_visible then
        pcall(function() group.MinimumSize = {0, 0} end)
        pcall(function() group.MaximumSize = {16777215, 16777215} end)
    else
        pcall(function() group.MinimumSize = {0, 0} end)
        -- Collapse hidden tabs vertically without forcing a zero max width on the window.
        pcall(function() group.MaximumSize = {16777215, 0} end)
    end
end

local function show_tab(tab)
    local items = App.State.items
    if not items then return end
    App.State.current_tab = tab

    local is_image = (tab == "image")
    local is_movie = (tab == "movie")
    local is_config = (tab == "config")

    set_group_visible(items.imageTabGroup, is_image)
    set_group_visible(items.movieTabGroup, is_movie)
    set_group_visible(items.configTabGroup, is_config)
    refresh_tab_button_styles()

    local win = App.State.win
    if win then
        pcall(function() win:RecalcLayout() end)
        pcall(function() win:Update() end)
    end
    refresh_gallery_buttons("image")
    refresh_gallery_buttons("movie")
    refresh_slot_buttons()
end

local function parse_veo_blocking_hint(msg)
    msg = tostring(msg or "")
    if msg:lower():find("safety", 1, true) or msg:lower():find("blocked", 1, true) then
        return msg
    end
    return nil
end

-- Generates a fixed 16:9 JPEG thumbnail for the gallery browser.
-- Unique per-slot key_pfx avoids preview-cache aliasing.
local function make_browser_preview(path, key_pfx)
    if not path or not file_exists(path) then return nil end
    local W, H = 480, 270  -- 16:9
    local key  = (key_pfx or "galbr") .. "|16x9|" .. path
    local cached = App.State.preview_cache[key]
    if cached and file_exists(cached) then return cached end

    local out = unique_path(App.Config.temp_dir, key_pfx or "galbr", "jpg")
    local ok  = false

    if is_video_file(path) then
        if has_cmd("ffmpeg") then
            -- Scale to fill 16:9, then pad if needed
            local vf = "scale=" .. W .. ":" .. H .. ":force_original_aspect_ratio=decrease,"
                    .. "pad=" .. W .. ":" .. H .. ":(ow-iw)/2:(oh-ih)/2:black"
            local cmd = "ffmpeg -y -ss 0.5 -i " .. shell_quote(path)
                     .. " -frames:v 1 -vf " .. shell_quote(vf)
                     .. " " .. shell_quote(out) .. " >/dev/null 2>&1"
            ok = run_shell_ok(cmd) and file_exists(out)
        end
    else
        -- sips -z forces exact pixel dimensions; slight stretch is fine for thumbnails.
        local src = ensure_png(path) or path
        local cmd = "sips -z " .. H .. " " .. W .. " -s format jpeg "
                 .. shell_quote(src) .. " --out " .. shell_quote(out)
                 .. " >/dev/null 2>&1"
        ok = run_shell_ok(cmd) and file_exists(out)
    end

    if ok and file_exists(out) then
        App.State.preview_cache[key] = out
        return out
    end
    return nil
end


-- Gallery Browser Window
-- Opens a full-size resizable window with a 5×4 thumbnail grid, paged
-- navigation, and action buttons including Reveal in Finder.
-- Uses a nested disp:RunLoop() so the main window is suspended while open.
-- ---------------------------------------------------------------------------
local function open_gallery_browser(tab)
    if App.State.gallery_browser_open then return end
    App.State.gallery_browser_open = true

    local ui   = App.Core.ui
    local disp = App.Core.disp
    if not ui or not disp then
        App.State.gallery_browser_open = false
        return
    end

    local COLS     = 3
    local PER_PAGE = 15  -- 3 × 5
    local TOTAL_BTNS = PER_PAGE

    local bstate = {
        list    = {},
        page    = 1,
        sel_abs = 0,
        tab     = tab,
    }

    local function rebuild_list(filter_text)
        local kind = gallery_filter_kind(filter_text or "")
        bstate.list    = get_project_history(kind)
        bstate.page    = 1
        bstate.sel_abs = 0
    end

    -- Sync starting filter from main window
    local items_main     = App.State.items
    local initial_filter = ""
    if items_main then
        local cid = (tab == "movie") and "movieGalleryFilterCombo" or "imgGalleryFilterCombo"
        initial_filter = combo_current_text(items_main[cid]) or ""
    end
    rebuild_list(initial_filter)

    -- Sync starting selection
    local main_sel = (tab == "movie") and App.State.movie_gallery_index or App.State.image_gallery_index
    if main_sel and main_sel >= 1 and main_sel <= #bstate.list then
        bstate.sel_abs = main_sel
        bstate.page    = math.ceil(main_sel / PER_PAGE)
    end

    local filter_options = {"Recent References", "Recent Images", "Recent Videos", "All Recent"}
    local btn_style_base = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px;}QPushButton:hover{background:#252A3A;}QPushButton:disabled{color:#3A3F52;}"
    local title_str = (tab == "movie") and "Movie Gallery Browser" or "Image Gallery Browser"

    local bwin = disp:AddWindow({
        ID = "galBrowseWin",
        WindowTitle = title_str,
        WindowFlags = { Window = true }
    },
    ui:VGroup({ID = "galBrowseRoot", Spacing = 6,
        -- Top bar
        ui:HGroup({Weight = 0, Spacing = 8,
            ui:Label({Text = "Filter:", Weight = 0}),
            ui:ComboBox({ID = "galBrowseFilterCombo", Weight = 1}),
            ui:Label({ID = "galBrowsePosLabel", Text = "Loading…", Weight = 1}),
            ui:Button({ID = "galBrowsePrevBtn", Text = "◀ Prev", Weight = 0}),
            ui:Button({ID = "galBrowseNextBtn", Text = "Next ▶", Weight = 0})
        }),
        -- Thumbnail grid: 5 rows × 3 columns
        ui:HGroup({Weight = 1, Spacing = 4,
            ui:Button({ID = "galBrowseBtn1",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn2",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn3",  Text = "", Weight = 1})
        }),
        ui:HGroup({Weight = 1, Spacing = 4,
            ui:Button({ID = "galBrowseBtn4",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn5",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn6",  Text = "", Weight = 1})
        }),
        ui:HGroup({Weight = 1, Spacing = 4,
            ui:Button({ID = "galBrowseBtn7",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn8",  Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn9",  Text = "", Weight = 1})
        }),
        ui:HGroup({Weight = 1, Spacing = 4,
            ui:Button({ID = "galBrowseBtn10", Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn11", Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn12", Text = "", Weight = 1})
        }),
        ui:HGroup({Weight = 1, Spacing = 4,
            ui:Button({ID = "galBrowseBtn13", Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn14", Text = "", Weight = 1}),
            ui:Button({ID = "galBrowseBtn15", Text = "", Weight = 1})
        }),
        -- Action bar
        ui:HGroup({Weight = 0, Spacing = 4,
            ui:Button({ID = "galBrowseUseBtn",    Text = "Use as Ref"}),
            ui:Button({ID = "galBrowseLoadBtn",   Text = "Load Settings"}),
            ui:Button({ID = "galBrowseOpenBtn",   Text = "Open"}),
            ui:Button({ID = "galBrowseFindBtn",   Text = "Reveal in Finder"}),
            ui:Button({ID = "galBrowsePoolBtn",   Text = "Add to Pool"}),
            ui:Button({ID = "galBrowseDeleteBtn", Text = "Delete"}),
            ui:Button({ID = "galBrowseCloseBtn",  Text = "Close"})
        }),
        ui:Label({ID = "galBrowseStatusLabel", Text = "", Weight = 0})
    }))

    if not bwin then
        App.State.gallery_browser_open = false
        return
    end

    local bitems = bwin:GetItems()
    -- Constrain each thumbnail button to a fixed 16:9 height so the grid
    -- always fits on screen regardless of image aspect ratio.
    local BTN_H = 160  -- px; 3 buttons at ~490px ea + spacing/UI chrome ≈760px total
    for i = 1, TOTAL_BTNS do
        local b = bitems["galBrowseBtn" .. i]
        if b then
            pcall(function() b.MaximumSize = {16777215, BTN_H} end)
            pcall(function() b.MinimumSize = {0, BTN_H - 20}   end)
        end
    end
    pcall(function() bwin.Geometry = {80, 40, 1100, 840} end)

    -- Populate filter combo
    combo_set_items(bitems.galBrowseFilterCombo, filter_options,
        initial_filter ~= "" and initial_filter or filter_options[1])

    local function set_browser_status(msg)
        pcall(function()
            if bitems.galBrowseStatusLabel then
                bitems.galBrowseStatusLabel.Text = tostring(msg or "")
            end
        end)
    end

    local function refresh_browser()
        local total    = #bstate.list
        local max_page = math.max(1, math.ceil(total / PER_PAGE))
        if bstate.page < 1       then bstate.page = 1        end
        if bstate.page > max_page then bstate.page = max_page end

        local start_abs = (bstate.page - 1) * PER_PAGE + 1
        local end_abs   = math.min(total, start_abs + PER_PAGE - 1)

        if total == 0 then
            pcall(function() bitems.galBrowsePosLabel.Text = "No items" end)
        else
            pcall(function()
                bitems.galBrowsePosLabel.Text =
                    "Items " .. tostring(start_abs) .. "\xe2\x80\x93" .. tostring(end_abs)
                    .. " of " .. tostring(total)
            end)
        end

        pcall(function() bitems.galBrowsePrevBtn.Enabled = bstate.page > 1        end)
        pcall(function() bitems.galBrowseNextBtn.Enabled = bstate.page < max_page end)

        for slot = 1, TOTAL_BTNS do
            local abs_idx = start_abs + slot - 1
            local btn     = bitems["galBrowseBtn" .. tostring(slot)]
            if btn then
                local e = bstate.list[abs_idx]
                if e and e.path and file_exists(e.path) then
                    -- Generate a fixed 16:9 thumbnail (480×270) for consistent row heights.
                    local key_pfx    = "galbr" .. tostring(slot)
                    local preview_path = make_browser_preview(e.path, key_pfx)
                    local icon_set   = false
                    if preview_path and App.Core.ui then
                        local ok, icon = pcall(function()
                            return App.Core.ui:Icon({File = preview_path})
                        end)
                        if ok and icon then
                            pcall(function()
                                btn.Icon = icon
                                btn.Text = ""
                                btn.ToolTip = basename(e.path)
                            end)
                            icon_set = true
                        end
                    end
                    if not icon_set then
                        btn.Text = tostring(abs_idx)
                        btn.ToolTip = basename(e.path)
                        clear_button_icon(btn)
                    end
                    pcall(function() btn.Enabled = true end)
                    local border = (abs_idx == bstate.sel_abs)
                        and "border: 3px solid #7B9FDB;"
                        or  "border: 1px solid #5A607A;"
                    set_button_square_style(btn, border, 0)
                else
                    set_button_empty_state(btn, "", true)
                    pcall(function() btn.Enabled = false end)
                    pcall(function() btn.ToolTip = "" end)
                end
            end
        end

        local has_sel = bstate.sel_abs >= 1
            and bstate.sel_abs <= total
            and file_exists(((bstate.list[bstate.sel_abs] or {}).path) or "")
        for _, aid in ipairs({"galBrowseUseBtn","galBrowseLoadBtn","galBrowseOpenBtn",
                              "galBrowseFindBtn","galBrowsePoolBtn","galBrowseDeleteBtn"}) do
            pcall(function() if bitems[aid] then bitems[aid].Enabled = has_sel end end)
        end
    end

    -- Show first so widgets are realized; THEN populate icons.
    -- Fusion's UIManager silently drops Icon assignments on widgets that
    -- haven't been painted yet, which caused blank buttons on first open.
    bwin:Show()
    pcall(function() bwin.Geometry = {80, 40, 1100, 840} end)
    refresh_browser()

    -- Filter
    bwin.On.galBrowseFilterCombo.CurrentIndexChanged = function()
        rebuild_list(combo_current_text(bitems.galBrowseFilterCombo))
        refresh_browser()
    end

    -- Paging
    bwin.On.galBrowsePrevBtn.Clicked = function()
        bstate.page = bstate.page - 1
        refresh_browser()
    end
    bwin.On.galBrowseNextBtn.Clicked = function()
        bstate.page = bstate.page + 1
        refresh_browser()
    end

    -- Thumbnail clicks (single = select, double = Use as Ref)
    local last_click_abs = 0
    local last_click_ms  = 0
    for slot = 1, TOTAL_BTNS do
        local s = slot
        bwin.On["galBrowseBtn" .. tostring(s)].Clicked = function()
            local abs_idx = (bstate.page - 1) * PER_PAGE + s
            if abs_idx < 1 or abs_idx > #bstate.list then return end
            local t = now_ms()
            local is_dbl = (abs_idx == last_click_abs) and ((t - last_click_ms) < 500)
            last_click_ms  = t
            last_click_abs = abs_idx
            bstate.sel_abs = abs_idx
            refresh_browser()
            local e = bstate.list[abs_idx]
            set_browser_status("Selected: " .. basename((e or {}).path or ""))
            if is_dbl and e and e.path and file_exists(e.path) then
                -- Double-click: load into first empty ref slot
                local max_r = (bstate.tab == "movie") and (App.State.movie_max_refs or 2)
                              or (App.State.image_max_refs or 8)
                local refs  = (bstate.tab == "movie") and App.State.movie_refs or App.State.image_refs
                for i = 1, max_r do
                    if not refs[i] or refs[i] == "" then
                        refs[i] = e.path
                        refresh_slot_buttons()
                        set_browser_status("Loaded into slot " .. i .. " (double-click)")
                        return
                    end
                end
                set_browser_status("All ref slots are full.")
            end
        end
    end

    -- Helper: get current selected entry
    local function sel_entry()
        return bstate.list[bstate.sel_abs]
    end

    -- Use as Ref
    bwin.On.galBrowseUseBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path or not file_exists(e.path) then
            set_browser_status("No item selected.")
            return
        end
        local max_r = (bstate.tab == "movie") and (App.State.movie_max_refs or 2)
                      or (App.State.image_max_refs or 8)
        local refs  = (bstate.tab == "movie") and App.State.movie_refs or App.State.image_refs
        for i = 1, max_r do
            if not refs[i] or refs[i] == "" then
                refs[i] = e.path
                refresh_slot_buttons()
                set_browser_status("Loaded into slot " .. i)
                return
            end
        end
        set_browser_status("All ref slots are full.")
    end

    -- Load Settings
    bwin.On.galBrowseLoadBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path then
            set_browser_status("No item selected.")
            return
        end
        if bstate.tab == "movie" then
            App.State.movie_gallery_index = bstate.sel_abs
        else
            App.State.image_gallery_index = bstate.sel_abs
        end
        local ok, msg = load_settings_from_gallery(bstate.tab)
        set_browser_status(msg)
    end

    -- Open
    bwin.On.galBrowseOpenBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path or not file_exists(e.path) then
            set_browser_status("No item selected.")
            return
        end
        local ok = open_file(e.path)
        set_browser_status(ok and ("Opened: " .. basename(e.path)) or "Failed to open file.")
    end

    -- Reveal in Finder
    bwin.On.galBrowseFindBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path or not file_exists(e.path) then
            set_browser_status("No item selected.")
            return
        end
        local ok = reveal_in_finder(e.path)
        set_browser_status(ok and ("Revealed: " .. basename(e.path)) or "Reveal in Finder failed.")
    end

    -- Add to Media Pool
    bwin.On.galBrowsePoolBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path or not file_exists(e.path) then
            set_browser_status("No item selected.")
            return
        end
        local ok, err, staged = stage_and_import(e.path)
        set_browser_status(ok
            and ("Added to Media Pool: " .. basename(staged or e.path))
            or  ("Failed: " .. tostring(err)))
    end

    -- Delete
    bwin.On.galBrowseDeleteBtn.Clicked = function()
        local e = sel_entry()
        if not e or not e.path then
            set_browser_status("No item selected.")
            return
        end
        local p  = e.path
        local sp = sidecar_path_for(p)
        if file_exists(p)  then os.remove(p)  end
        if file_exists(sp) then os.remove(sp) end
        delete_history_path(p)
        bstate.sel_abs = 0
        rebuild_list(combo_current_text(bitems.galBrowseFilterCombo))
        refresh_browser()
        refresh_gallery_ui()
        set_browser_status("Deleted: " .. basename(p))
    end

    -- Close: sync selection back to main window
    local function do_browser_close()
        if bstate.sel_abs >= 1 and bstate.sel_abs <= #bstate.list then
            if bstate.tab == "movie" then
                App.State.movie_gallery_index = bstate.sel_abs
                local ps = App.State.movie_gallery_page_size or 4
                App.State.movie_gallery_offset = math.max(1, bstate.sel_abs - math.floor(ps / 2))
            else
                App.State.image_gallery_index = bstate.sel_abs
                local ps = App.State.image_gallery_page_size or 4
                App.State.image_gallery_offset = math.max(1, bstate.sel_abs - math.floor(ps / 2))
            end
            refresh_gallery_ui()
        end
        App.State.gallery_browser_open = false
        disp:ExitLoop()
    end

    bwin.On.galBrowseCloseBtn.Clicked  = function() do_browser_close() end
    bwin.On.galBrowseWin.Close         = function() do_browser_close() end

    disp:RunLoop()
    bwin:Hide()
end

-- Route new module locals through the App table so they don't add upvalues to
-- build_ui() -- LuaJIT caps closures at 60 upvalues and build_ui is at that limit.
App._galFn = {
    browse = open_gallery_browser,
    find   = function(tab)
        local e = current_gallery_entry(tab)
        if e and e.path and file_exists(e.path) then
            return reveal_in_finder(e.path), "Revealed: " .. basename(e.path)
        end
        return false, "No gallery item selected."
    end,
}

local function build_ui()
    if not App.Core.disp then
        return nil
    end

    local ui = App.Core.ui
    local function make_vscroll(id)
        local ctrl
        if ui.ScrollBar then
            ctrl = ui:ScrollBar({ID = id, Orientation = "Vertical", Weight = 1})
        elseif ui.Slider then
            ctrl = ui:Slider({ID = id, Orientation = "Vertical", Weight = 1})
        elseif ui.SpinBox then
            ctrl = ui:SpinBox({ID = id, Weight = 0})
        else
            ctrl = ui:LineEdit({ID = id, Text = "1", Weight = 0})
        end
        set_scroll_macos_style(ctrl)
        return ctrl
    end

    local win = App.Core.disp:AddWindow({
        ID = "cleanRoomWin",
        WindowTitle = App.Config.script_name .. " " .. App.Config.script_version,
        WindowFlags = { Window = true }
    },
    ui:VGroup({ID = "root", Spacing = 4,
        ui:HGroup({Weight = 0, Spacing = 6,
            ui:Button({ID = "tabImageBtn", Text = "ImageGen"}),
            ui:Button({ID = "tabMovieBtn", Text = "MovieGen"}),
            ui:Button({ID = "tabConfigBtn", Text = "Configuration"}),
            ui:Button({ID = "uiRefreshBtn", Text = "Refresh UI", Weight = 0})
        }),

        ui:VGroup({ID = "imageTabGroup", Weight = 1, Spacing = 4,
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Model", Weight = 0}),
                ui:ComboBox({ID = "imgModelCombo", Weight = 1}),
                ui:Button({ID = "imgRefreshModelsBtn", Text = "Refresh Models", Weight = 0})
            }),
            ui:Label({ID = "imgCapsLabel", Text = "Capabilities:", Weight = 0}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Aspect Ratio", Weight = 0}),
                ui:ComboBox({ID = "imgAspectCombo", Weight = 0}),
                ui:Label({Text = "Image Size", Weight = 0}),
                ui:ComboBox({ID = "imgSizeCombo", Weight = 0})
            }),
            ui:Label({Text = "Prompt", Weight = 0}),
            ui:TextEdit({ID = "imgPromptEdit", Weight = 0.12, PlainText = "Describe your transformation."}),
            ui:HGroup({ID = "imgInlineTokenPickerRow", Weight = 0, Spacing = 6, Hidden = true, Visible = false,
                ui:Label({Text = "Insert Ref", Weight = 0}),
                ui:ComboBox({ID = "imgInlineTokenCombo", Weight = 1}),
                ui:Button({ID = "imgInlineTokenInsertBtn", Text = "Insert", Weight = 0})
            }),
            ui:HGroup({ID = "imgTokenRow", Weight = 0, Spacing = 6,
                ui:Button({ID = "imgToken1Btn", Text = "@image1"}),
                ui:Button({ID = "imgToken2Btn", Text = "@image2"}),
                ui:Button({ID = "imgToken3Btn", Text = "@image3"}),
                ui:Button({ID = "imgToken4Btn", Text = "@image4"}),
                ui:Button({ID = "imgToken5Btn", Text = "@image5"}),
                ui:Button({ID = "imgToken6Btn", Text = "@image6"}),
                ui:Button({ID = "imgToken7Btn", Text = "@image7"}),
                ui:Button({ID = "imgToken8Btn", Text = "@image8"})
            }),

            ui:HGroup({Weight = 1, Spacing = 6,
                ui:VGroup({ID = "imgGalleryCol", Weight = 0.18, Spacing = 6,
                    ui:HGroup({Weight = 0, Spacing = 4,
                        ui:Label({Text = "Gallery", Weight = 1}),
                        ui:Button({ID = "imgGalleryBrowseBtn", Text = "Browse ↗", Weight = 0,
                            StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 6px;font-size:11px;}QPushButton:hover{background:#252A3A;}"})
                    }),
                    ui:ComboBox({ID = "imgGalleryFilterCombo", Weight = 0}),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:VGroup({ID = "imgGalleryListGroup", Weight = 1, Spacing = 4,
                            ui:Button({ID = "imgGalleryBtn1",  Text = "1",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn2",  Text = "2",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn3",  Text = "3",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn4",  Text = "4",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn5",  Text = "5",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn6",  Text = "6",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn7",  Text = "7",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn8",  Text = "8",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn9",  Text = "9",  Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn10", Text = "10", Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn11", Text = "11", Weight = 0}),
                            ui:Button({ID = "imgGalleryBtn12", Text = "12", Weight = 0})
                        }),
                        ui:VGroup({Weight = 0, Spacing = 2,
                            ui:Button({ID = "imgGalleryScrollUp", Text = "▲", Weight = 0}),
                            ui:Label({ID = "imgGalleryScrollPosLabel", Text = "0/0", Weight = 1}),
                            ui:Button({ID = "imgGalleryScrollDn", Text = "▼", Weight = 0})
                        })
                    }),
                    ui:Button({ID = "imgGalleryUseBtn",    Text = "Use as Ref",         Weight = 0}),
                    ui:Button({ID = "imgGalleryDeleteBtn", Text = "Delete Selected",     Weight = 0}),
                    ui:Button({ID = "imgGalleryFindBtn",   Text = "Reveal in Finder",    Weight = 0}),
                    ui:Button({ID = "imgGalleryPasteBtn",  Text = "Paste Ref",           Weight = 0}),
                    ui:Button({ID = "imgGalleryLoadBtn",   Text = "Load Settings",       Weight = 0}),
                    ui:Button({ID = "imgGalleryAddPoolBtn",Text = "Add Selected To Pool",Weight = 0}),
                    ui:Button({ID = "imgUndoRefBtn", Text = "↩ Undo Clear", Weight = 0,
                        StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 8px;}QPushButton:hover{background:#252A3A;}QPushButton:disabled{color:#3A3F52;}"})
                }),
                ui:VGroup({ID = "imgRefGrid", Weight = 0.22, Spacing = 6,
                    ui:Label({Text = "Original", Weight = 0}),
                    ui:HGroup({ID = "imgRefRow1", Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn1", Text = "1"}),
                        ui:Button({ID = "imgRefBtn2", Text = "2"})
                    }),
                    ui:HGroup({ID = "imgRefRow2", Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn3", Text = "3"}),
                        ui:Button({ID = "imgRefBtn4", Text = "4"})
                    }),
                    ui:HGroup({ID = "imgRefRow3", Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn5", Text = "5"}),
                        ui:Button({ID = "imgRefBtn6", Text = "6"})
                    }),
                    ui:HGroup({ID = "imgRefRow4", Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn7", Text = "7"}),
                        ui:Button({ID = "imgRefBtn8", Text = "8"})
                    })
                }),
                ui:VGroup({ID = "imgResultCol", Weight = 0.60, Spacing = 6,
                    ui:HGroup({Weight = 0, Spacing = 6,
                        ui:Label({Text = "Result", Weight = 1}),
                        ui:Button({ID = "imgOpenResultBtn", Text = "⎋ Open", Weight = 0,
                            StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 8px;font-size:11px;}QPushButton:hover{background:#252A3A;}QPushButton:disabled{color:#3A3F52;}"})
                    }),
                    ui:Button({ID = "imgResultBtn", Text = "Result", Weight = 1}),
                    ui:Label({ID = "imgResultHintLabel", Text = "No result yet", Weight = 0})
                })
            }),

            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Button({ID = "imgGrabBtn", Text = "Grab Current Frame"}),
                ui:Button({ID = "imgClearBtn", Text = "Clear Slots"}),
                ui:Button({ID = "imgGenerateBtn", Text = "Generate"}),
                ui:Button({ID = "imgKeepEditingBtn", Text = "Keep Editing"}),
                ui:Button({ID = "imgAddPoolBtn", Text = "Add to Media Pool"}),
                ui:Button({ID = "imgCloseBtn", Text = "Close"})
            }),
            ui:TextEdit({ID = "imgStatusBox", ReadOnly = true, Weight = 0, PlainText = "Ready."})
        }),

        ui:VGroup({ID = "movieTabGroup", Weight = 1, Spacing = 4,
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Movie Model", Weight = 0}),
                ui:ComboBox({ID = "movieModelCombo", Weight = 1}),
                ui:Button({ID = "movieRefreshModelsBtn", Text = "Refresh Movie Models", Weight = 0})
            }),
            ui:Label({ID = "movieCapsLabel", Text = "Capabilities:", Weight = 0}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Ref Mode", Weight = 0}),
                ui:ComboBox({ID = "movieRefModeCombo", Weight = 0}),
                ui:Label({Text = "Aspect Ratio", Weight = 0}),
                ui:ComboBox({ID = "movieAspectCombo", Weight = 0}),
                ui:Label({Text = "Resolution", Weight = 0}),
                ui:ComboBox({ID = "movieResolutionCombo", Weight = 0}),
                ui:Label({Text = "Duration (s)", Weight = 0}),
                ui:ComboBox({ID = "movieDurationCombo", Weight = 0})
            }),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Negative Prompt", Weight = 0}),
                ui:LineEdit({ID = "movieNegativeEdit", Weight = 1})
            }),
            ui:Label({Text = "Prompt", Weight = 0}),
            ui:TextEdit({ID = "moviePromptEdit", Weight = 0.12, PlainText = "Describe your shot."}),
            ui:HGroup({ID = "movieInlineTokenPickerRow", Weight = 0, Spacing = 6, Hidden = true, Visible = false,
                ui:Label({Text = "Insert Ref", Weight = 0}),
                ui:ComboBox({ID = "movieInlineTokenCombo", Weight = 1}),
                ui:Button({ID = "movieInlineTokenInsertBtn", Text = "Insert", Weight = 0})
            }),
            ui:HGroup({ID = "movieTokenRow", Weight = 0, Spacing = 6,
                ui:Button({ID = "movieToken1Btn", Text = "@image1"}),
                ui:Button({ID = "movieToken2Btn", Text = "@image2"}),
                ui:Button({ID = "movieToken3Btn", Text = "@image3"})
            }),

            ui:HGroup({Weight = 1, Spacing = 6,
                ui:VGroup({ID = "movieGalleryCol", Weight = 0.18, Spacing = 6,
                    ui:HGroup({Weight = 0, Spacing = 4,
                        ui:Label({Text = "Gallery", Weight = 1}),
                        ui:Button({ID = "movieGalleryBrowseBtn", Text = "Browse ↗", Weight = 0,
                            StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 6px;font-size:11px;}QPushButton:hover{background:#252A3A;}"})
                    }),
                    ui:ComboBox({ID = "movieGalleryFilterCombo", Weight = 0}),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:VGroup({ID = "movieGalleryListGroup", Weight = 1, Spacing = 4,
                            ui:Button({ID = "movieGalleryBtn1",  Text = "1",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn2",  Text = "2",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn3",  Text = "3",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn4",  Text = "4",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn5",  Text = "5",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn6",  Text = "6",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn7",  Text = "7",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn8",  Text = "8",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn9",  Text = "9",  Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn10", Text = "10", Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn11", Text = "11", Weight = 0}),
                            ui:Button({ID = "movieGalleryBtn12", Text = "12", Weight = 0})
                        }),
                        ui:VGroup({Weight = 0, Spacing = 2,
                            ui:Button({ID = "movieGalleryScrollUp", Text = "▲", Weight = 0}),
                            ui:Label({ID = "movieGalleryScrollPosLabel", Text = "0/0", Weight = 1}),
                            ui:Button({ID = "movieGalleryScrollDn", Text = "▼", Weight = 0})
                        })
                    }),
                    ui:Button({ID = "movieGalleryUseBtn",    Text = "Use as Ref",         Weight = 0}),
                    ui:Button({ID = "movieGalleryDeleteBtn", Text = "Delete Selected",     Weight = 0}),
                    ui:Button({ID = "movieGalleryFindBtn",   Text = "Reveal in Finder",    Weight = 0}),
                    ui:Button({ID = "movieGalleryPasteBtn",  Text = "Paste Ref",           Weight = 0}),
                    ui:Button({ID = "movieGalleryLoadBtn",   Text = "Load Settings",       Weight = 0}),
                    ui:Button({ID = "movieGalleryAddPoolBtn",Text = "Add Selected To Pool",Weight = 0}),
                    ui:Button({ID = "movieUndoRefBtn", Text = "↩ Undo Clear", Weight = 0,
                        StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 8px;}QPushButton:hover{background:#252A3A;}QPushButton:disabled{color:#3A3F52;}"})
                }),
                ui:VGroup({ID = "movieRefGrid", Weight = 0.22, Spacing = 6,
                    ui:Label({Text = "Original", Weight = 0}),
                    ui:HGroup({ID = "movieRefRow1", Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn1", Text = "1"}),
                        ui:Button({ID = "movieRefBtn2", Text = "2"})
                    }),
                    ui:HGroup({ID = "movieRefRow2", Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn3", Text = "3"}),
                        ui:Button({ID = "movieRefBtn4", Text = "4"})
                    }),
                    ui:HGroup({ID = "movieRefRow3", Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn5", Text = "5"}),
                        ui:Button({ID = "movieRefBtn6", Text = "6"})
                    }),
                    ui:HGroup({ID = "movieRefRow4", Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn7", Text = "7"}),
                        ui:Button({ID = "movieRefBtn8", Text = "8"})
                    })
                }),
                ui:VGroup({ID = "movieResultCol", Weight = 0.60, Spacing = 6,
                    ui:HGroup({Weight = 0, Spacing = 6,
                        ui:Label({Text = "Result", Weight = 1}),
                        ui:Button({ID = "movieOpenResultBtn", Text = "⎋ Open", Weight = 0,
                            StyleSheet = "QPushButton{border-radius:0px;border:1px solid #5A607A;background:#1A1F2C;color:#9AA4C2;padding:2px 8px;font-size:11px;}QPushButton:hover{background:#252A3A;}QPushButton:disabled{color:#3A3F52;}"})
                    }),
                    ui:Button({ID = "movieResultBtn", Text = "Result", Weight = 1}),
                    ui:Label({ID = "movieResultHintLabel", Text = "No result yet", Weight = 0})
                })
            }),

            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Button({ID = "movieGrabBtn", Text = "Grab Current Frame"}),
                ui:Button({ID = "movieClearBtn", Text = "Clear Slots"}),
                ui:Button({ID = "movieGenerateBtn", Text = "Generate Movie"}),
                ui:Button({ID = "movieKeepEditingBtn", Text = "Keep Editing"}),
                ui:Button({ID = "movieExtendBtn", Text = "Extend Movie"}),
                ui:Button({ID = "movieAddPoolBtn", Text = "Add Movie To Media Pool"}),
                ui:Button({ID = "moviePlayBtn", Text = "Play Result"}),
                ui:Button({ID = "movieCloseBtn", Text = "Close"})
            }),
            ui:TextEdit({ID = "movieStatusBox", ReadOnly = true, Weight = 0, PlainText = "Ready."})
        }),

        ui:VGroup({ID = "configTabGroup", Weight = 1, Spacing = 4,
            ui:Label({Text = "Gemini Endpoint", Weight = 0}),
            ui:LineEdit({ID = "cfgGeminiUrlEdit", Weight = 0}),
            ui:Label({Text = "Gemini API Key", Weight = 0}),
            ui:LineEdit({ID = "cfgGeminiKeyEdit", EchoMode = "Password", Weight = 0}),

            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Button({ID = "cfgGeminiTestBtn", Text = "Test Gemini Key"}),
                ui:Button({ID = "cfgSaveBtn", Text = "Save Config"}),
                ui:Button({ID = "cfgOpenReadmeBtn", Text = "Open README"}),
                ui:Button({ID = "cfgCheckUpdatesBtn", Text = "Check for Updates"}),
                ui:Button({ID = "cfgGetApiKeyBtn", Text = "Get API Key"})
            }),

            ui:Label({Text = "Black Magic Banana v" .. App.Config.script_version .. "  |  https://github.com/Chewboctopus/Black-Magic-Banana", Weight = 0}),

            ui:Label({Text = "Save Generations To", Weight = 0}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:LineEdit({ID = "cfgSaveDirEdit", Weight = 1}),
                ui:Button({ID = "cfgSaveDirBrowseBtn", Text = "Browse", Weight = 0})
            }),

            ui:Label({Text = "Media Pool Staging Folder", Weight = 0}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:LineEdit({ID = "cfgPoolDirEdit", Weight = 1}),
                ui:Button({ID = "cfgPoolDirBrowseBtn", Text = "Browse", Weight = 0})
            }),

            ui:Label({ID = "cfgStatusBox", Text = "Ready.", Weight = 0})
        })
    }))

    local MIN_W, MIN_H = 860, 720

    local items = win:GetItems()
    App.State.items = items
    App.State.win = win
    -- Force geometry as a property assignment BEFORE Show().
    -- Do NOT set win.MinimumSize / win.MaximumSize here — in Fusion's Qt binding
    -- those behave like setFixedSize() on the window and lock all resize.
    pcall(function() win.Geometry = {64, 32, 1620, 900} end)

    local function force_square_buttons()
        local button_ids = {
            "tabImageBtn", "tabMovieBtn", "tabConfigBtn", "uiRefreshBtn",
            "imgRefreshModelsBtn", "imgToken1Btn", "imgToken2Btn", "imgToken3Btn", "imgToken4Btn", "imgToken5Btn", "imgToken6Btn", "imgToken7Btn", "imgToken8Btn", "imgInlineTokenInsertBtn",
            "imgGalleryBrowseBtn", "imgGalleryScrollUp", "imgGalleryScrollDn",
            "imgGalleryUseBtn", "imgGalleryDeleteBtn", "imgGalleryFindBtn", "imgGalleryPasteBtn", "imgGalleryLoadBtn", "imgGalleryAddPoolBtn", "imgUndoRefBtn", "imgOpenResultBtn",
            "imgGrabBtn", "imgClearBtn", "imgGenerateBtn", "imgKeepEditingBtn", "imgAddPoolBtn", "imgCloseBtn",
            "movieRefreshModelsBtn", "movieToken1Btn", "movieToken2Btn", "movieToken3Btn", "movieInlineTokenInsertBtn",
            "movieGalleryBrowseBtn", "movieGalleryScrollUp", "movieGalleryScrollDn",
            "movieGalleryUseBtn", "movieGalleryDeleteBtn", "movieGalleryFindBtn", "movieGalleryPasteBtn", "movieGalleryLoadBtn", "movieGalleryAddPoolBtn", "movieUndoRefBtn", "movieOpenResultBtn",
            "movieGrabBtn", "movieClearBtn", "movieGenerateBtn", "movieKeepEditingBtn", "movieExtendBtn", "movieAddPoolBtn", "moviePlayBtn", "movieCloseBtn",
            "cfgGeminiTestBtn", "cfgSaveBtn", "cfgSaveDirBrowseBtn", "cfgPoolDirBrowseBtn", "cfgOpenReadmeBtn", "cfgCheckUpdatesBtn", "cfgGetApiKeyBtn"
        }
        for _, id in ipairs(button_ids) do
            local btn = items[id]
            if btn then
                style_action_button(btn, false)
            end
        end

        local control_ids = {
            "imgModelCombo", "imgAspectCombo", "imgSizeCombo",
            "movieModelCombo", "movieRefModeCombo", "movieAspectCombo", "movieResolutionCombo", "movieDurationCombo",
            "imgGalleryFilterCombo", "imgInlineTokenCombo",
            "movieGalleryFilterCombo", "movieInlineTokenCombo",
            "cfgGeminiUrlEdit", "cfgGeminiKeyEdit", "cfgSaveDirEdit", "cfgPoolDirEdit",
            "movieNegativeEdit", "imgPromptEdit", "moviePromptEdit", "imgStatusBox", "movieStatusBox"
        }
        for _, id in ipairs(control_ids) do
            local c = items[id]
            if c then
                set_control_square_style(c, "")
            end
        end

        pcall(function() if items.imgPromptEdit then items.imgPromptEdit.MaximumSize = {16777215, 84} end end)
        pcall(function() if items.moviePromptEdit then items.moviePromptEdit.MaximumSize = {16777215, 84} end end)
        pcall(function() if items.imgStatusBox then items.imgStatusBox.MaximumSize = {16777215, 44} end end)
        pcall(function() if items.movieStatusBox then items.movieStatusBox.MaximumSize = {16777215, 44} end end)
        pcall(function() if items.imgResultHintLabel then items.imgResultHintLabel.StyleSheet = "color: #9AA4C2;" end end)
        pcall(function() if items.movieResultHintLabel then items.movieResultHintLabel.StyleSheet = "color: #9AA4C2;" end end)

        for i = 1, (App.State.gallery_button_count or 12) do
            local ib = items["imgGalleryBtn" .. tostring(i)]
            local mb = items["movieGalleryBtn" .. tostring(i)]
            if ib then set_button_square_style(ib, "border: 1px solid #5A607A;", 0) end
            if mb then set_button_square_style(mb, "border: 1px solid #5A607A;", 0) end
        end
        if items.imgGalleryScroll then
            set_scroll_macos_style(items.imgGalleryScroll)
            pcall(function() items.imgGalleryScroll.MinimumSize = {16, 0} end)
            pcall(function() items.imgGalleryScroll.MaximumSize = {20, 16777215} end)
        end
        if items.movieGalleryScroll then
            set_scroll_macos_style(items.movieGalleryScroll)
            pcall(function() items.movieGalleryScroll.MinimumSize = {16, 0} end)
            pcall(function() items.movieGalleryScroll.MaximumSize = {20, 16777215} end)
        end
        if items.imgGalleryScrollPosLabel then
            pcall(function() items.imgGalleryScrollPosLabel.StyleSheet = "color: #AAB3CC; font-size: 10px; qproperty-alignment: 'AlignHCenter';" end)
        end
        if items.movieGalleryScrollPosLabel then
            pcall(function() items.movieGalleryScrollPosLabel.StyleSheet = "color: #AAB3CC; font-size: 10px; qproperty-alignment: 'AlignHCenter';" end)
        end
        update_gallery_layout("image")
        update_gallery_layout("movie")

        refresh_tab_button_styles()
    end

    combo_set_items(items.imgGalleryFilterCombo, {"Recent References", "Recent Image Gens", "Recent Videos", "All"}, "Recent References")
    combo_set_items(items.movieGalleryFilterCombo, {"Recent References", "Recent Image Gens", "Recent Videos", "All"}, "Recent References")

    combo_set_items(items.imgAspectCombo, {"16:9", "9:16", "1:1"}, App.Config.image_aspect_ratio)
    combo_set_items(items.imgSizeCombo, {"1K", "2K", "4K"}, App.Config.image_size)

    combo_set_items(items.movieAspectCombo, {"16:9", "9:16"}, App.Config.movie_aspect_ratio)
    combo_set_items(items.movieResolutionCombo, {"720p", "1080p", "4k"}, App.Config.movie_resolution)
    combo_set_items(items.movieDurationCombo, {"4", "6", "8"}, App.Config.movie_duration)
    combo_set_items(items.movieRefModeCombo, {movie_ref_mode_display("frames"), movie_ref_mode_display("ingredients")}, movie_ref_mode_display(App.Config.movie_ref_mode))

    sync_controls_from_config()
    force_square_buttons()
    refresh_model_combos()
    refresh_gallery_ui()
    refresh_slot_buttons()
    set_widget_visible(items.imgInlineTokenPickerRow, false)
    set_widget_visible(items.movieInlineTokenPickerRow, false)

    items.imgPromptEdit.PlainText = items.imgPromptEdit.PlainText or "Describe your transformation."
    items.moviePromptEdit.PlainText = items.moviePromptEdit.PlainText or "Describe your shot."
    items.movieNegativeEdit.Text = App.Config.movie_negative_prompt or ""

    local start_tab = "image"
    if not App.Config.gemini_api_key or trim(App.Config.gemini_api_key) == "" then
        start_tab = "config"
    end
    show_tab(start_tab)

    function win.On.tabImageBtn.Clicked()
        show_tab("image")
    end
    function win.On.tabMovieBtn.Clicked()
        show_tab("movie")
    end
    function win.On.tabConfigBtn.Clicked()
        show_tab("config")
    end
    function win.On.uiRefreshBtn.Clicked()
        force_square_buttons()
        refresh_gallery_ui()
        refresh_slot_buttons()
        show_tab(App.State.current_tab or "image")
        if App.State.current_tab == "movie" then
            set_movie_status("UI refreshed.")
        else
            set_image_status("UI refreshed.")
        end
    end

    function win.On.cleanRoomWin.Resize(ev)
        local _ = ev
        if App.State.ui_updating or App.State.ui_refreshing then return end
        force_square_buttons()
        refresh_gallery_buttons("image")
        refresh_gallery_buttons("movie")
        refresh_slot_buttons()
    end

    function win.On.imgModelCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local raw = combo_current_text(items.imgModelCombo)
        local selected = display_to_model(raw)
        if selected == App.Config.image_model then return end
        App.Config.image_model = selected
        refresh_model_combos()
        save_settings()
    end

    function win.On.movieModelCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local raw = combo_current_text(items.movieModelCombo)
        local selected = display_to_model(raw)
        if selected == App.Config.movie_model then return end
        App.Config.movie_model = selected
        refresh_model_combos()
        save_settings()
    end

    function win.On.imgRefreshModelsBtn.Clicked()
        apply_config_from_controls()
        local ok1, msg1 = fetch_gemini_models()
        refresh_model_combos()
        if ok1 then
            set_image_status("Image models refreshed.")
        else
            set_image_status(msg1)
        end
    end

    function win.On.movieRefreshModelsBtn.Clicked()
        apply_config_from_controls()
        local ok1, msg1 = fetch_gemini_models()
        refresh_model_combos()
        if ok1 then
            set_movie_status("Movie models refreshed.")
        else
            set_movie_status(msg1)
        end
    end

    function win.On.imgAspectCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = combo_current_text(items.imgAspectCombo)
        if selected == App.Config.image_aspect_ratio then return end
        App.Config.image_aspect_ratio = selected
        save_settings()
    end

    function win.On.imgSizeCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = combo_current_text(items.imgSizeCombo)
        if selected == App.Config.image_size then return end
        App.Config.image_size = selected
        save_settings()
    end

    function win.On.movieAspectCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = combo_current_text(items.movieAspectCombo)
        if selected == App.Config.movie_aspect_ratio then return end
        App.Config.movie_aspect_ratio = selected
        save_settings()
    end

    function win.On.movieRefModeCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = movie_ref_mode_from_text(combo_current_text(items.movieRefModeCombo))
        if selected == App.Config.movie_ref_mode then return end
        App.Config.movie_ref_mode = selected
        refresh_model_combos()
        save_settings()
    end

    function win.On.movieResolutionCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = combo_current_text(items.movieResolutionCombo)
        if selected == App.Config.movie_resolution then return end
        App.Config.movie_resolution = selected
        save_settings()
    end

    function win.On.movieDurationCombo.CurrentIndexChanged()
        if App.State.ui_updating then return end
        local selected = combo_current_text(items.movieDurationCombo)
        if selected == App.Config.movie_duration then return end
        App.Config.movie_duration = selected
        save_settings()
    end

    function win.On.imgGalleryFilterCombo.CurrentIndexChanged()
        App.State.image_gallery_index = 1
        App.State.image_gallery_offset = 1
        refresh_gallery_ui()
    end

    function win.On.movieGalleryFilterCombo.CurrentIndexChanged()
        App.State.movie_gallery_index = 1
        App.State.movie_gallery_offset = 1
        refresh_gallery_ui()
    end

    -- ▲/▼ inline gallery step buttons
    local function gallery_step(tab, dir)
        local list     = (tab == "movie") and App.State.movie_gallery_list or App.State.image_gallery_list
        local page     = (tab == "movie") and (App.State.movie_gallery_page_size or 4)
                         or (App.State.image_gallery_page_size or 4)
        local max_off  = math.max(1, #list - page + 1)
        local off_key  = (tab == "movie") and "movie_gallery_offset" or "image_gallery_offset"
        local cur      = App.State[off_key] or 1
        local new_off  = math.max(1, math.min(max_off, cur + dir))
        App.State[off_key] = new_off
        refresh_gallery_buttons(tab)
    end

    function win.On.imgGalleryScrollUp.Clicked()   gallery_step("image", -1) end
    function win.On.imgGalleryScrollDn.Clicked()   gallery_step("image",  1) end
    function win.On.movieGalleryScrollUp.Clicked() gallery_step("movie", -1) end
    function win.On.movieGalleryScrollDn.Clicked() gallery_step("movie",  1) end

    -- Browse Gallery window (calls via App._galFn to avoid adding upvalues to build_ui)
    function win.On.imgGalleryBrowseBtn.Clicked()   App._galFn.browse("image") end
    function win.On.movieGalleryBrowseBtn.Clicked() App._galFn.browse("movie") end

    -- Reveal in Finder from inline gallery
    function win.On.imgGalleryFindBtn.Clicked()
        local _, msg = App._galFn.find("image")
        set_image_status(msg)
    end
    function win.On.movieGalleryFindBtn.Clicked()
        local _, msg = App._galFn.find("movie")
        set_movie_status(msg)
    end

    for i = 1, (App.State.gallery_button_count or 12) do
        local idx = i
        local img_id = "imgGalleryBtn" .. tostring(i)
        local movie_id = "movieGalleryBtn" .. tostring(i)
        if items[img_id] then
            win.On[img_id].Clicked = function()
                local _, m = set_gallery_selection_visible("image", idx)
                set_image_status(m)
            end
        end
        if items[movie_id] then
            win.On[movie_id].Clicked = function()
                local _, m = set_gallery_selection_visible("movie", idx)
                set_movie_status(m)
            end
        end
    end

    -- NOTE: WheelEvent / trackpad scroll events do NOT fire in Fusion's UIManager.
    -- Confirmed by direct testing - no wheel events are accessible from Lua scripts.
    -- Gallery scrolling is only possible via the scrollbar widget itself.

    local function bind_context_for_control(id, path_fn, status_fn, title_fn)
        if not items[id] then return end
        win.On[id] = win.On[id] or {}
        local last_open_ms = 0
        local function run_ctx()
            local t = now_ms()
            if (t - last_open_ms) < 300 then
                return
            end
            last_open_ms = t
            local p = path_fn and path_fn() or nil
            local title = title_fn and title_fn() or id
            show_media_context_menu(p, title, status_fn)
        end

        local prev_mouse = win.On[id].MousePress
        win.On[id].MousePress = function(ev)
            if is_right_click_event(ev) then
                run_ctx()
                return true
            end
            if prev_mouse then
                return prev_mouse(ev)
            end
        end
        local prev_release = win.On[id].MouseRelease
        win.On[id].MouseRelease = function(ev)
            if is_right_click_event(ev) then
                run_ctx()
                return true
            end
            if prev_release then
                return prev_release(ev)
            end
        end
        win.On[id].ContextMenu = function(ev)
            local _ = ev
            run_ctx()
        end
        win.On[id].RightClicked = function(ev)
            local _ = ev
            run_ctx()
        end
    end

    for i = 1, (App.State.gallery_button_count or 12) do
        local idx = i
        bind_context_for_control(
            "imgGalleryBtn" .. tostring(i),
            function() return gallery_path_from_visible_slot("image", idx) end,
            set_image_status,
            function() return "Image Gallery " .. tostring(idx) end
        )
        bind_context_for_control(
            "movieGalleryBtn" .. tostring(i),
            function() return gallery_path_from_visible_slot("movie", idx) end,
            set_movie_status,
            function() return "Movie Gallery " .. tostring(idx) end
        )
    end

    for i = 1, 8 do
        local idx = i
        bind_context_for_control(
            "imgRefBtn" .. tostring(i),
            function() return App.State.image_refs[idx] end,
            set_image_status,
            function() return "Image Ref Slot " .. tostring(idx) end
        )
        bind_context_for_control(
            "movieRefBtn" .. tostring(i),
            function() return App.State.movie_refs[idx] end,
            set_movie_status,
            function() return "Movie Ref Slot " .. tostring(idx) end
        )
    end

    bind_context_for_control("imgResultBtn", function() return App.State.last_image_path end, set_image_status, function() return "Image Result" end)
    bind_context_for_control("movieResultBtn", function() return App.State.last_movie_path end, set_movie_status, function() return "Movie Result" end)

    function win.On.imgGalleryUseBtn.Clicked()
        local ok, msg = use_selected_gallery_as_ref("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryUseBtn.Clicked()
        local ok, msg = use_selected_gallery_as_ref("movie")
        set_movie_status(msg)
    end

    -- Undo last cleared ref slot
    local function do_undo_ref()
        local u = App.State.last_cleared_ref
        if not u or not u.path or not file_exists(u.path) then
            set_image_status("Nothing to undo.")
            return
        end
        if u.tab == "movie" then
            App.State.movie_refs[u.idx] = u.path
        else
            App.State.image_refs[u.idx] = u.path
        end
        App.State.last_cleared_ref = nil
        refresh_slot_buttons()
        set_image_status("Restored slot " .. tostring(u.idx))
    end
    function win.On.imgUndoRefBtn.Clicked()   do_undo_ref() end
    function win.On.movieUndoRefBtn.Clicked() do_undo_ref() end

    -- Open result in Preview (images) or QuickTime (movies)
    function win.On.imgOpenResultBtn.Clicked()
        local p = App.State.last_image_path
        if p and file_exists(p) then
            open_file(p)
        else
            set_image_status("No result to open.")
        end
    end
    function win.On.movieOpenResultBtn.Clicked()
        local p = App.State.last_movie_path
        if p and file_exists(p) then
            open_file(p)
        else
            set_movie_status("No result to open.")
        end
    end

    function win.On.imgGalleryDeleteBtn.Clicked()
        local ok, msg = delete_selected_gallery("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryDeleteBtn.Clicked()
        local ok, msg = delete_selected_gallery("movie")
        set_movie_status(msg)
    end

    function win.On.imgGalleryPasteBtn.Clicked()
        local ok, msg = paste_clipboard_into("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryPasteBtn.Clicked()
        local ok, msg = paste_clipboard_into("movie")
        set_movie_status(msg)
    end

    function win.On.imgGalleryLoadBtn.Clicked()
        local ok, msg = load_settings_from_gallery("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryLoadBtn.Clicked()
        local ok, msg = load_settings_from_gallery("movie")
        set_movie_status(msg)
    end

    function win.On.imgGalleryAddPoolBtn.Clicked()
        local ok, msg = add_selected_gallery_to_pool("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryAddPoolBtn.Clicked()
        local ok, msg = add_selected_gallery_to_pool("movie")
        set_movie_status(msg)
    end

    local function on_img_ref_clicked(i)
        local removed = clear_ref_slot("image", i)
        refresh_slot_buttons()
        if removed then
            set_image_status("Cleared slot " .. tostring(i))
        elseif i > (App.State.image_max_refs or 0) then
            set_image_status("Slot " .. tostring(i) .. " is unsupported for current model.")
        else
            set_image_status("Slot " .. tostring(i) .. " is already empty.")
        end
    end

    local function on_movie_ref_clicked(i)
        local removed = clear_ref_slot("movie", i)
        refresh_slot_buttons()
        if removed then
            set_movie_status("Cleared movie slot " .. tostring(i))
        elseif i > (App.State.movie_max_refs or 0) then
            set_movie_status("Slot " .. tostring(i) .. " is unsupported for current model.")
        else
            set_movie_status("Slot " .. tostring(i) .. " is already empty.")
        end
    end

    function win.On.imgRefBtn1.Clicked() on_img_ref_clicked(1) end
    function win.On.imgRefBtn2.Clicked() on_img_ref_clicked(2) end
    function win.On.imgRefBtn3.Clicked() on_img_ref_clicked(3) end
    function win.On.imgRefBtn4.Clicked() on_img_ref_clicked(4) end
    function win.On.imgRefBtn5.Clicked() on_img_ref_clicked(5) end
    function win.On.imgRefBtn6.Clicked() on_img_ref_clicked(6) end
    function win.On.imgRefBtn7.Clicked() on_img_ref_clicked(7) end
    function win.On.imgRefBtn8.Clicked() on_img_ref_clicked(8) end

    function win.On.movieRefBtn1.Clicked() on_movie_ref_clicked(1) end
    function win.On.movieRefBtn2.Clicked() on_movie_ref_clicked(2) end
    function win.On.movieRefBtn3.Clicked() on_movie_ref_clicked(3) end
    function win.On.movieRefBtn4.Clicked() on_movie_ref_clicked(4) end
    function win.On.movieRefBtn5.Clicked() on_movie_ref_clicked(5) end
    function win.On.movieRefBtn6.Clicked() on_movie_ref_clicked(6) end
    function win.On.movieRefBtn7.Clicked() on_movie_ref_clicked(7) end
    function win.On.movieRefBtn8.Clicked() on_movie_ref_clicked(8) end

    local function read_edit_text(edit)
        return tostring((edit and (edit.PlainText or edit.Text)) or "")
    end

    local function write_edit_text(edit, txt)
        if not edit then return end
        pcall(function() edit.PlainText = txt end)
        pcall(function() edit.Text = txt end)
    end

    local function get_edit_cursor_pos(edit)
        if not edit then return nil end
        local pos = nil
        pcall(function() pos = tonumber(edit.CursorPosition) end)
        if pos == nil then
            pcall(function() pos = tonumber(edit.cursorPosition) end)
        end
        if pos == nil then
            pcall(function() pos = tonumber(edit.CaretPosition) end)
        end
        if pos == nil then
            pcall(function()
                local cp = edit:GetCursorPosition()
                if type(cp) == "table" then
                    pos = tonumber(cp[1]) or tonumber(cp[2]) or tonumber(cp.pos) or tonumber(cp.position)
                else
                    pos = tonumber(cp)
                end
            end)
        end
        return pos
    end

    local function set_edit_cursor_pos(edit, pos)
        if not edit or pos == nil then return end
        pcall(function() edit.CursorPosition = pos end)
        pcall(function() edit.cursorPosition = pos end)
        pcall(function() edit.CaretPosition = pos end)
        pcall(function() edit:SetCursorPosition(pos) end)
    end

    local function remember_edit_cursor(edit, key)
        local pos = get_edit_cursor_pos(edit)
        if pos ~= nil then
            App.State[key] = pos
        end
    end

    local function cursor_has_at_trigger(edit, cursor_key)
        local txt = read_edit_text(edit)
        local pos = get_edit_cursor_pos(edit)
        if pos == nil then
            pos = tonumber(App.State[cursor_key])
        end
        if pos == nil then return false end
        pos = math.floor(pos)
        local ch_a = (pos >= 1 and pos <= #txt) and txt:sub(pos, pos) or ""
        local ch_b = (pos - 1 >= 1 and (pos - 1) <= #txt) and txt:sub(pos - 1, pos - 1) or ""
        return (ch_a == "@") or (ch_b == "@")
    end

    local function inline_token_options(tab)
        local out = {}
        if tab == "movie" then
            local max_slots = math.min(3, App.State.movie_max_refs or 3)
            for i = 1, max_slots do
                if App.State.movie_refs[i] and App.State.movie_refs[i] ~= "" then
                    out[#out + 1] = "@image" .. tostring(i)
                end
            end
            return out
        end
        local max_slots = math.min(8, App.State.image_max_refs or 8)
        for i = 1, max_slots do
            if App.State.image_refs[i] and App.State.image_refs[i] ~= "" then
                out[#out + 1] = "@image" .. tostring(i)
            end
        end
        return out
    end

    local function set_inline_picker_visible(tab, visible)
        local row = items[(tab == "movie") and "movieInlineTokenPickerRow" or "imgInlineTokenPickerRow"]
        if row then
            set_widget_visible(row, visible)
        end
    end

    local function refresh_inline_picker_options(tab)
        local combo = items[(tab == "movie") and "movieInlineTokenCombo" or "imgInlineTokenCombo"]
        if not combo then return 0 end
        local opts = inline_token_options(tab)
        combo_set_items(combo, opts, opts[1])
        return #opts
    end

    local function maybe_show_inline_picker(tab, edit, cursor_key)
        if cursor_has_at_trigger(edit, cursor_key) then
            local count = refresh_inline_picker_options(tab)
            set_inline_picker_visible(tab, count > 0)
        else
            set_inline_picker_visible(tab, false)
        end
    end

    local function insert_token_at_cursor(edit, token, cursor_key)
        if not edit then return end
        token = trim(token or "")
        if token == "" then return end

        local direct_ok = false
        local direct_methods = {
            function() edit:InsertPlainText(token) end,
            function() edit:insertPlainText(token) end,
            function() edit:InsertText(token) end,
            function() edit:Insert(token) end
        }
        for _, fn in ipairs(direct_methods) do
            local ok = pcall(fn)
            if ok then
                direct_ok = true
                break
            end
        end
        if direct_ok then
            remember_edit_cursor(edit, cursor_key)
            return
        end

        local txt = read_edit_text(edit)
        local pos = get_edit_cursor_pos(edit)
        if pos == nil then
            pos = tonumber(App.State[cursor_key])
        end
        if pos == nil then
            pos = #txt
        end
        pos = math.max(0, math.min(#txt, math.floor(pos)))

        local left = txt:sub(1, pos)
        local right = txt:sub(pos + 1)
        local insertion = token
        local left_char = left:sub(-1)
        local right_char = right:sub(1, 1)
        if left ~= "" and not left_char:match("[%s%(%[%{@]") then
            insertion = " " .. insertion
        end
        if right ~= "" and not right_char:match("[%s%.,!%?;:%)%]%}]") then
            insertion = insertion .. " "
        end

        write_edit_text(edit, left .. insertion .. right)
        local new_pos = #left + #insertion
        set_edit_cursor_pos(edit, new_pos)
        App.State[cursor_key] = new_pos
    end

    function win.On.imgPromptEdit.TextChanged()
        remember_edit_cursor(items.imgPromptEdit, "image_prompt_cursor")
        maybe_show_inline_picker("image", items.imgPromptEdit, "image_prompt_cursor")
    end

    function win.On.moviePromptEdit.TextChanged()
        remember_edit_cursor(items.moviePromptEdit, "movie_prompt_cursor")
        maybe_show_inline_picker("movie", items.moviePromptEdit, "movie_prompt_cursor")
    end

    function win.On.imgPromptEdit.CursorPositionChanged()
        remember_edit_cursor(items.imgPromptEdit, "image_prompt_cursor")
        maybe_show_inline_picker("image", items.imgPromptEdit, "image_prompt_cursor")
    end

    function win.On.moviePromptEdit.CursorPositionChanged()
        remember_edit_cursor(items.moviePromptEdit, "movie_prompt_cursor")
        maybe_show_inline_picker("movie", items.moviePromptEdit, "movie_prompt_cursor")
    end

    local function insert_from_inline_picker(tab)
        local combo = items[(tab == "movie") and "movieInlineTokenCombo" or "imgInlineTokenCombo"]
        local edit = items[(tab == "movie") and "moviePromptEdit" or "imgPromptEdit"]
        local cursor_key = (tab == "movie") and "movie_prompt_cursor" or "image_prompt_cursor"
        if not combo or not edit then return end
        local token = combo_current_text(combo):match("@image%d+")
        if not token then return end
        local token_to_insert = token
        if cursor_has_at_trigger(edit, cursor_key) then
            token_to_insert = token:gsub("^@", "")
        end
        insert_token_at_cursor(edit, token_to_insert, cursor_key)
        set_inline_picker_visible(tab, false)
    end

    function win.On.imgInlineTokenInsertBtn.Clicked()
        insert_from_inline_picker("image")
    end

    function win.On.movieInlineTokenInsertBtn.Clicked()
        insert_from_inline_picker("movie")
    end

    function win.On.imgToken1Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image1", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken2Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image2", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken3Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image3", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken4Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image4", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken5Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image5", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken6Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image6", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken7Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image7", "image_prompt_cursor"); set_inline_picker_visible("image", false) end
    function win.On.imgToken8Btn.Clicked() insert_token_at_cursor(items.imgPromptEdit, "@image8", "image_prompt_cursor"); set_inline_picker_visible("image", false) end

    function win.On.movieToken1Btn.Clicked() insert_token_at_cursor(items.moviePromptEdit, "@image1", "movie_prompt_cursor"); set_inline_picker_visible("movie", false) end
    function win.On.movieToken2Btn.Clicked() insert_token_at_cursor(items.moviePromptEdit, "@image2", "movie_prompt_cursor"); set_inline_picker_visible("movie", false) end
    function win.On.movieToken3Btn.Clicked() insert_token_at_cursor(items.moviePromptEdit, "@image3", "movie_prompt_cursor"); set_inline_picker_visible("movie", false) end

    function win.On.imgGrabBtn.Clicked()
        local ok, msg = grab_current_frame_into("image")
        set_image_status(msg)
    end

    function win.On.movieGrabBtn.Clicked()
        local ok, msg = grab_current_frame_into("movie")
        set_movie_status(msg)
    end

    function win.On.imgClearBtn.Clicked()
        clear_all_refs("image")
        refresh_slot_buttons()
        set_image_status("Cleared all slots.")
    end

    function win.On.movieClearBtn.Clicked()
        clear_all_refs("movie")
        refresh_slot_buttons()
        set_movie_status("Cleared all movie slots.")
    end

    function win.On.imgGenerateBtn.Clicked()
        apply_config_from_controls()
        App.Config.image_model = display_to_model(combo_current_text(items.imgModelCombo))
        App.Config.image_aspect_ratio = combo_current_text(items.imgAspectCombo)
        App.Config.image_size = combo_current_text(items.imgSizeCombo)
        save_settings()

        local prompt = trim(items.imgPromptEdit.PlainText or items.imgPromptEdit.Text or "")
        if prompt == "" then
            set_image_status("Prompt is required.")
            return
        end

        local refs = current_image_refs()
        for _, p in ipairs(refs) do
            add_history("ref", p)
        end
        App.State.image_generating = true
        App.State.last_image_path = nil
        refresh_slot_buttons()
        set_image_status("Starting generation...")
        -- Drain pending Qt events so the status label actually repaints before
        -- we block the event loop for the duration of the API call.
        pcall(function() App.Core.disp:StepLoop() end)
        pcall(function() App.Core.ui:StepLoop() end)

        local ok, result = generate_image_gemini(prompt, refs)
        App.State.image_generating = false

        if ok then
            App.State.last_image_path = result
            refresh_gallery_ui()
            refresh_slot_buttons()
            set_image_status("Success:\n" .. tostring(result))
        else
            set_image_status("Failed:\n" .. tostring(result))
            refresh_slot_buttons()
        end
    end

    function win.On.movieGenerateBtn.Clicked()
        apply_config_from_controls()
        App.Config.movie_model = display_to_model(combo_current_text(items.movieModelCombo))
        App.Config.movie_ref_mode = movie_ref_mode_from_text(combo_current_text(items.movieRefModeCombo))
        App.Config.movie_aspect_ratio = combo_current_text(items.movieAspectCombo)
        App.Config.movie_resolution = combo_current_text(items.movieResolutionCombo)
        App.Config.movie_duration = combo_current_text(items.movieDurationCombo)
        App.Config.movie_negative_prompt = trim(items.movieNegativeEdit.Text or "")
        save_settings()

        local prompt = trim(items.moviePromptEdit.PlainText or items.moviePromptEdit.Text or "")
        if prompt == "" then
            set_movie_status("Prompt is required.")
            return
        end

        local refs = current_movie_refs()
        for _, p in ipairs(refs) do
            add_history("ref", p)
        end

        App.State.movie_generating = true
        App.State.last_movie_path = nil
        refresh_slot_buttons()
        set_movie_status("Starting movie generation...")
        log("Using Veo endpoint: " .. trim(App.Config.gemini_api_url) .. "/models/" .. App.Config.movie_model .. ":predictLongRunning")
        -- Drain pending Qt events so the status label actually repaints before
        -- we block the event loop for the duration of the API call.
        pcall(function() App.Core.disp:StepLoop() end)
        pcall(function() App.Core.ui:StepLoop() end)

        local ok, result = generate_movie_gemini(prompt, refs)
        App.State.movie_generating = false
        if ok then
            App.State.last_movie_path = result
            refresh_gallery_ui()
            refresh_slot_buttons()
            set_movie_status("Success:\n" .. tostring(result))
        else
            local hint = parse_veo_blocking_hint(result)
            if hint then
                set_movie_status("Failed:\n" .. tostring(hint))
            else
                set_movie_status("Failed:\n" .. tostring(result))
            end
            refresh_slot_buttons()
        end
    end

    function win.On.imgKeepEditingBtn.Clicked()
        local ok, msg = keep_editing("image")
        set_image_status(msg)
    end

    function win.On.movieKeepEditingBtn.Clicked()
        local ok, msg = keep_editing("movie")
        set_movie_status(msg)
    end

    function win.On.movieExtendBtn.Clicked()
        local uri = App.State.last_movie_uri
        if not uri or uri == "" then
            set_movie_status("No extendable movie result. Generate a movie first (URI required for extension).")
            return
        end

        apply_config_from_controls()
        App.Config.movie_model = display_to_model(combo_current_text(items.movieModelCombo))
        save_settings()

        local prompt = trim(items.moviePromptEdit.PlainText or items.moviePromptEdit.Text or "")
        if prompt == "" then
            set_movie_status("Prompt is required for extension.")
            return
        end

        App.State.movie_generating = true
        App.State.last_movie_path = nil
        refresh_slot_buttons()
        set_movie_status("Starting movie extension...")
        pcall(function() App.Core.disp:StepLoop() end)
        pcall(function() App.Core.ui:StepLoop() end)

        local ok, result = generate_movie_extension_gemini(prompt, uri)
        App.State.movie_generating = false
        if ok then
            App.State.last_movie_path = result
            refresh_gallery_ui()
            refresh_slot_buttons()
            set_movie_status("Extension complete:\n" .. tostring(result))
        else
            local hint = parse_veo_blocking_hint(result)
            set_movie_status("Extension failed:\n" .. tostring(hint or result))
            refresh_slot_buttons()
        end
    end

    function win.On.imgAddPoolBtn.Clicked()
        if not App.State.last_image_path or not file_exists(App.State.last_image_path) then
            set_image_status("No image result to import.")
            return
        end
        local ok, imported_or_err, staged = stage_and_import(App.State.last_image_path)
        if ok then
            set_image_status("Added to Media Pool:\n" .. tostring(staged or App.State.last_image_path))
        else
            set_image_status("Import failed:\n" .. tostring(imported_or_err))
        end
    end

    function win.On.movieAddPoolBtn.Clicked()
        if not App.State.last_movie_path or not file_exists(App.State.last_movie_path) then
            set_movie_status("No movie result to import.")
            return
        end
        local ok, imported_or_err, staged = stage_and_import(App.State.last_movie_path)
        if ok then
            set_movie_status("Added movie to Media Pool:\n" .. tostring(staged or App.State.last_movie_path))
        else
            set_movie_status("Import failed:\n" .. tostring(imported_or_err))
        end
    end

    function win.On.moviePlayBtn.Clicked()
        if not App.State.last_movie_path or not file_exists(App.State.last_movie_path) then
            set_movie_status("No movie result to open.")
            return
        end
        run_shell_ok("open " .. shell_quote(App.State.last_movie_path) .. " >/dev/null 2>&1")
        set_movie_status("Opened movie:\n" .. tostring(App.State.last_movie_path))
    end

    function win.On.imgResultBtn.Clicked()
        if App.State.image_generating then
            set_image_status("Generation in progress...")
            return
        end
        if App.State.last_image_path and file_exists(App.State.last_image_path) then
            -- Re-render thumbnail to make sure it stays visible
            set_button_image(items.imgResultBtn, App.State.last_image_path, "Result", "image")
            set_button_square_style(items.imgResultBtn, "border: 1px solid #6B6F85;")
            if items.imgResultHintLabel then items.imgResultHintLabel.Text = "Click to view" end
            open_in_preview(App.State.last_image_path)
        else
            set_image_status("No image result to open.")
        end
    end

    function win.On.movieResultBtn.Clicked()
        if App.State.movie_generating then
            set_movie_status("Generation in progress...")
            return
        end
        if App.State.last_movie_path and file_exists(App.State.last_movie_path) then
            local poster = load_preview_for_video(App.State.last_movie_path, App.Config.result_preview_max, "movie_result")
            -- Re-render thumbnail to keep it visible, then open externally
            set_button_image(items.movieResultBtn, poster or App.State.last_movie_path, "Video Ready", "video")
            set_button_square_style(items.movieResultBtn, "border: 1px solid #6B6F85;")
            if items.movieResultHintLabel then items.movieResultHintLabel.Text = "Click to view" end
            open_in_preview(App.State.last_movie_path)
        end
    end

    function win.On.cfgSaveBtn.Clicked()
        apply_config_from_controls()
        save_settings()
        set_config_status("Configuration saved.")
    end

    function win.On.cfgGeminiTestBtn.Clicked()
        apply_config_from_controls()
        local ok, msg = test_gemini_key()
        set_config_status(msg)
    end

    function win.On.cfgSaveDirBrowseBtn.Clicked()
        local picked = App.Core.fusion and App.Core.fusion:RequestDir(App.Config.output_dir)
        if picked and picked ~= "" then
            if picked:sub(-1) ~= "/" then picked = picked .. "/" end
            items.cfgSaveDirEdit.Text = picked
            apply_config_from_controls()
            save_settings()
        end
    end

    function win.On.cfgPoolDirBrowseBtn.Clicked()
        local picked = App.Core.fusion and App.Core.fusion:RequestDir(App.Config.media_pool_dir)
        if picked and picked ~= "" then
            if picked:sub(-1) ~= "/" then picked = picked .. "/" end
            items.cfgPoolDirEdit.Text = picked
            apply_config_from_controls()
            save_settings()
        end
    end

    local function open_readme()
        local readme = "https://github.com/Chewboctopus/Black-Magic-Banana#readme"
        local cmd = "open " .. shell_quote(readme) .. " >/dev/null 2>&1"
        run_shell_ok(cmd)
        set_config_status("Opened README in browser.")
    end

    local function open_api_key_page()
        local url = "https://aistudio.google.com/api-keys"
        local ok = run_shell_ok("open " .. shell_quote(url) .. " >/dev/null 2>&1")
        if ok then
            set_config_status("Opened Gemini API key page.")
        else
            set_config_status("Failed to open browser for API key page.")
        end
    end

    local function check_for_updates()
        set_config_status("Checking GitHub for updates...")
        local url = "https://raw.githubusercontent.com/Chewboctopus/Black-Magic-Banana/main/Black%20Magic%20Banana.lua"
        local status, body, err = curl_get(url, {}, 5)
        if status == 200 and body ~= "" then
            local remote_version = body:match('script_version%s*=%s*"([^"]+)"')
            if not remote_version then
                set_config_status("Could not parse remote version.")
            elseif remote_version ~= App.Config.script_version then
                set_config_status("Update Available! (v" .. remote_version .. "). See README to install.")
            else
                set_config_status("You are up to date! (v" .. remote_version .. ")")
            end
        else
            set_config_status("Update check failed (HTTP " .. tostring(status) .. ").")
        end
    end

    function win.On.cfgCheckUpdatesBtn.Clicked()
        check_for_updates()
    end

    function win.On.cfgOpenReadmeBtn.Clicked()
        open_readme()
    end

    function win.On.cfgGetApiKeyBtn.Clicked()
        open_api_key_page()
    end

    function win.On.imgCloseBtn.Clicked()
        App.Core.disp:ExitLoop()
    end

    function win.On.movieCloseBtn.Clicked()
        App.Core.disp:ExitLoop()
    end

    -- When the window regains focus (e.g. after Preview app closes), re-render
    -- the result button so the image thumbnail is not lost
    function win.On.cleanRoomWin.WindowActivate(ev)
        local _ = ev
        if App.State.last_image_path and file_exists(App.State.last_image_path) and not App.State.image_generating then
            pcall(function()
                set_button_image(items.imgResultBtn, App.State.last_image_path, "Result", "image")
                set_button_square_style(items.imgResultBtn, "border: 1px solid #6B6F85;")
                if items.imgResultHintLabel then items.imgResultHintLabel.Text = "Click to view" end
            end)
        end
        if App.State.last_movie_path and file_exists(App.State.last_movie_path) and not App.State.movie_generating then
            pcall(function()
                local poster = load_preview_for_video(App.State.last_movie_path, App.Config.result_preview_max, "movie_result")
                set_button_image(items.movieResultBtn, poster or App.State.last_movie_path, "Video Ready", "video")
                set_button_square_style(items.movieResultBtn, "border: 1px solid #6B6F85;")
                if items.movieResultHintLabel then items.movieResultHintLabel.Text = "Click to view" end
            end)
        end
    end

    function win.On.cleanRoomWin.Close()
        App.Core.disp:ExitLoop()
    end

    return win
end

local function headless_test()
    log("No UI context found; headless mode.")
    local prompt = "Describe your transformation."
    local ok, result = generate_image_gemini(prompt, {})
    if ok then
        log("Done: " .. tostring(result))
    else
        log("Failed: " .. tostring(result))
    end
end

local function main()
    log("Starting " .. App.Config.script_version)

    load_settings()
    apply_storage_defaults()
    mkdir_p(App.Config.refs_dir)
    mkdir_p(App.Config.temp_dir)
    mkdir_p(App.Config.output_dir)
    mkdir_p(App.Config.media_pool_dir)
    mkdir_p(App.Config.debug_dir)
    load_history()

    -- Warn early if no API key is configured so users aren't confused by the
    -- first Generate call failing silently with an auth error.
    if trim(App.Config.gemini_api_key) == "" then
        log("WARNING: No Gemini API key found. Set the DAVINCI_IMAGE_AI_API_KEY environment variable or enter a key in the Configuration tab.")
    end

    local ok_g, msg_g = fetch_gemini_models()
    if not ok_g then log(msg_g) end

    if App.Core.disp and App.Core.ui then
        local win = build_ui()
        if win then
            -- Set geometry before Show() to override any cached shape from prior sessions.
            -- We also set it after Show() as some Resolve versions only honor it post-show.
            pcall(function() win.Geometry = {64, 32, 1620, 900} end)
            win:Show()
            pcall(function() win.Geometry = {64, 32, 1620, 900} end)
            App.Core.disp:RunLoop()
            win:Hide()
            save_settings()
            save_history()
            return
        end
    end

    headless_test()
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
    log("Fatal error:\n" .. tostring(err))
end
