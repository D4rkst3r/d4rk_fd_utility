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

-- HazMat – Konfiguration
Config.HazMat = {
    oilBarrierSpacing       = 1.5,     -- Abstand zwischen Ölsperren-Props (Meter)
    zoneColor               = { r = 255, g = 165, b = 0,   a = 80  },
    zoneColorBorder         = { r = 255, g = 100, b = 0,   a = 200 },
    suitProtection          = 100,     -- Schutz-Level mit Anzug (0-100)
    deconTime               = 15000,   -- Dekontamination Dauer (ms)
    autoContaminate         = true,    -- Spieler ohne Anzug in Zone kontaminieren
    contaminateCheckInterval = 2000,   -- Kontaminierungs-Check Interval (ms)
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
    hydraulicspreader = {
        label      = 'Hydraulikspreizer',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 8000,   -- ms
    },
    rescuesaw = {
        label      = 'Rettungssäge',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 10000,
    },
    tirecutters = {
        label      = 'Reifenschneider',
        required   = true,
        consume    = false,
        durability = true,
        useTime    = 5000,
    },
    -- HazMat
    oilbarrier = {
        label      = 'Ölsperre',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 3000,
    },
    oilabsorbent = {
        label      = 'Ölbindemittel',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 5000,
    },
    broom = {
        label      = 'Besen',
        required   = true,
        consume    = false,
        durability = false,
        useTime    = 0,
    },
    hazmatsuit = {
        label      = 'HazMat Anzug',
        required   = false,
        consume    = false,
        durability = true,
        useTime    = 0,
    },
    deconkit = {
        label      = 'Dekontaminationskit',
        required   = true,
        consume    = true,
        durability = false,
        useTime    = 0,
    },
    -- Scene Management
    trafficcone = {
        label      = 'Verkehrskegel',
        required   = true,
        consume    = false,   -- Wird in scene.lua manuell verwaltet (Aufheben gibt Item zurück)
        durability = false,
        useTime    = 1500,
    },
    safetybarrier = {
        label      = 'Absperrband',
        required   = true,
        consume    = false,   -- Wird in scene.lua manuell verwaltet
        durability = false,
        useTime    = 2000,
    },
    lightstand = {
        label      = 'Lichtmast',
        required   = true,
        consume    = false,
        durability = false,
        useTime    = 4000,
    },
    -- Equipment
    thermocam = {
        label      = 'Wärmebildkamera',
        required   = false,
        consume    = false,
        durability = false,
        useTime    = 0,
    },
    fireextinguisher = {
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
    triagetag = {
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
    lightPlace   = 3000,
    extract      = 10000,
    triage       = 2000,
}

-- ─────────────────────────────────────────────
--  Prop Limits – Max platzierte Props pro Spieler
-- ─────────────────────────────────────────────
Config.Limits = {
    cones        = 12,
    barriers     = 8,
    lightstands  = 4,
    oilPatches   = 6,
    fireSigns    = 6,
    flares       = 8,
}

-- ─────────────────────────────────────────────
--  Scene Management Konfiguration
-- ─────────────────────────────────────────────
Config.Scene = {
    -- Abstand vor dem Spieler beim Platzieren (Meter)
    placeDistance  = 2.5,

    -- Raycast-Reichweite beim Preview (Meter)
    raycastDistance = 15.0,

    -- Lichtmast: Lichtfarbe (RGB)
    lightColor     = { r = 255, g = 220, b = 150 },
    lightIntensity = 10.0,
    lightRange     = 15.0,

    -- Prop-Rotation beim Platzieren in Spieler-Heading-Richtung
    alignToPlayer  = true,

    -- Radial-Menü Keybind (ox_lib)
    radialKey      = 'F5',
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
        dict  = 'amb@world_human_gardener_plant@male@base',
        clip  = 'base',
        flag  = 1,
    },
    place = {
        dict  = 'amb@world_human_gardener_plant@male@base',
        clip  = 'base',
        flag  = 49,
    },
    pour = {
        dict  = 'weapons@first_person@aim_idle@remote_clone@misc@jerrycan@',
        clip  = 'fire',
        flag  = 1,
        -- TODO: Hand-Prop prop_ld_jerrycan_01 während Animation spawnen
    },
    sweep = {
        dict  = 'anim@amb@drug_field_workers@rake@male_b@base',
        clip  = 'base',
        flag  = 1,
        -- TODO: Hand-Prop prop_tool_broom2 während Animation spawnen
    },
}

-- ─────────────────────────────────────────────
--  Props (Modelle)
-- ─────────────────────────────────────────────
Config.Props = {
    -- Extrication
    wheel         = 'prop_byard_tyres_01',

    -- Scene Management
    cone          = 'prop_mp_cone_01',
    coneBig       = 'prop_mp_cone_04',
    barrier       = 'prop_barrier_wat_03a',
    barrierLong   = 'prop_barrier_wat_04a',
    lightstand    = 'prop_worklight_03a',
    lightstandBig = 'prop_worklight_04a',
    warningSign   = 'prop_mp_arrow_barrier_01',
    flare         = 'prop_flare_01',
    oilPatch      = 'p_oil_slick_01',       -- Automatisch unter Gefahrgut-Fahrzeug
    oilBarrier    = 'prop_conc_sacks_02a',  -- Vom Spieler platzierte Sperre (Item)
    -- TODO: Hand-Props während Animation
    -- jerrycan   = 'prop_ld_jerrycan_01',  -- Kanister in Hand beim Ausgießen
    -- broom      = 'prop_tool_broom2',     -- Besen in Hand beim Kehren
}

-- ─────────────────────────────────────────────
--  Prop Attachments
--  Daten aus d4rk_prop_tool – direkt hier eintragen
-- ─────────────────────────────────────────────
Config.Attachments = {
    -- ── HazMat ───────────────────────────────
    sweep = {
        prop     = 'prop_tool_broom2',
        bone     = 'SKEL_R_Hand',
        boneId   = 28422,
        offset   = { x = -0.02, y = 0.02, z = -0.565 },
        rotation = { x = -38.5, y = 1.0,  z = 2.0    },
        animDict = 'anim@amb@drug_field_workers@rake@male_b@base',
        animClip = 'base',
    },
    pour = {
        prop     = 'prop_ld_jerrycan_01',
        boneId   = 28422,
        offset   = { x = 0.085, y = 0.015, z = -0.04 },
        rotation = { x = -9.0,  y = -94.5, z = 171.0 },
        animDict = 'weapons@first_person@aim_idle@remote_clone@misc@jerrycan@',
        animClip = 'fire',
    },

    -- ── Extrication ──────────────────────────
    -- Offsets mit d4rk_prop_tool suchen, dann hier eintragen
    spreizer = {
        prop     = 'prop_tool_blowtorch',  -- Platzhalter → ersetzen wenn gefunden
        boneId   = 28422,
        offset   = { x = 0.0, y = 0.0, z = 0.0 },
        rotation = { x = 0.0, y = 0.0, z = 0.0 },
        animDict = 'amb@world_human_gardener_plant@male@base',
        animClip = 'base',
    },
    saw = {
        prop     = 'prop_tool_grinder',    -- Platzhalter → ersetzen wenn gefunden
        boneId   = 28422,
        offset   = { x = 0.0, y = 0.0, z = 0.0 },
        rotation = { x = 0.0, y = 0.0, z = 0.0 },
        animDict = 'amb@world_human_gardener_plant@male@base',
        animClip = 'base',
    },
    tirecutters = {
        prop     = 'prop_tool_pliers',     -- Platzhalter → ersetzen wenn gefunden
        boneId   = 28422,
        offset   = { x = 0.0, y = 0.0, z = 0.0 },
        rotation = { x = 0.0, y = 0.0, z = 0.0 },
        animDict = 'amb@world_human_gardener_plant@male@base',
        animClip = 'base',
    },
}
Config.Target = {
    icon     = 'fas fa-fire-extinguisher',
    distance = 4.0,
}