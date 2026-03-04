-- Clean-room DaVinci Resolve utility script (unencrypted Lua)
-- Pipeline:
-- 1) Export current frame as still (PNG)
-- 2) Compress to 1920px JPEG (sips)
-- 3) Base64 encode JPEG
-- 4) Send JSON via curl (async subprocess + polling)
-- 5) Decode returned base64 to image
-- 6) Save/import generated image

math.randomseed(os.time())

local App = {}

App.Config = {
    script_name = "DaVinci Image AI (Clean Room)",
    script_version = "0.1.0",
    temp_dir = "/tmp/davinci-image-ai-clean/",
    output_dir = "/tmp/davinci-image-ai-clean/output/",
    api_url = "",
    api_key = os.getenv("DAVINCI_IMAGE_AI_API_KEY") or "",
    model = "",
    max_time_seconds = 180,
    jpeg_long_edge = 1920,
    jpeg_quality = 70
}

App.Core = {}
App.Core.resolve = resolve or Resolve()
App.Core.fusion = App.Core.resolve and App.Core.resolve:Fusion()
App.Core.ui = App.Core.fusion and App.Core.fusion.UIManager
App.Core.disp = App.Core.ui and bmd.UIDispatcher(App.Core.ui)

local function log(msg)
    print("[" .. App.Config.script_name .. "] " .. tostring(msg))
end

local function shell_quote(s)
    if s == nil then
        return "''"
    end
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function file_exists(path)
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
    os.execute("mkdir -p " .. shell_quote(path))
end

local function now_ms()
    return math.floor(os.time() * 1000 + math.random(0, 999))
end

local function unique_path(dir, prefix, ext)
    local stamp = tostring(now_ms())
    return dir .. prefix .. "_" .. stamp .. "." .. ext
end

local function sleep_seconds(sec)
    os.execute("sleep " .. tostring(sec))
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

local function parse_data_url(body)
    local mime, b64 = body:match("data:([^;]+);base64,([A-Za-z0-9+/=_%-%s]+)")
    if not b64 then return nil, nil end
    b64 = b64:gsub("%s+", ""):gsub("%%2B", "+"):gsub("%%2F", "/"):gsub("%%3D", "=")
    return mime or "image/jpeg", b64
end

local function parse_named_b64(body)
    local keys = {
        "b64_json",
        "image_base64",
        "base64",
        "image_b64",
        "imageData",
        "result_base64"
    }
    for _, key in ipairs(keys) do
        local pat = '"' .. key .. '"%s*:%s*"([A-Za-z0-9+/=_%-%s]+)"'
        local b64 = body:match(pat)
        if b64 and #b64 > 100 then
            b64 = b64:gsub("%s+", ""):gsub("\\/", "/"):gsub("%%2B", "+"):gsub("%%2F", "/"):gsub("%%3D", "=")
            return "image/jpeg", b64
        end
    end
    return nil, nil
end

local function parse_image_url(body)
    local u = body:match('"url"%s*:%s*"(https://[^"]+)"')
    if u then return u end
    u = body:match("(https://[%w%._%-%/%?&=#%%]+%.png)")
    if u then return u end
    u = body:match("(https://[%w%._%-%/%?&=#%%]+%.jpg)")
    if u then return u end
    u = body:match("(https://[%w%._%-%/%?&=#%%]+%.jpeg)")
    if u then return u end
    u = body:match("(https://[%w%._%-%/%?&=#%%]+%.webp)")
    return u
end

local function compress_png_to_jpeg(src_png, out_jpg)
    local cmd = string.format(
        "sips -s format jpeg -s formatOptions %d -Z %d %s --out %s >/dev/null 2>&1",
        App.Config.jpeg_quality,
        App.Config.jpeg_long_edge,
        shell_quote(src_png),
        shell_quote(out_jpg)
    )
    local ok = run_shell_ok(cmd)
    return ok and file_exists(out_jpg)
end

local function encode_file_b64(src_path, b64_path)
    local cmd1 = string.format(
        "openssl base64 -A -in %s -out %s >/dev/null 2>&1",
        shell_quote(src_path),
        shell_quote(b64_path)
    )
    if run_shell_ok(cmd1) and file_exists(b64_path) then
        return true
    end

    local cmd2 = string.format(
        "( base64 %s | tr -d '\\n' ) > %s 2>/dev/null",
        shell_quote(src_path),
        shell_quote(b64_path)
    )
    return run_shell_ok(cmd2) and file_exists(b64_path)
end

