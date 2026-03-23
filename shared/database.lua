---------------------------------------------------
--  d4rk_fd_utility – Database Abstraktion
--  Unterstützt: oxmysql | mysql-async | ghmattimysql
---------------------------------------------------

DB = {}

-- ─────────────────────────────────────────────
--  Interner Wrapper – wählt die richtige Resource
-- ─────────────────────────────────────────────

local function getAdapter()
    return Config.Database or 'oxmysql'
end

---Führt eine INSERT / UPDATE / DELETE Query aus
---@param query  string
---@param params table
---@param cb     function|nil  callback(affectedRows)
function DB.Execute(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        exports.oxmysql:execute(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.execute(query, params, function(rows)
            if cb then cb(rows) end
        end)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:execute(query, params, function(rows)
            if cb then cb(rows) end
        end)

    else
        print(('[d4rk_fd_utility] ^1Unbekannter DB Adapter: %s^7'):format(adapter))
    end
end

---Liest eine einzelne Zeile
---@param query  string
---@param params table
---@param cb     function  callback(row|nil)
function DB.Single(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        exports.oxmysql:single(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.fetchAll(query, params, function(result)
            if cb then cb(result and result[1] or nil) end
        end)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:scalar(query, params, function(result)
            if cb then cb(result) end
        end)

    else
        print(('[d4rk_fd_utility] ^1Unbekannter DB Adapter: %s^7'):format(adapter))
    end
end

---Liest mehrere Zeilen
---@param query  string
---@param params table
---@param cb     function  callback(rows)
function DB.Fetch(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        exports.oxmysql:query(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.fetchAll(query, params, function(result)
            if cb then cb(result or {}) end
        end)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:fetch(query, params, function(result)
            if cb then cb(result or {}) end
        end)

    else
        print(('[d4rk_fd_utility] ^1Unbekannter DB Adapter: %s^7'):format(adapter))
    end
end

---Synchrone Version von DB.Single (via Promise – funktioniert in Coroutine-Kontext)
---Nutzbar in: lib.callback.register, Citizen.CreateThread mit Await
---@param query  string
---@param params table
---@return table|nil
function DB.SingleSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        -- oxmysql hat keine _sync Exports mehr → Promise awaiten
        return Citizen.Await(exports.oxmysql:single_p(query, params))

    elseif adapter == 'mysql-async' then
        -- mysql-async: Sync via Promise
        local p = promise.new()
        MySQL.Async.fetchAll(query, params, function(result)
            p:resolve(result and result[1] or nil)
        end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:fetch(query, params, function(result)
            p:resolve(result and result[1] or nil)
        end)
        return Citizen.Await(p)
    end

    return nil
end

---Synchrone Version von DB.Fetch (via Promise)
---@param query  string
---@param params table
---@return table
function DB.FetchSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return Citizen.Await(exports.oxmysql:query_p(query, params)) or {}

    elseif adapter == 'mysql-async' then
        local p = promise.new()
        MySQL.Async.fetchAll(query, params, function(result)
            p:resolve(result or {})
        end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:fetch(query, params, function(result)
            p:resolve(result or {})
        end)
        return Citizen.Await(p)
    end

    return {}
end