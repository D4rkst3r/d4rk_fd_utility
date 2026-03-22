---------------------------------------------------
--  d4rk_fd_utility – Locale System
---------------------------------------------------

local localeData = {}

-- Lädt die JSON Locale-Datei beim Start
CreateThread(function()
    local file = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(Config.Locale))
    if file then
        localeData = json.decode(file) or {}
    else
        print(('[d4rk_fd_utility] Locale "%s" nicht gefunden, fallback auf "en"'):format(Config.Locale))
        local fallback = LoadResourceFile(GetCurrentResourceName(), 'locales/en.json')
        if fallback then localeData = json.decode(fallback) or {} end
    end
end)

---@param key string
---@param ... any  Platzhalter-Werte für string.format
---@return string
function T(key, ...)
    local text = localeData[key] or key
    if select('#', ...) > 0 then
        return text:format(...)
    end
    return text
end