local function decode_b64_to_file(payload, out_path)
    local b64_tmp = unique_path(App.Config.temp_dir, "decode", "b64")
    if not write_file(b64_tmp, payload, "wb") then
        return false
    end

    local cmd1 = string.format(
        "base64 -d -i %s -o %s >/dev/null 2>&1",
        shell_quote(b64_tmp),
        shell_quote(out_path)
    )
    if run_shell_ok(cmd1) and file_exists(out_path) then
        os.remove(b64_tmp)
        return true
    end

    local cmd2 = string.format(
        "openssl base64 -d -A -in %s -out %s >/dev/null 2>&1",
        shell_quote(b64_tmp),
        shell_quote(out_path)
    )
    local ok = run_shell_ok(cmd2) and file_exists(out_path)
    os.remove(b64_tmp)
    return ok
end

local function start_curl_async(config_path, status_path, body_path, err_path, max_time)
    local cmd = string.format(
        "curl -sS -L --http1.1 --no-keepalive -m %d --config %s -o %s -w '%%{http_code}' > %s 2> %s",
        max_time,
        shell_quote(config_path),
        shell_quote(body_path),
        shell_quote(status_path),
        shell_quote(err_path)
    )
    local h = io.popen(cmd .. " </dev/null &", "r")
    if h then
        h:close()
        return true
    end
    return false
end

local function wait_for_status_file(status_path, timeout_seconds)
    local elapsed = 0
    while elapsed < timeout_seconds do
        if file_exists(status_path) then
            return true
        end
        sleep_seconds(1)
        elapsed = elapsed + 1
    end
    return false
end

local function import_result_to_media_pool(path)
    local pm = App.Core.resolve and App.Core.resolve:GetProjectManager()
    local project = pm and pm:GetCurrentProject()
    local pool = project and project:GetMediaPool()
    if pool then
        local ok = pcall(function() pool:ImportMedia({path}) end)
        if ok then
            log("Imported generated image into Media Pool: " .. path)
            return
        end
    end
    log("Generated image saved: " .. path)
end

local function build_payload_json(prompt, image_b64)
    local model_line = ""
    if App.Config.model ~= "" then
        model_line = '"model":"' .. json_escape(App.Config.model) .. '",'
    end
    return "{"
        .. model_line
        .. '"prompt":"' .. json_escape(prompt) .. '",'
        .. '"image_b64":"' .. image_b64 .. '",'
        .. '"mime_type":"image/jpeg"'
        .. "}"
end

local function export_current_frame_png(out_png)
    local pm = App.Core.resolve and App.Core.resolve:GetProjectManager()
    local project = pm and pm:GetCurrentProject()
    if not project then
        return false, "No active project."
    end

    local ok, ret = pcall(function()
        return project:ExportCurrentFrameAsStill(out_png)
    end)
    if not ok then
        return false, "ExportCurrentFrameAsStill call failed."
    end
    if not ret or not file_exists(out_png) then
        return false, "Resolve did not create still file."
    end
    return true, nil
end

