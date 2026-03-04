-- DaVinci Image AI (Clean Room) - Rebuild Baseline
-- Rebuilt from conversation requirements after corrupted intermediate versions.

math.randomseed(os.time())

local App = {}

App.Config = {
    script_name = "DaVinci Image AI (Clean Room)",
    script_version = "0.4.0-rebuild",
    temp_dir = "/tmp/davinci-image-ai-clean/",
    output_dir = "/tmp/davinci-image-ai-clean/output/",
    media_pool_dir = "",

    gemini_api_url = "https://generativelanguage.googleapis.com/v1beta",
    gemini_api_key = os.getenv("DAVINCI_IMAGE_AI_API_KEY") or "",

    openai_api_url = "https://api.openai.com/v1",
    openai_api_key = "",

    image_provider = "gemini",
    image_model = "gemini-2.5-flash-image",
    image_aspect_ratio = "16:9",
    image_size = "1K",

    movie_model = "veo-3.1-generate-preview",
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
    settings_path = (os.getenv("HOME") or "") .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/cleanroom_settings.conf",
    history_path = (os.getenv("HOME") or "") .. "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/DaVinci Banana_v000/DaVinci Banana/cleanroom_history.conf",
    startup_log = "/tmp/davinci-image-ai-clean/startup.log"
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

    preview_cache = {},

    history = {},

    image_gallery_list = {},
    movie_gallery_list = {},
    image_gallery_index = 1,
    movie_gallery_index = 1,

    image_models = {},
    movie_models = {},
    openai_image_models = {},

    active_image_provider = "gemini"
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
    os.execute("mkdir -p '/tmp/davinci-image-ai-clean' >/dev/null 2>&1")
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
    return math.floor(os.time() * 1000 + math.random(0, 999))
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

local function has_cmd(cmd)
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

local function unique_path(dir, prefix, ext)
    mkdir_p(dir)
    local base = prefix .. "_" .. tostring(now_ms())
    local path = dir .. base .. "." .. ext
    return path
end

local function build_output_path(kind, ext)
    local base = project_prefix() .. "_" .. timestamp_compact()
    local dir = App.Config.output_dir
    mkdir_p(dir)
    local p = dir .. base .. "." .. ext
    local idx = 1
    while file_exists(p) do
        p = dir .. base .. "_" .. tostring(idx) .. "." .. ext
        idx = idx + 1
    end
    return p
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

local function load_settings()
    local txt = read_file(App.Paths.settings_path, "rb")
    if not txt or txt == "" then return end
    local kv = parse_keyval_lines(txt)

    App.Config.gemini_api_url = kv.gemini_api_url or App.Config.gemini_api_url
    App.Config.gemini_api_key = kv.gemini_api_key or App.Config.gemini_api_key
    App.Config.openai_api_url = kv.openai_api_url or App.Config.openai_api_url
    App.Config.openai_api_key = kv.openai_api_key or App.Config.openai_api_key

    App.Config.output_dir = kv.output_dir or App.Config.output_dir
    App.Config.media_pool_dir = kv.media_pool_dir or App.Config.media_pool_dir

    App.Config.image_provider = kv.image_provider or App.Config.image_provider
    App.Config.image_model = kv.image_model or App.Config.image_model
    App.Config.image_aspect_ratio = kv.image_aspect_ratio or App.Config.image_aspect_ratio
    App.Config.image_size = kv.image_size or App.Config.image_size

    App.Config.movie_model = kv.movie_model or App.Config.movie_model
    App.Config.movie_aspect_ratio = kv.movie_aspect_ratio or App.Config.movie_aspect_ratio
    App.Config.movie_resolution = kv.movie_resolution or App.Config.movie_resolution
    App.Config.movie_duration = kv.movie_duration or App.Config.movie_duration
    App.Config.movie_negative_prompt = kv.movie_negative_prompt or App.Config.movie_negative_prompt
end

local function save_settings()
    local keys = {
        "gemini_api_url", "gemini_api_key", "openai_api_url", "openai_api_key",
        "output_dir", "media_pool_dir",
        "image_provider", "image_model", "image_aspect_ratio", "image_size",
        "movie_model", "movie_aspect_ratio", "movie_resolution", "movie_duration", "movie_negative_prompt"
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

local function parse_http_error_message(body)
    local msg = body:match('"message"%s*:%s*"([^"]+)"')
    if msg and msg ~= "" then
        return msg
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

local function ensure_png(src_path)
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

local IMAGE_MODEL_CAPS = {
    ["gemini-2.5-flash-image"] = {alias = "Nano Banana", max_refs = 8, sizes = {"1K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-3.1-flash-image-preview"] = {alias = "Nano Banana 2", max_refs = 4, sizes = {"1K", "2K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-3-pro-image-preview"] = {alias = "Nano Banana Pro", max_refs = 8, sizes = {"1K", "2K", "4K"}, aspects = {"16:9", "9:16", "1:1"}},
    ["gemini-2.0-flash-exp-image-generation"] = {alias = "Gemini 2 Flash Image", max_refs = 0, sizes = {"1K"}, aspects = {"16:9", "9:16", "1:1"}}
}

local MOVIE_MODEL_CAPS = {
    ["veo-3.1-generate-preview"] = {alias = "Veo 3.1", max_refs = 2, supports_last_frame = true, supports_reference_images = true, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p", "4k"}, durations = {"4", "6", "8"}},
    ["veo-3.1-fast-generate-preview"] = {alias = "Veo 3.1 Fast", max_refs = 1, supports_last_frame = false, supports_reference_images = false, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p"}, durations = {"4", "6", "8"}},
    ["veo-3-generate-preview"] = {alias = "Veo 3", max_refs = 2, supports_last_frame = true, supports_reference_images = false, aspects = {"16:9", "9:16"}, resolutions = {"720p", "1080p", "4k"}, durations = {"4", "6", "8"}},
    ["veo-2"] = {alias = "Veo 2", max_refs = 2, supports_last_frame = true, supports_reference_images = false, aspects = {"16:9", "9:16"}, resolutions = {"720p"}, durations = {"5", "6", "8"}}
}

local DEFAULT_IMAGE_MODELS = {
    "gemini-2.5-flash-image",
    "gemini-3.1-flash-image-preview",
    "gemini-3-pro-image-preview"
}

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

local function set_button_image(btn, path, fallback_text, kind)
    if not btn then return end

    local preview = nil
    if path and path ~= "" and file_exists(path) then
        if kind == "video" or path:lower():match("%.mp4$") or path:lower():match("%.mov$") then
            preview = load_preview_for_video(path, App.Config.result_preview_max, "vprev")
        else
            preview = load_preview_for_image(path, App.Config.ref_preview_max, "iprev")
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
        pcall(function() btn.Icon = nil end)
    end
end

local function get_current_timeline_meta()
    local out = {timeline = "", timecode = "", frame = ""}
    local project, _ = resolve_project_and_pool()
    local timeline = project and project:GetCurrentTimeline()
    if timeline then
        local ok_name, tname = pcall(function() return timeline:GetName() end)
        if ok_name and tname then out.timeline = tostring(tname) end

        local ok_tc, tc = pcall(function() return timeline:GetCurrentTimecode() end)
        if ok_tc and tc then out.timecode = tostring(tc) end

        local ok_fr, fr = pcall(function() return timeline:GetCurrentFrame() end)
        if ok_fr and fr then out.frame = tostring(fr) end
    end
    return out
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

local function refresh_slot_buttons()
    local items = App.State.items
    if not items then return end

    for i = 1, 8 do
        local btn = items["imgRefBtn" .. tostring(i)]
        local p = App.State.image_refs[i]
        if p and p ~= "" then
            set_button_image(btn, p, tostring(i), "image")
        else
            set_button_image(btn, nil, tostring(i), "image")
        end
    end

    for i = 1, 8 do
        local btn = items["movieRefBtn" .. tostring(i)]
        local p = App.State.movie_refs[i]
        if p and p ~= "" then
            set_button_image(btn, p, tostring(i), "image")
        else
            set_button_image(btn, nil, tostring(i), "image")
        end

        local supported = i <= (App.State.movie_max_refs or 0)
        pcall(function()
            if supported then
                btn.StyleSheet = "border: 1px solid #6B6F85;"
            else
                btn.StyleSheet = "border: 2px solid #AA3333; color: #AA3333;"
            end
        end)
    end

    if items.imgResultBtn then
        if App.State.last_image_path and file_exists(App.State.last_image_path) then
            set_button_image(items.imgResultBtn, App.State.last_image_path, "Result", "image")
        else
            set_button_image(items.imgResultBtn, nil, "Result", "image")
        end
    end

    if items.movieResultBtn then
        if App.State.last_movie_path and file_exists(App.State.last_movie_path) then
            local poster = load_preview_for_video(App.State.last_movie_path, App.Config.result_preview_max, "movie_result")
            set_button_image(items.movieResultBtn, poster or App.State.last_movie_path, "Video Ready", "video")
        else
            set_button_image(items.movieResultBtn, nil, "Result", "video")
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
    local caps = IMAGE_MODEL_CAPS[model]
    if not caps then
        App.State.image_max_refs = 4
        items.imgCapsLabel.Text = "Capabilities: refs up to 4 | aspect/size depends on provider"
        return
    end

    App.State.image_max_refs = caps.max_refs or 4
    local aspects = table.concat(caps.aspects or {}, ",")
    local sizes = table.concat(caps.sizes or {}, ",")
    items.imgCapsLabel.Text = "Capabilities: refs up to " .. tostring(App.State.image_max_refs) .. " | aspect: " .. aspects .. " | size: " .. sizes
end

local function refresh_movie_capabilities_label()
    local items = App.State.items
    if not items or not items.movieCapsLabel then return end

    local model = App.Config.movie_model
    local caps = MOVIE_MODEL_CAPS[model]
    if not caps then
        App.State.movie_max_refs = 2
        items.movieCapsLabel.Text = "Capabilities: refs up to 2 | aspect/resolution/duration vary by model"
        return
    end

    App.State.movie_max_refs = caps.max_refs or 2
    local parts = {}
    parts[#parts + 1] = "Capabilities: refs up to " .. tostring(App.State.movie_max_refs)
    parts[#parts + 1] = "aspect: " .. table.concat(caps.aspects or {}, ",")
    parts[#parts + 1] = "resolution: " .. table.concat(caps.resolutions or {}, ",")
    parts[#parts + 1] = "duration: " .. table.concat(caps.durations or {}, ",")
    parts[#parts + 1] = "slot1=first frame"
    if caps.supports_last_frame then
        parts[#parts + 1] = "slot2=last frame"
    elseif caps.supports_reference_images then
        parts[#parts + 1] = "slot2=reference"
    else
        parts[#parts + 1] = "slot2 unsupported"
    end
    items.movieCapsLabel.Text = table.concat(parts, " | ")
end

local function sync_controls_from_config()
    local items = App.State.items
    if not items then return end

    items.cfgGeminiUrlEdit.Text = App.Config.gemini_api_url
    items.cfgGeminiKeyEdit.Text = App.Config.gemini_api_key
    items.cfgOpenAIUrlEdit.Text = App.Config.openai_api_url
    items.cfgOpenAIKeyEdit.Text = App.Config.openai_api_key
    items.cfgSaveDirEdit.Text = App.Config.output_dir
    items.cfgPoolDirEdit.Text = App.Config.media_pool_dir

    combo_set_items(items.imgProviderCombo, {"gemini", "openai"}, App.Config.image_provider)
end

local function apply_config_from_controls()
    local items = App.State.items
    if not items then return end

    App.Config.gemini_api_url = trim(items.cfgGeminiUrlEdit.Text or App.Config.gemini_api_url)
    App.Config.gemini_api_key = trim(items.cfgGeminiKeyEdit.Text or App.Config.gemini_api_key)
    App.Config.openai_api_url = trim(items.cfgOpenAIUrlEdit.Text or App.Config.openai_api_url)
    App.Config.openai_api_key = trim(items.cfgOpenAIKeyEdit.Text or App.Config.openai_api_key)

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

    local provider = combo_current_text(items.imgProviderCombo)
    if provider ~= "" then
        App.Config.image_provider = provider
    end
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
    local msg = parse_http_error_message(body)
    if trim(msg) == "" then msg = trim(err) end
    return false, "Gemini key test failed: HTTP " .. tostring(status) .. " " .. msg
end

local function test_openai_key()
    local url = trim(App.Config.openai_api_url)
    if url == "" then
        return false, "OpenAI API URL is required."
    end
    if trim(App.Config.openai_api_key) == "" then
        return false, "OpenAI API key is required."
    end

    local req = url .. "/models"
    local status, body, err = curl_get(req, {"Authorization: Bearer " .. App.Config.openai_api_key}, 60)
    if status >= 200 and status < 300 then
        return true, "OpenAI key test passed."
    end
    local msg = parse_http_error_message(body)
    if trim(msg) == "" then msg = trim(err) end
    return false, "OpenAI key test failed: HTTP " .. tostring(status) .. " " .. msg
end

local function fetch_gemini_models()
    local key = trim(App.Config.gemini_api_key)
    if key == "" then
        return false, "Gemini API key is required to refresh models."
    end
    local req = trim(App.Config.gemini_api_url) .. "/models?key=" .. urlencode(key)
    local status, body, err = curl_get(req, nil, 90)
    if status < 200 or status >= 300 then
        local msg = parse_http_error_message(body)
        if trim(msg) == "" then msg = trim(err) end
        return false, "HTTP " .. tostring(status) .. ". " .. msg
    end

    local image_models = {}
    local movie_models = {}

    for name in body:gmatch('"name"%s*:%s*"models/([^"]+)"') do
        local lower = name:lower()
        if lower:find("veo", 1, true) then
            movie_models[#movie_models + 1] = name
        elseif lower:find("image", 1, true) then
            image_models[#image_models + 1] = name
        end
    end

    if #image_models == 0 then
        image_models = DEFAULT_IMAGE_MODELS
    end
    if #movie_models == 0 then
        movie_models = DEFAULT_MOVIE_MODELS
    end

    App.State.image_models = image_models
    App.State.movie_models = movie_models
    return true, "Gemini models refreshed."
end

local function fetch_openai_image_models()
    local key = trim(App.Config.openai_api_key)
    if key == "" then
        App.State.openai_image_models = {"gpt-image-1"}
        return false, "OpenAI key not set. Using fallback model list."
    end
    local req = trim(App.Config.openai_api_url) .. "/models"
    local status, body, err = curl_get(req, {"Authorization: Bearer " .. key}, 90)
    if status < 200 or status >= 300 then
        App.State.openai_image_models = {"gpt-image-1"}
        local msg = parse_http_error_message(body)
        if trim(msg) == "" then msg = trim(err) end
        return false, "OpenAI models refresh failed: HTTP " .. tostring(status) .. ". " .. msg
    end

    local out = {}
    for id in body:gmatch('"id"%s*:%s*"([^"]+)"') do
        local lower = id:lower()
        if lower:find("image", 1, true) then
            out[#out + 1] = id
        end
    end
    if #out == 0 then out = {"gpt-image-1"} end
    App.State.openai_image_models = out
    return true, "OpenAI models refreshed."
end

local function refresh_model_combos()
    local items = App.State.items
    if not items then return end

    if #App.State.image_models == 0 then
        App.State.image_models = DEFAULT_IMAGE_MODELS
    end
    if #App.State.movie_models == 0 then
        App.State.movie_models = DEFAULT_MOVIE_MODELS
    end
    if #App.State.openai_image_models == 0 then
        App.State.openai_image_models = {"gpt-image-1"}
    end

    local provider = App.Config.image_provider
    local img_display = {}
    if provider == "openai" then
        for _, m in ipairs(App.State.openai_image_models) do
            img_display[#img_display + 1] = m
        end
        if App.Config.image_model == "" then
            App.Config.image_model = img_display[1]
        end
    else
        for _, m in ipairs(App.State.image_models) do
            img_display[#img_display + 1] = image_model_display(m)
        end
        App.Config.image_model = display_to_model(App.Config.image_model)
    end

    combo_set_items(items.imgModelCombo, img_display, provider == "openai" and App.Config.image_model or image_model_display(App.Config.image_model))

    local movie_display = {}
    for _, m in ipairs(App.State.movie_models) do
        movie_display[#movie_display + 1] = movie_model_display(m)
    end
    combo_set_items(items.movieModelCombo, movie_display, movie_model_display(App.Config.movie_model))

    refresh_image_capabilities_label()
    refresh_movie_capabilities_label()
    refresh_slot_buttons()
end

local function fill_ref_slot(tab, path, meta)
    if tab == "movie" then
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
    if tab == "movie" then
        App.State.movie_refs[idx] = nil
        App.State.movie_ref_meta[idx] = nil
    else
        App.State.image_refs[idx] = nil
        App.State.image_ref_meta[idx] = nil
    end
end

local function clear_all_refs(tab)
    if tab == "movie" then
        for i = 1, 8 do
            App.State.movie_refs[i] = nil
            App.State.movie_ref_meta[i] = nil
        end
    else
        for i = 1, 8 do
            App.State.image_refs[i] = nil
            App.State.image_ref_meta[i] = nil
        end
    end
end

local function grab_current_frame_into(tab)
    mkdir_p(App.Config.temp_dir)
    local out = unique_path(App.Config.temp_dir, "grab", "png")
    local ok, err = export_current_frame_png(out)
    if not ok then
        return false, err
    end

    local idx = fill_ref_slot(tab, out, get_current_timeline_meta())
    add_history("ref", out)
    refresh_gallery_ui()
    refresh_slot_buttons()
    return true, "Grabbed frame into slot " .. tostring(idx)
end

local function paste_clipboard_into(tab)
    mkdir_p(App.Config.temp_dir)
    if not has_cmd("pngpaste") then
        return false, "pngpaste is not installed. Install pngpaste to paste clipboard images."
    end
    local out = unique_path(App.Config.temp_dir, "paste", "png")
    local cmd = "pngpaste " .. shell_quote(out) .. " >/dev/null 2>&1"
    if not run_shell_ok(cmd) or not file_exists(out) then
        return false, "Clipboard does not contain an image."
    end

    local idx = fill_ref_slot(tab, out, {timeline = "Clipboard", timecode = "", frame = ""})
    add_history("ref", out)
    refresh_gallery_ui()
    refresh_slot_buttons()
    return true, "Pasted image into slot " .. tostring(idx)
end

local function set_image_provider(provider)
    provider = trim(provider)
    if provider == "" then provider = "gemini" end
    App.Config.image_provider = provider
    App.State.active_image_provider = provider
    refresh_model_combos()
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
    local ok_req, status, body, err = curl_config_request(req, {}, payload_path, App.Config.max_http_seconds)
    log("[cURL stats] " .. tostring(status) .. " size=" .. tostring(#(body or "")))

    if not ok_req then
        return false, "HTTP 000. stderr: " .. tostring(err)
    end
    if status < 200 or status >= 300 then
        return false, "HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body)
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

local function openai_size_from(aspect, quality)
    quality = quality or "1K"
    aspect = aspect or "1:1"
    if quality == "2K" then
        if aspect == "16:9" then return "1536x1024" end
        if aspect == "9:16" then return "1024x1536" end
        return "1024x1024"
    end
    if quality == "4K" then
        if aspect == "16:9" then return "1536x1024" end
        if aspect == "9:16" then return "1024x1536" end
        return "1024x1024"
    end
    if aspect == "16:9" then return "1536x1024" end
    if aspect == "9:16" then return "1024x1536" end
    return "1024x1024"
end

local function generate_image_openai(prompt, refs)
    local key = trim(App.Config.openai_api_key)
    local url = trim(App.Config.openai_api_url)
    local model = trim(App.Config.image_model)

    if key == "" then return false, "OpenAI API key is required." end
    if url == "" then return false, "OpenAI API URL is required." end
    if model == "" then model = "gpt-image-1" end

    if #refs > 0 then
        set_image_status("OpenAI image generation currently ignores reference slots.")
    end

    local payload = "{"
        .. '"model":"' .. json_escape(model) .. '",'
        .. '"prompt":"' .. json_escape(prompt) .. '",'
        .. '"size":"' .. json_escape(openai_size_from(App.Config.image_aspect_ratio, App.Config.image_size)) .. '",'
        .. '"response_format":"b64_json"'
        .. "}"

    local payload_path = unique_path(App.Config.temp_dir, "oai_img", "json")
    write_file(payload_path, payload, "wb")

    local req = url .. "/images/generations"
    local ok_req, status, body, err = curl_config_request(req, {
        "Authorization: Bearer " .. key
    }, payload_path, App.Config.max_http_seconds)
    log("[cURL stats] " .. tostring(status) .. " size=" .. tostring(#(body or "")))

    if not ok_req then
        return false, "HTTP 000. stderr: " .. tostring(err)
    end
    if status < 200 or status >= 300 then
        return false, "HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body)
    end

    local mime, data = parse_image_from_response(body)
    if not data then
        return false, "No image payload found in response."
    end

    local out_png = build_output_path("image", "png")
    if mime == "url" then
        local tmp = unique_path(App.Config.temp_dir, "oai_dl", "bin")
        if not download_file(data, nil, tmp) then
            return false, "Image URL returned but download failed."
        end
        local png = ensure_png(tmp)
        if png ~= out_png then
            run_shell_ok("cp " .. shell_quote(png) .. " " .. shell_quote(out_png))
        end
    else
        local tmp = unique_path(App.Config.temp_dir, "oai_dec", "bin")
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
        provider = "openai",
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
    local png = ensure_png(path)
    local b64 = encode_file_base64(png)
    if not b64 then return nil end

    local mime = image_mime_from_ext(png)
    if mode == "imageBytes" then
        return '{"imageBytes":"' .. b64 .. '","mimeType":"' .. mime .. '"}'
    elseif mode == "bytesBase64Encoded" then
        return '{"bytesBase64Encoded":"' .. b64 .. '","mimeType":"' .. mime .. '"}'
    end
    return '{"inlineData":{"mimeType":"' .. mime .. '","data":"' .. b64 .. '"}}'
end

local function build_veo_payload(prompt, refs, caps, mode, use_last_frame, use_reference_images)
    local instance_parts = {'"prompt":"' .. json_escape(prompt) .. '"'}
    local params_parts = {}

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
            params_parts[#params_parts + 1] = '"lastFrame":' .. blob2
        end
    end

    if use_reference_images and #refs > 0 then
        local arr = {}
        local max_ref_imgs = math.min(#refs, 3)
        for i = 1, max_ref_imgs do
            local blob = image_blob_json(refs[i], mode)
            if blob then
                arr[#arr + 1] = '{"referenceType":"REFERENCE_TYPE_RAW","referenceImage":' .. blob .. '}'
            end
        end
        if #arr > 0 then
            params_parts[#params_parts + 1] = '"referenceImages":[' .. table.concat(arr, ",") .. ']'
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

    params_parts[#params_parts + 1] = '"personGeneration":"allow_all"'

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

    local ok_req, status, body, err = curl_config_request(req, {}, payload_path, App.Config.max_http_seconds)
    log("[cURL stats] " .. tostring(status) .. " size=" .. tostring(#(body or "")))

    if not ok_req then
        return false, nil, "HTTP 000. stderr: " .. tostring(err)
    end
    if status < 200 or status >= 300 then
        return false, nil, "HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body)
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
            return false, "Poll failed: HTTP " .. tostring(status) .. ". " .. parse_http_error_message(body ~= "" and body or err)
        end

        write_file("/tmp/davinci-image-ai-clean/veo_poll_last.json", body, "wb")

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

local function generate_movie_gemini(prompt, refs)
    local key = trim(App.Config.gemini_api_key)
    if key == "" then return false, "Gemini API key is required." end

    local model = trim(App.Config.movie_model)
    if model == "" then return false, "Movie model is required." end

    local caps = MOVIE_MODEL_CAPS[model] or {max_refs = 2, supports_last_frame = true, supports_reference_images = false}
    local mode = "inlineData"
    local use_last = caps.supports_last_frame and refs[2] ~= nil
    local use_refs = caps.supports_reference_images and (#refs > 0)

    local tries = 0
    local op_name = nil
    local last_err = ""

    while tries < 6 do
        tries = tries + 1
        local payload = build_veo_payload(prompt, refs, caps, mode, use_last, use_refs)
        local ok, op_or_nil, body_or_err = start_veo_operation(payload)
        if ok then
            op_name = op_or_nil
            break
        end

        local msg = tostring(body_or_err or "")
        last_err = msg

        if msg:find("`inlineData`", 1, true) then
            mode = "imageBytes"
            log("Veo fallback: retrying with image blob format `imageBytes`")
        elseif msg:find("`imageBytes`", 1, true) then
            mode = "bytesBase64Encoded"
            log("Veo fallback: retrying with image blob format `bytesBase64Encoded`")
        elseif msg:find("`lastFrame`", 1, true) then
            use_last = false
            log("Veo fallback: `lastFrame` unsupported; retrying without it.")
        elseif msg:find("`referenceImages`", 1, true) then
            use_refs = false
            log("Veo fallback: retrying without unsupported field `referenceImages`")
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

    local out_mp4 = build_output_path("movie", "mp4")
    local ok_dl = download_file(uri_or_err, {"x-goog-api-key: " .. key}, out_mp4)
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
        prompt = prompt,
        negative_prompt = App.Config.movie_negative_prompt,
        aspect_ratio = App.Config.movie_aspect_ratio,
        size_or_resolution = App.Config.movie_resolution,
        duration = App.Config.movie_duration,
        refs = refs
    })
    add_history("video_gen", out_mp4, sidecar)

    return true, out_mp4
end

function refresh_gallery_ui()
    local items = App.State.items
    if not items then return end

    local img_filter = combo_current_text(items.imgGalleryFilterCombo)
    if img_filter == "" then img_filter = "Recent References" end
    local img_kind = "refs"
    if img_filter == "Recent Image Gens" then img_kind = "images" end
    if img_filter == "Recent Videos" then img_kind = "videos" end
    if img_filter == "All" then img_kind = "all" end

    local img_hist = get_project_history(img_kind)
    App.State.image_gallery_list = img_hist
    local img_labels = {}
    for _, e in ipairs(img_hist) do
        img_labels[#img_labels + 1] = basename(e.path)
    end
    if #img_labels == 0 then img_labels = {"(empty)"} end
    combo_set_items(items.imgGalleryItemCombo, img_labels, img_labels[1])

    local movie_filter = combo_current_text(items.movieGalleryFilterCombo)
    if movie_filter == "" then movie_filter = "Recent References" end
    local mov_kind = "refs"
    if movie_filter == "Recent Image Gens" then mov_kind = "images" end
    if movie_filter == "Recent Videos" then mov_kind = "videos" end
    if movie_filter == "All" then mov_kind = "all" end

    local mov_hist = get_project_history(mov_kind)
    App.State.movie_gallery_list = mov_hist
    local mov_labels = {}
    for _, e in ipairs(mov_hist) do
        mov_labels[#mov_labels + 1] = basename(e.path)
    end
    if #mov_labels == 0 then mov_labels = {"(empty)"} end
    combo_set_items(items.movieGalleryItemCombo, mov_labels, mov_labels[1])
end

local function current_gallery_entry(tab)
    local items = App.State.items
    if tab == "movie" then
        local idx = (items.movieGalleryItemCombo and items.movieGalleryItemCombo.CurrentIndex or 0) + 1
        return App.State.movie_gallery_list[idx]
    end
    local idx = (items.imgGalleryItemCombo and items.imgGalleryItemCombo.CurrentIndex or 0) + 1
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
        if meta.aspect_ratio and meta.aspect_ratio ~= "" then App.Config.movie_aspect_ratio = meta.aspect_ratio end
        if meta.size_or_resolution and meta.size_or_resolution ~= "" then App.Config.movie_resolution = meta.size_or_resolution end
        if meta.duration and meta.duration ~= "" then App.Config.movie_duration = meta.duration end
        if meta.negative_prompt and meta.negative_prompt ~= "" then App.Config.movie_negative_prompt = meta.negative_prompt end

        local items = App.State.items
        if items and items.moviePromptEdit then
            items.moviePromptEdit.PlainText = meta.prompt or ""
        end

        clear_all_refs("movie")
        for i, p in ipairs(meta.refs or {}) do
            if i <= (App.State.movie_max_refs or 2) and file_exists(p) then
                App.State.movie_refs[i] = p
            end
        end

        refresh_model_combos()
        refresh_slot_buttons()
        return true, "Loaded movie settings from metadata: " .. basename(entry.path)
    end

    if meta.provider and meta.provider ~= "" then App.Config.image_provider = meta.provider end
    if meta.model and meta.model ~= "" then App.Config.image_model = meta.model end
    if meta.aspect_ratio and meta.aspect_ratio ~= "" then App.Config.image_aspect_ratio = meta.aspect_ratio end
    if meta.size_or_resolution and meta.size_or_resolution ~= "" then App.Config.image_size = meta.size_or_resolution end

    local items = App.State.items
    if items and items.imgPromptEdit then
        items.imgPromptEdit.PlainText = meta.prompt or ""
    end

    clear_all_refs("image")
    for i, p in ipairs(meta.refs or {}) do
        if i <= (App.State.image_max_refs or 8) and file_exists(p) then
            App.State.image_refs[i] = p
        end
    end

    refresh_model_combos()
    refresh_slot_buttons()
    return true, "Loaded image settings from metadata: " .. basename(entry.path)
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

    local idx = fill_ref_slot(tab, entry.path, {timeline = "Gallery", timecode = "", frame = ""})
    refresh_slot_buttons()
    return true, "Loaded gallery image into slot " .. tostring(idx)
end

local function show_tab(tab)
    local items = App.State.items
    if not items then return end
    App.State.current_tab = tab

    local is_image = (tab == "image")
    local is_movie = (tab == "movie")
    local is_config = (tab == "config")

    items.imageTabGroup.Visible = is_image
    items.movieTabGroup.Visible = is_movie
    items.configTabGroup.Visible = is_config
end

local function parse_veo_blocking_hint(msg)
    msg = tostring(msg or "")
    if msg:lower():find("safety", 1, true) or msg:lower():find("blocked", 1, true) then
        return msg
    end
    return nil
end

local function build_ui()
    if not App.Core.disp then
        return nil
    end

    local ui = App.Core.ui

    local win = App.Core.disp:AddWindow({
        ID = "cleanRoomWin",
        WindowTitle = App.Config.script_name .. " " .. App.Config.script_version,
        Geometry = {80, 80, 1460, 920}
    },
    ui:VGroup({ID = "root", Spacing = 6,
        ui:HGroup({Weight = 0, Spacing = 6,
            ui:Button({ID = "tabImageBtn", Text = "ImageGen"}),
            ui:Button({ID = "tabMovieBtn", Text = "MovieGen"}),
            ui:Button({ID = "tabConfigBtn", Text = "Configuration"})
        }),

        ui:VGroup({ID = "imageTabGroup", Weight = 1, Spacing = 6,
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Provider", Weight = 0}),
                ui:ComboBox({ID = "imgProviderCombo", Weight = 0}),
                ui:Label({Text = "Model", Weight = 0}),
                ui:ComboBox({ID = "imgModelCombo", Weight = 1}),
                ui:Button({ID = "imgRefreshModelsBtn", Text = "Refresh Models", Weight = 0})
            }),
            ui:Label({ID = "imgCapsLabel", Text = "Capabilities:"}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Aspect Ratio", Weight = 0}),
                ui:ComboBox({ID = "imgAspectCombo", Weight = 0}),
                ui:Label({Text = "Image Size", Weight = 0}),
                ui:ComboBox({ID = "imgSizeCombo", Weight = 0})
            }),
            ui:Label({Text = "Prompt", Weight = 0}),
            ui:TextEdit({ID = "imgPromptEdit", Weight = 0.25, PlainText = "Describe your transformation."}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({ID = "imgRefTokenLabel", Text = "References: grab frames to enable @image tokens", Weight = 1}),
                ui:Button({ID = "imgToken1Btn", Text = "@image1"}),
                ui:Button({ID = "imgToken2Btn", Text = "@image2"}),
                ui:Button({ID = "imgToken3Btn", Text = "@image3"}),
                ui:Button({ID = "imgToken4Btn", Text = "@image4"})
            }),

            ui:HGroup({Weight = 1, Spacing = 6,
                ui:VGroup({Weight = 0.26, Spacing = 6,
                    ui:Label({Text = "Gallery", Weight = 0}),
                    ui:ComboBox({ID = "imgGalleryFilterCombo", Weight = 0}),
                    ui:ComboBox({ID = "imgGalleryItemCombo", Weight = 0}),
                    ui:Button({ID = "imgGalleryUseBtn", Text = "Use Selected As Ref", Weight = 0}),
                    ui:Button({ID = "imgGalleryDeleteBtn", Text = "Delete Selected", Weight = 0}),
                    ui:Button({ID = "imgGalleryPasteBtn", Text = "Paste Ref", Weight = 0}),
                    ui:Button({ID = "imgGalleryLoadBtn", Text = "Load Settings", Weight = 0})
                }),

                ui:VGroup({Weight = 0.38, Spacing = 6,
                    ui:Label({Text = "Original", Weight = 0}),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn1", Text = "1"}),
                        ui:Button({ID = "imgRefBtn2", Text = "2"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn3", Text = "3"}),
                        ui:Button({ID = "imgRefBtn4", Text = "4"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn5", Text = "5"}),
                        ui:Button({ID = "imgRefBtn6", Text = "6"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "imgRefBtn7", Text = "7"}),
                        ui:Button({ID = "imgRefBtn8", Text = "8"})
                    })
                }),

                ui:VGroup({Weight = 0.36, Spacing = 6,
                    ui:Label({Text = "Result", Weight = 0}),
                    ui:Button({ID = "imgResultBtn", Text = "Result", Weight = 1})
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
            ui:TextEdit({ID = "imgStatusBox", ReadOnly = true, Weight = 0.15, PlainText = "Ready."})
        }),

        ui:VGroup({ID = "movieTabGroup", Weight = 1, Spacing = 6,
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({Text = "Movie Model", Weight = 0}),
                ui:ComboBox({ID = "movieModelCombo", Weight = 1}),
                ui:Button({ID = "movieRefreshModelsBtn", Text = "Refresh Movie Models", Weight = 0})
            }),
            ui:Label({ID = "movieCapsLabel", Text = "Capabilities:"}),
            ui:HGroup({Weight = 0, Spacing = 6,
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
            ui:TextEdit({ID = "moviePromptEdit", Weight = 0.25, PlainText = "Describe your shot."}),
            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Label({ID = "movieRefTokenLabel", Text = "References: @image1, @image2", Weight = 1}),
                ui:Button({ID = "movieToken1Btn", Text = "@image1"}),
                ui:Button({ID = "movieToken2Btn", Text = "@image2"})
            }),

            ui:HGroup({Weight = 1, Spacing = 6,
                ui:VGroup({Weight = 0.26, Spacing = 6,
                    ui:Label({Text = "Gallery", Weight = 0}),
                    ui:ComboBox({ID = "movieGalleryFilterCombo", Weight = 0}),
                    ui:ComboBox({ID = "movieGalleryItemCombo", Weight = 0}),
                    ui:Button({ID = "movieGalleryUseBtn", Text = "Use Selected As Ref", Weight = 0}),
                    ui:Button({ID = "movieGalleryDeleteBtn", Text = "Delete Selected", Weight = 0}),
                    ui:Button({ID = "movieGalleryPasteBtn", Text = "Paste Ref", Weight = 0}),
                    ui:Button({ID = "movieGalleryLoadBtn", Text = "Load Settings", Weight = 0})
                }),

                ui:VGroup({Weight = 0.38, Spacing = 6,
                    ui:Label({Text = "Original", Weight = 0}),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn1", Text = "1"}),
                        ui:Button({ID = "movieRefBtn2", Text = "2"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn3", Text = "3"}),
                        ui:Button({ID = "movieRefBtn4", Text = "4"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn5", Text = "5"}),
                        ui:Button({ID = "movieRefBtn6", Text = "6"})
                    }),
                    ui:HGroup({Weight = 1, Spacing = 4,
                        ui:Button({ID = "movieRefBtn7", Text = "7"}),
                        ui:Button({ID = "movieRefBtn8", Text = "8"})
                    })
                }),

                ui:VGroup({Weight = 0.36, Spacing = 6,
                    ui:Label({Text = "Result", Weight = 0}),
                    ui:Button({ID = "movieResultBtn", Text = "Result", Weight = 1})
                })
            }),

            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Button({ID = "movieGrabBtn", Text = "Grab Current Frame"}),
                ui:Button({ID = "movieClearBtn", Text = "Clear Slots"}),
                ui:Button({ID = "movieGenerateBtn", Text = "Generate Movie"}),
                ui:Button({ID = "movieKeepEditingBtn", Text = "Keep Editing"}),
                ui:Button({ID = "movieAddPoolBtn", Text = "Add Movie To Media Pool"}),
                ui:Button({ID = "moviePlayBtn", Text = "Play Result"}),
                ui:Button({ID = "movieCloseBtn", Text = "Close"})
            }),
            ui:TextEdit({ID = "movieStatusBox", ReadOnly = true, Weight = 0.15, PlainText = "Ready."})
        }),

        ui:VGroup({ID = "configTabGroup", Weight = 1, Spacing = 6,
            ui:Label({Text = "Gemini Endpoint", Weight = 0}),
            ui:LineEdit({ID = "cfgGeminiUrlEdit", Weight = 0}),
            ui:Label({Text = "Gemini API Key", Weight = 0}),
            ui:LineEdit({ID = "cfgGeminiKeyEdit", EchoMode = "Password", Weight = 0}),

            ui:Label({Text = "OpenAI Endpoint", Weight = 0}),
            ui:LineEdit({ID = "cfgOpenAIUrlEdit", Weight = 0}),
            ui:Label({Text = "OpenAI API Key", Weight = 0}),
            ui:LineEdit({ID = "cfgOpenAIKeyEdit", EchoMode = "Password", Weight = 0}),

            ui:HGroup({Weight = 0, Spacing = 6,
                ui:Button({ID = "cfgGeminiTestBtn", Text = "Test Gemini Key"}),
                ui:Button({ID = "cfgOpenAITestBtn", Text = "Test OpenAI Key"}),
                ui:Button({ID = "cfgSaveBtn", Text = "Save Config"})
            }),

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

    local items = win:GetItems()
    App.State.items = items
    App.State.win = win

    combo_set_items(items.imgGalleryFilterCombo, {"Recent References", "Recent Image Gens", "Recent Videos", "All"}, "Recent References")
    combo_set_items(items.movieGalleryFilterCombo, {"Recent References", "Recent Image Gens", "Recent Videos", "All"}, "Recent References")

    combo_set_items(items.imgAspectCombo, {"16:9", "9:16", "1:1"}, App.Config.image_aspect_ratio)
    combo_set_items(items.imgSizeCombo, {"1K", "2K", "4K"}, App.Config.image_size)

    combo_set_items(items.movieAspectCombo, {"16:9", "9:16"}, App.Config.movie_aspect_ratio)
    combo_set_items(items.movieResolutionCombo, {"720p", "1080p", "4k"}, App.Config.movie_resolution)
    combo_set_items(items.movieDurationCombo, {"4", "6", "8"}, App.Config.movie_duration)

    sync_controls_from_config()
    refresh_model_combos()
    refresh_gallery_ui()
    refresh_slot_buttons()

    items.imgPromptEdit.PlainText = items.imgPromptEdit.PlainText or "Describe your transformation."
    items.moviePromptEdit.PlainText = items.moviePromptEdit.PlainText or "Describe your shot."
    items.movieNegativeEdit.Text = App.Config.movie_negative_prompt or ""

    show_tab("image")

    function win.On.tabImageBtn.Clicked()
        show_tab("image")
    end
    function win.On.tabMovieBtn.Clicked()
        show_tab("movie")
    end
    function win.On.tabConfigBtn.Clicked()
        show_tab("config")
    end

    function win.On.imgProviderCombo.CurrentIndexChanged()
        set_image_provider(combo_current_text(items.imgProviderCombo))
        save_settings()
    end

    function win.On.imgModelCombo.CurrentIndexChanged()
        local raw = combo_current_text(items.imgModelCombo)
        App.Config.image_model = display_to_model(raw)
        refresh_image_capabilities_label()
        refresh_slot_buttons()
        save_settings()
    end

    function win.On.movieModelCombo.CurrentIndexChanged()
        local raw = combo_current_text(items.movieModelCombo)
        App.Config.movie_model = display_to_model(raw)
        refresh_movie_capabilities_label()
        refresh_slot_buttons()
        save_settings()
    end

    function win.On.imgRefreshModelsBtn.Clicked()
        apply_config_from_controls()
        local ok1, msg1 = fetch_gemini_models()
        local ok2, msg2 = fetch_openai_image_models()
        refresh_model_combos()
        set_image_status((ok1 and "" or (msg1 .. "\n")) .. (ok2 and "" or msg2))
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
        App.Config.image_aspect_ratio = combo_current_text(items.imgAspectCombo)
        save_settings()
    end

    function win.On.imgSizeCombo.CurrentIndexChanged()
        App.Config.image_size = combo_current_text(items.imgSizeCombo)
        save_settings()
    end

    function win.On.movieAspectCombo.CurrentIndexChanged()
        App.Config.movie_aspect_ratio = combo_current_text(items.movieAspectCombo)
        save_settings()
    end

    function win.On.movieResolutionCombo.CurrentIndexChanged()
        App.Config.movie_resolution = combo_current_text(items.movieResolutionCombo)
        save_settings()
    end

    function win.On.movieDurationCombo.CurrentIndexChanged()
        App.Config.movie_duration = combo_current_text(items.movieDurationCombo)
        save_settings()
    end

    function win.On.imgGalleryFilterCombo.CurrentIndexChanged()
        refresh_gallery_ui()
    end

    function win.On.movieGalleryFilterCombo.CurrentIndexChanged()
        refresh_gallery_ui()
    end

    function win.On.imgGalleryUseBtn.Clicked()
        local ok, msg = use_selected_gallery_as_ref("image")
        set_image_status(msg)
    end

    function win.On.movieGalleryUseBtn.Clicked()
        local ok, msg = use_selected_gallery_as_ref("movie")
        set_movie_status(msg)
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

    local function on_img_ref_clicked(i)
        if App.State.image_refs[i] and App.State.image_refs[i] ~= "" then
            clear_ref_slot("image", i)
            refresh_slot_buttons()
            set_image_status("Cleared slot " .. tostring(i))
        end
    end

    local function on_movie_ref_clicked(i)
        if i > (App.State.movie_max_refs or 0) then
            set_movie_status("Slot " .. tostring(i) .. " is unsupported for current model.")
            return
        end
        if App.State.movie_refs[i] and App.State.movie_refs[i] ~= "" then
            clear_ref_slot("movie", i)
            refresh_slot_buttons()
            set_movie_status("Cleared movie slot " .. tostring(i))
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

    local function append_token(edit, token)
        local txt = edit.PlainText or edit.Text or ""
        if txt == "" then
            edit.PlainText = token
        else
            edit.PlainText = txt .. " " .. token
        end
    end

    function win.On.imgToken1Btn.Clicked() append_token(items.imgPromptEdit, "@image1") end
    function win.On.imgToken2Btn.Clicked() append_token(items.imgPromptEdit, "@image2") end
    function win.On.imgToken3Btn.Clicked() append_token(items.imgPromptEdit, "@image3") end
    function win.On.imgToken4Btn.Clicked() append_token(items.imgPromptEdit, "@image4") end

    function win.On.movieToken1Btn.Clicked() append_token(items.moviePromptEdit, "@image1") end
    function win.On.movieToken2Btn.Clicked() append_token(items.moviePromptEdit, "@image2") end

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
        set_image_status("Starting generation...")

        local ok, result
        if App.Config.image_provider == "openai" then
            ok, result = generate_image_openai(prompt, refs)
        else
            ok, result = generate_image_gemini(prompt, refs)
        end

        if ok then
            App.State.last_image_path = result
            refresh_gallery_ui()
            refresh_slot_buttons()
            set_image_status("Success:\n" .. tostring(result))
        else
            set_image_status("Failed:\n" .. tostring(result))
        end
    end

    function win.On.movieGenerateBtn.Clicked()
        apply_config_from_controls()
        App.Config.movie_model = display_to_model(combo_current_text(items.movieModelCombo))
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

        set_button_image(items.movieResultBtn, nil, "Generating...", "video")
        set_movie_status("Starting movie generation...")
        log("Using Veo endpoint: " .. trim(App.Config.gemini_api_url) .. "/models/" .. App.Config.movie_model .. ":predictLongRunning")

        local ok, result = generate_movie_gemini(prompt, refs)
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
        if App.State.last_image_path and file_exists(App.State.last_image_path) then
            set_button_image(items.imgResultBtn, App.State.last_image_path, "Result", "image")
            set_image_status("Result preview refreshed.")
        end
    end

    function win.On.movieResultBtn.Clicked()
        if App.State.last_movie_path and file_exists(App.State.last_movie_path) then
            local poster = load_preview_for_video(App.State.last_movie_path, App.Config.result_preview_max, "movie_result")
            set_button_image(items.movieResultBtn, poster or App.State.last_movie_path, "Video Ready", "video")
            set_movie_status("Result preview refreshed.")
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

    function win.On.cfgOpenAITestBtn.Clicked()
        apply_config_from_controls()
        local ok, msg = test_openai_key()
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

    function win.On.imgCloseBtn.Clicked()
        App.Core.disp:ExitLoop()
    end

    function win.On.movieCloseBtn.Clicked()
        App.Core.disp:ExitLoop()
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

    mkdir_p(App.Config.temp_dir)
    mkdir_p(App.Config.output_dir)

    load_settings()
    load_history()

    local ok_g, msg_g = fetch_gemini_models()
    if not ok_g then log(msg_g) end
    fetch_openai_image_models()

    if App.Core.disp and App.Core.ui then
        local win = build_ui()
        if win then
            win:Show()
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
