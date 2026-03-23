---------------------------------------------------
--  d4rk_fd_utility – Locale System
---------------------------------------------------

local localeData = {}

local function LoadLocale()
    local file = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(Config.Locale))
    if file then
        localeData = json.decode(file) or {}
    else
        print(('[d4rk_fd_utility] Locale "%s" nicht gefunden, fallback auf "en"'):format(Config.Locale))
        local fallback = LoadResourceFile(GetCurrentResourceName(), 'locales/en.json')
        if fallback then localeData = json.decode(fallback) or {} end
    end
end

-- Direkt laden ohne Thread – funktioniert auf Client und Server
LoadLocale()

---@param key string
---@param ... any
---@return string
function T(key, ...)
    local text = localeData[key] or key
    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end