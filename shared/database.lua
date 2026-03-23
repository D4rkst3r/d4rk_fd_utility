---------------------------------------------------
--  d4rk_fd_utility – Database Abstraktion
--  oxmysql:  MySQL.*.await  (Lua 5.4 native)
--  mysql-async / ghmattimysql: Callback-Fallback
---------------------------------------------------

DB = {}

local function getAdapter()
    return Config.Database or 'oxmysql'
end

-- ─────────────────────────────────────────────
--  Execute  (INSERT / UPDATE / DELETE)
-- ─────────────────────────────────────────────

function DB.Execute(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        if cb then
            MySQL.update(query, params, cb)
        else
            MySQL.update(query, params)
        end

    elseif adapter == 'mysql-async' then
        MySQL.Async.execute(query, params, cb)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:execute(query, params, cb)
    end
end

-- ─────────────────────────────────────────────
--  Single  (SELECT – eine Zeile)
-- ─────────────────────────────────────────────

function DB.Single(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        MySQL.single(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.fetchAll(query, params, function(result)
            if cb then cb(result and result[1] or nil) end
        end)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:scalar(query, params, cb)
    end
end

-- ─────────────────────────────────────────────
--  Fetch  (SELECT – mehrere Zeilen)
-- ─────────────────────────────────────────────

function DB.Fetch(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        MySQL.query(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.fetchAll(query, params, function(result)
            if cb then cb(result or {}) end
        end)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:fetch(query, params, function(result)
            if cb then cb(result or {}) end
        end)
    end
end

-- ─────────────────────────────────────────────
--  Scalar  (SELECT – einzelner Wert)
-- ─────────────────────────────────────────────

function DB.Scalar(query, params, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        MySQL.scalar(query, params, cb)

    elseif adapter == 'mysql-async' then
        MySQL.Async.fetchScalar(query, params, cb)

    elseif adapter == 'ghmattimysql' then
        exports['ghmattimysql']:scalar(query, params, cb)
    end
end

-- ─────────────────────────────────────────────
--  Await-Versionen  (für Coroutine-Kontext)
--  Nutzbar in: lib.callback.register, CreateThread
-- ─────────────────────────────────────────────

-- await: einzelne Zeile
function DB.SingleSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return MySQL.single.await(query, params)

    elseif adapter == 'mysql-async' then
        local p = promise.new()
        MySQL.Async.fetchAll(query, params, function(r) p:resolve(r and r[1] or nil) end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:fetch(query, params, function(r) p:resolve(r and r[1] or nil) end)
        return Citizen.Await(p)
    end
end

-- await: mehrere Zeilen
function DB.FetchSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return MySQL.query.await(query, params) or {}

    elseif adapter == 'mysql-async' then
        local p = promise.new()
        MySQL.Async.fetchAll(query, params, function(r) p:resolve(r or {}) end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:fetch(query, params, function(r) p:resolve(r or {}) end)
        return Citizen.Await(p)
    end
end

-- await: scalar
function DB.ScalarSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return MySQL.scalar.await(query, params)

    elseif adapter == 'mysql-async' then
        local p = promise.new()
        MySQL.Async.fetchScalar(query, params, function(r) p:resolve(r) end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:scalar(query, params, function(r) p:resolve(r) end)
        return Citizen.Await(p)
    end
end

-- await: execute
function DB.ExecuteSync(query, params)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return MySQL.update.await(query, params)

    elseif adapter == 'mysql-async' then
        local p = promise.new()
        MySQL.Async.execute(query, params, function(r) p:resolve(r) end)
        return Citizen.Await(p)

    elseif adapter == 'ghmattimysql' then
        local p = promise.new()
        exports['ghmattimysql']:execute(query, params, function(r) p:resolve(r) end)
        return Citizen.Await(p)
    end
end

-- ─────────────────────────────────────────────
--  Prepared Statements  (oxmysql only)
--  Für wiederholte Queries mit gleichem Statement
--  deutlich schneller laut Benchmark
-- ─────────────────────────────────────────────

--[[
    Beispiel:
    local results = DB.Prepare(
        'SELECT id FROM player_vehicles WHERE plate = ? LIMIT 1',
        { { 'ABC123' }, { 'XYZ456' } }   -- mehrere Parameter-Sets
    )
]]
function DB.Prepare(query, paramSets, cb)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        if cb then
            MySQL.prepare(query, paramSets, cb)
        else
            MySQL.prepare(query, paramSets)
        end
    else
        -- Fallback: normale Einzel-Queries
        if cb then
            local results = {}
            for _, params in ipairs(paramSets or {}) do
                DB.Single(query, params, function(r)
                    results[#results + 1] = r
                end)
            end
            cb(results)
        end
    end
end

function DB.PrepareSync(query, paramSets)
    local adapter = getAdapter()

    if adapter == 'oxmysql' then
        return MySQL.prepare.await(query, paramSets)
    else
        -- Fallback: await-Version
        local p = promise.new()
        local results = {}
        for _, params in ipairs(paramSets or {}) do
            results[#results + 1] = DB.SingleSync(query, params)
        end
        return results
    end
end
