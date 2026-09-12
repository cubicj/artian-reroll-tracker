local TAG = "[RerollTracker]"
local BASE_SIZE = 18

local _M = {}

local cache = {}
local currentSize = BASE_SIZE
local currentFont = nil

local function read_default_size()
    if type(imgui.get_default_font_size) ~= "function" then
        return nil
    end
    local ok, size = pcall(imgui.get_default_font_size)
    if not ok or type(size) ~= "number" or size <= 0 then
        return nil
    end
    return math.floor(size + 0.5)
end

local function load_font_for(size)
    local ok, font = false, "imgui.load_font is unavailable"
    if type(imgui.load_font) == "function" then
        ok, font = pcall(imgui.load_font, nil, size)
    end
    if not ok or not font then
        log.error(TAG .. " Error: font load failed at size " .. tostring(size) .. ": " .. tostring(font))
        return false
    end
    return font
end

function _M.current()
    local size = read_default_size()
    if not size then
        currentSize = BASE_SIZE
        currentFont = nil
        return nil, BASE_SIZE
    end
    if cache[size] == nil then
        cache[size] = load_font_for(size)
    end
    currentSize = size
    currentFont = cache[size] or nil
    return currentFont, currentSize
end

function _M.scaled(px)
    return math.ceil(px * currentSize / BASE_SIZE)
end

return _M
