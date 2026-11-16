-- Resolve stable PCI paths to /dev/dri/cardX (AQ_DRM_DEVICES splits on ':', so paths must not contain ':')
local function resolve_card(by_path)
    local p = io.popen("readlink -f '" .. by_path .. "' 2>/dev/null")
    if not p then return nil end
    local res = p:read("*l")
    p:close()
    if res and res ~= "" then return res end
    return nil
end

local amd_card = resolve_card("/dev/dri/by-path/pci-0000:06:00.0-card") or "/dev/dri/card1"
local nv_card  = resolve_card("/dev/dri/by-path/pci-0000:01:00.0-card") or "/dev/dri/card0"
hl.env("AQ_DRM_DEVICES", amd_card .. ":" .. nv_card)

hl.on("hyprland.start", function()
    -- Start input method daemon (fcitx5)
    hl.exec_cmd("fcitx5 -d")
end)
