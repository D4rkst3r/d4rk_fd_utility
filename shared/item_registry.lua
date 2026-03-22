---------------------------------------------------
--  d4rk_fd_utility – Item Registry
--  Registriert alle Items automatisch bei ox_inventory
---------------------------------------------------

-- Wird nur server-seitig ausgeführt (in server/main.lua aufgerufen)
-- Hier kannst du zusätzliche Item-Metadaten definieren

ItemRegistry = {}

ItemRegistry.Definitions = {
    hydraulicSpreader = {
        weight      = 15000,
        stack       = false,
        close       = true,
        description = 'Hydraulischer Rettungsspreizer – Fahrzeugtüren öffnen',
    },
    rescueSaw = {
        weight      = 12000,
        stack       = false,
        close       = true,
        description = 'Rettungssäge – Dach und Türen aufschneiden',
    },
    tireCutter = {
        weight      = 5000,
        stack       = false,
        close       = true,
        description = 'Reifenschneider für Extrication',
    },
    oilBarrier = {
        weight      = 3000,
        stack       = true,
        close       = false,
        description = 'Platzierbare Ölsperre / Barriere',
    },
    hazmatSuit = {
        weight      = 8000,
        stack       = false,
        close       = true,
        description = 'Schutzanzug für HazMat-Einsätze',
    },
    trafficCone = {
        weight      = 2000,
        stack       = true,
        close       = false,
        description = 'Verkehrskegel zur Absicherung',
    },
    safetyBarrier = {
        weight      = 4000,
        stack       = true,
        close       = false,
        description = 'Absperrband / Barrier',
    },
    lightStand = {
        weight      = 10000,
        stack       = false,
        close       = false,
        description = 'Tragbarer Lichtmast für Nachteinsätze',
    },
    thermoCam = {
        weight      = 3000,
        stack       = false,
        close       = true,
        description = 'Wärmebildkamera',
    },
    fireExtinguisher = {
        weight      = 8000,
        stack       = false,
        close       = false,
        description = 'Tragbarer Feuerlöscher',
    },
    spineboard = {
        weight      = 7000,
        stack       = false,
        close       = false,
        description = 'Spineboard für Patientenstabilisierung',
    },
    triageTag = {
        weight      = 100,
        stack       = true,
        close       = false,
        description = 'Triage-Markierung (Rot/Gelb/Grün/Schwarz)',
    },
}

---@param itemName string
---@return table|nil
function ItemRegistry.Get(itemName)
    return ItemRegistry.Definitions[itemName]
end
