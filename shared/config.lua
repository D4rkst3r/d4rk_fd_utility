---------------------------------------------------
--  d4rk_fd_utility – Zentrale Konfiguration
---------------------------------------------------

Config = {}

-- ─────────────────────────────────────────────
--  Framework & Integrations
-- ─────────────────────────────────────────────
Config.Framework     = 'qbx'         -- 'qbx' | 'qb' | 'esx' | 'standalone'
Config.Locale        = 'de'          -- Sprache (locales/<lang>.json)
Config.Debug         = false         -- Debug-Prints in der Console
Config.Database      = 'oxmysql'     -- 'oxmysql' | 'mysql-async' | 'ghmattimysql'

Config.UseTarget     = true          -- ox_target für Interaktionen
Config.UseInventory  = true          -- ox_inventory für Item-Checks
Config.UseNotify     = true          -- ox_lib Notify statt einfachem Chat

-- ─────────────────────────────────────────────
--  Module – einzeln aktivierbar
-- ─────────────────────────────────────────────
Config.Modules = {
    Extrication     = true,   -- client/extrication.lua
    HazMat          = true,   -- client/hazmat.lua
    Scene           = true,   -- client/scene.lua
    Equipment       = true,   -- client/equipment.lua
    Patient         = true,   -- client/patient.lua
    Fire            = true,   -- client/fire.lua
}

-- Extrication – Zusatz-Optionen
Config.Extrication = {
    onlyWrecked = false,   -- true → Target nur auf beschädigten Fahrzeugen anzeigen
}

-- ─────────────────────────────────────────────
--  Spieler-Fahrzeug Erkennung
-- ─────────────────────────────────────────────
Config.PlayerVehicles = {
    enabled               = true,

    -- Tabelle + Spalte aus dem Server-eigenen Fahrzeugsystem
    -- Einfach anpassen falls der Server etwas anderes nutzt
    dbTable               = 'player_vehicles',  -- QB/QBX default
    dbColumn              = 'plate',            -- Spaltenname für Kennzeichen

    -- Beispiele:
    --   ESX:              dbTable = 'owned_vehicles',  dbColumn = 'plate'
    --   Eigenes System:   dbTable = 'vehicles',        dbColumn = 'numberplate'

    requireLettersInPlate = true,  -- NPC-Platten ohne Buchstaben vorfiltern
}

-- ─────────────────────────────────────────────
--  Job / Permissions
-- ─────────────────────────────────────────────
Config.Jobs = {
    ['ambulance'] = true,
    ['fire']      = true,
    ['firefighter'] = true,
}

-- Mindest-Grade pro Aktion (0 = alle Grades erlaubt)
Config.Grades = {
    extrication   = 0,
    hazmat        = 2,
    scene         = 0,
    equipment     = 0,
    patient       = 0,
    fire          = 0,
}

-- ─────────────────────────────────────────────
--  ox_inventory – Items
-- ─────────────────────────────────────────────
--  required  = true  → Aktion nur mit Item möglich
--  consume   = true  → Item wird bei Nutzung verbraucht
--  durability = true → Item verliert Haltbarkeit (ox_inv Feature)
-- ─────────────────────────────────────────────
Config.Items = {
    -- Extrication
    hydraulicSpreader = {
        label      = 'Hydraulikspreizer',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 8000,   -- ms
    },
    rescueSaw = {
        label      = 'Rettungssäge',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 10000,
    },
    tireCutter = {
        label      = 'Reifenschneider',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 5000,
    },
    -- HazMat
    oilBarrier = {
        label      = 'Ölsperre',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 3000,
    },
    hazmatSuit = {
        label      = 'HazMat Anzug',
        required   = false,
        consume    = false,
        durability = true,
        useTime    = 0,
    },
    -- Scene Management
    trafficCone = {
        label      = 'Verkehrskegel',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 1500,
    },
    safetyBarrier = {
        label      = 'Absperrband',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 2000,
    },
    lightStand = {
        label      = 'Lichtmast',
        required   = true,
        consume    = false,
        durability = false,
        useTime    = 4000,
    },
    -- Equipment
    thermoCam = {
        label      = 'Wärmebildkamera',
        required   = false,
        consume    = false,
        durability = false,
        useTime    = 0,
    },
    fireExtinguisher = {
        label      = 'Feuerlöscher',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 0,
    },
    -- Patient
    spineboard = {
        label      = 'Spineboard',
        required   = true,
        consume    = false,
        durability = false,
        useTime    = 3000,
    },
    triageTag = {
        label      = 'Triage-Tag',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 1000,
    },
}

-- ─────────────────────────────────────────────
--  Cooldowns (ms) – verhindert Spam
-- ─────────────────────────────────────────────
Config.Cooldowns = {
    doorRemove   = 5000,
    tireRemove   = 5000,
    airbag       = 8000,
    oilPlace     = 3000,
    conePlace    = 1500,
    barrierPlace = 2000,
    extract      = 10000,
    triage       = 2000,
}

-- ─────────────────────────────────────────────
--  Prop Limits – Max platzierte Props pro Spieler
-- ─────────────────────────────────────────────
Config.Limits = {
    cones        = 12,
    barriers     = 8,
    lightStands  = 4,
    oilPatches   = 6,
    fireSigns    = 6,
}

-- ─────────────────────────────────────────────
--  Animationen
-- ─────────────────────────────────────────────
Config.Anims = {
    spreizer = {
        dict  = 'amb@world_human_gardener_plant@male@base',
        clip  = 'base',
        flag  = 1,
    },
    saw = {
        dict  = 'amb@world_human_gardener_plant@male@base',
        clip  = 'base',
        flag  = 1,
    },
    kneel = {
        dict  = 'amb@medic@standing@tendtovictim@enter',
        clip  = 'enter',
        flag  = 1,
    },
    place = {
        dict  = 'amb@world_human_gardener_plant@male@base',
        clip  = 'base',
        flag  = 49,
    },
}

-- ─────────────────────────────────────────────
--  Props (Modelle)
-- ─────────────────────────────────────────────
Config.Props = {
    cone          = 'prop_mp_cone_01',
    barrierPost   = 'prop_barrier_wat_03a',
    lightStand    = 'prop_worklight_03a',
    oilPatch      = 'prop_oil_slick_01',
    warningSign   = 'prop_mp_arrow_barrier_01',
    flare         = 'prop_flare_01',
}

-- ─────────────────────────────────────────────
--  ox_target – Konfiguration
-- ─────────────────────────────────────────────
Config.Target = {
    icon     = 'fas fa-fire-extinguisher',
    distance = 2.0,
}