local function call_api_with_image(prompt)
    mkdir_p(App.Config.temp_dir)
    mkdir_p(App.Config.output_dir)

    if App.Config.api_url == "" then
        return false, "API URL is required."
    end
    if App.Config.api_key == "" then
        return false, "API key is required."
    end

    local frame_png = unique_path(App.Config.temp_dir, "frame", "png")
    local frame_jpg = unique_path(App.Config.temp_dir, "frame", "jpg")
    local frame_b64 = unique_path(App.Config.temp_dir, "frame", "b64")
    local payload_json = unique_path(App.Config.temp_dir, "payload", "json")
    local curl_cfg = unique_path(App.Config.temp_dir, "request", "curl")
    local status_txt = unique_path(App.Config.temp_dir, "response", "status")
    local body_txt = unique_path(App.Config.temp_dir, "response", "body")
    local err_txt = unique_path(App.Config.temp_dir, "response", "err")

    local ok_export, export_err = export_current_frame_png(frame_png)
    if not ok_export then
        return false, export_err
    end

    if not compress_png_to_jpeg(frame_png, frame_jpg) then
        return false, "JPEG compression failed (sips)."
    end

    if not encode_file_b64(frame_jpg, frame_b64) then
        return false, "Base64 encoding failed."
    end

    local image_b64 = read_file(frame_b64, "rb")
    if not image_b64 or image_b64 == "" then
        return false, "Base64 file is empty."
    end
    image_b64 = image_b64:gsub("%s+", "")

    local payload = build_payload_json(prompt, image_b64)
    if not write_file(payload_json, payload, "wb") then
        return false, "Failed to write payload JSON."
    end

    local cfg = {}
    cfg[#cfg + 1] = "url = " .. shell_quote(App.Config.api_url)
    cfg[#cfg + 1] = "request = POST"
    cfg[#cfg + 1] = "header = " .. shell_quote("Content-Type: application/json")
    cfg[#cfg + 1] = "header = " .. shell_quote("Authorization: Bearer " .. App.Config.api_key)
    cfg[#cfg + 1] = "data-binary = " .. shell_quote("@" .. payload_json)
    if not write_file(curl_cfg, table.concat(cfg, "\n"), "wb") then
        return false, "Failed to write curl config."
    end

    if not start_curl_async(curl_cfg, status_txt, body_txt, err_txt, App.Config.max_time_seconds) then
        return false, "Failed to start async curl."
    end

    if not wait_for_status_file(status_txt, App.Config.max_time_seconds + 20) then
        return false, "Timed out waiting for API response."
    end

    local status = (read_file(status_txt, "rb") or ""):gsub("%s+", "")
    local body = read_file(body_txt, "rb") or ""
    local err_body = read_file(err_txt, "rb") or ""

    if status == "" then
        return false, "Missing HTTP status. curl error: " .. err_body
    end
    if status:sub(1, 1) ~= "2" then
        return false, "HTTP " .. status .. ". Body: " .. body
    end

    local mime, b64 = parse_data_url(body)
    if not b64 then
        mime, b64 = parse_named_b64(body)
    end

    if b64 then
        local ext = "jpg"
        if mime and mime:find("png", 1, true) then ext = "png" end
        if mime and mime:find("webp", 1, true) then ext = "webp" end
        local out_path = unique_path(App.Config.output_dir, "generated", ext)
        if not decode_b64_to_file(b64, out_path) then
            return false, "Base64 decode of API response failed."
        end
        import_result_to_media_pool(out_path)
        return true, out_path
    end

    local image_url = parse_image_url(body)
    if image_url then
        local out_path = unique_path(App.Config.output_dir, "generated", "jpg")
        local dl_cmd = string.format("curl -sS -L %s -o %s >/dev/null 2>&1", shell_quote(image_url), shell_quote(out_path))
        if run_shell_ok(dl_cmd) and file_exists(out_path) then
            import_result_to_media_pool(out_path)
            return true, out_path
        end
    end

    return false, "No image payload found in response."
end

local function build_ui()
    if not App.Core.disp then
        return nil
    end

    local ui = App.Core.ui
    local win = App.Core.disp:AddWindow({
        ID = "cleanRoomWin",
        WindowTitle = App.Config.script_name .. " " .. App.Config.script_version,
        Geometry = {100, 100, 760, 420}
    }, ui:VGroup({
        ID = "root",
        Spacing = 8,
        ui:Label({Text = "API URL"}),
        ui:LineEdit({ID = "apiUrlEdit", Text = App.Config.api_url, PlaceholderText = "https://api.example.com/v1/image"}),
        ui:Label({Text = "API Key"}),
        ui:LineEdit({ID = "apiKeyEdit", Text = App.Config.api_key, EchoMode = "Password"}),
        ui:Label({Text = "Model (optional)"}),
        ui:LineEdit({ID = "modelEdit", Text = App.Config.model, PlaceholderText = "model-name"}),
        ui:Label({Text = "Prompt"}),
        ui:PlainTextEdit({ID = "promptEdit", PlainText = "Describe your transformation."}),
        ui:HGroup({
            Weight = 0,
            ui:Button({ID = "runBtn", Text = "Grab + Send"}),
            ui:Button({ID = "closeBtn", Text = "Close"})
        }),
        ui:TextEdit({ID = "statusBox", ReadOnly = true, Text = "Ready."})
    }))

    local items = win:GetItems()

    local function set_status(text)
        items.statusBox.PlainText = tostring(text or "")
        log(text)
    end

    function win.On.runBtn.Clicked()
        App.Config.api_url = items.apiUrlEdit.Text or ""
        App.Config.api_key = items.apiKeyEdit.Text or ""
        App.Config.model = items.modelEdit.Text or ""
        local prompt = items.promptEdit.PlainText or ""
        set_status("Running pipeline...")
        local ok, result = call_api_with_image(prompt)
        if ok then
            set_status("Success:\n" .. tostring(result))
        else
            set_status("Failed:\n" .. tostring(result))
        end
    end

    function win.On.closeBtn.Clicked()
        App.Core.disp:ExitLoop()
    end

    function win.On.cleanRoomWin.Close()
        App.Core.disp:ExitLoop()
    end

    return win
end

local function main()
    log("Starting " .. App.Config.script_version)

    mkdir_p(App.Config.temp_dir)
    mkdir_p(App.Config.output_dir)

    local win = build_ui()
    if win then
        win:Show()
        App.Core.disp:RunLoop()
        win:Hide()
        return
    end

    log("No UI context found. Running headless with defaults.")
    local ok, result = call_api_with_image("Describe your transformation.")
    if ok then
        log("Done: " .. tostring(result))
    else
        log("Failed: " .. tostring(result))
    end
end

main()
