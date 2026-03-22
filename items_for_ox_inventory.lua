--[[
    =========================================================
    d4rk_fd_utility – Items für ox_inventory
    =========================================================
    Diese Einträge gehören in:
        ox_inventory/data/items.lua

    Einfach alles unterhalb dieser Kommentare ans Ende der
    Datei kopieren (vor der letzten schließenden Klammer).
    =========================================================
--]]

-- ── Extrication ─────────────────────────────────────────
['hydraulicSpreader'] = {
    label       = 'Hydraulikspreizer',
    weight      = 15000,
    stack       = false,
    close       = true,
    description = 'Hydraulischer Rettungsspreizer – Fahrzeugtüren öffnen',
},

['rescueSaw'] = {
    label       = 'Rettungssäge',
    weight      = 12000,
    stack       = false,
    close       = true,
    description = 'Rettungssäge – Dach und Türen aufschneiden',
},

['tireCutter'] = {
    label       = 'Reifenschneider',
    weight      = 5000,
    stack       = false,
    close       = true,
    description = 'Reifenschneider für Fahrzeugextrication',
},

-- ── HazMat ───────────────────────────────────────────────
['oilBarrier'] = {
    label       = 'Ölsperre',
    weight      = 3000,
    stack       = true,
    close       = false,
    description = 'Platzierbare Ölsperre / Barriere',
},

['hazmatSuit'] = {
    label       = 'HazMat Anzug',
    weight      = 8000,
    stack       = false,
    close       = true,
    description = 'Schutzanzug für HazMat-Einsätze',
},

-- ── Scene Management ─────────────────────────────────────
['trafficCone'] = {
    label       = 'Verkehrskegel',
    weight      = 2000,
    stack       = true,
    close       = false,
    description = 'Verkehrskegel zur Absicherung der Einsatzstelle',
},

['safetyBarrier'] = {
    label       = 'Absperrband',
    weight      = 4000,
    stack       = true,
    close       = false,
    description = 'Absperrband / Barriere für die Einsatzstelle',
},

['lightStand'] = {
    label       = 'Lichtmast',
    weight      = 10000,
    stack       = false,
    close       = false,
    description = 'Tragbarer Lichtmast für Nachteinsätze',
},

-- ── Equipment ────────────────────────────────────────────
['thermoCam'] = {
    label       = 'Wärmebildkamera',
    weight      = 3000,
    stack       = false,
    close       = true,
    description = 'Wärmebildkamera zur Personensuche',
},

['fireExtinguisher'] = {
    label       = 'Feuerlöscher',
    weight      = 8000,
    stack       = false,
    close       = false,
    description = 'Tragbarer CO₂-Feuerlöscher',
},

-- ── Patient ──────────────────────────────────────────────
['spineboard'] = {
    label       = 'Spineboard',
    weight      = 7000,
    stack       = false,
    close       = false,
    description = 'Spineboard zur Patientenstabilisierung',
},

['triageTag'] = {
    label       = 'Triage-Tag',
    weight      = 100,
    stack       = true,
    close       = false,
    description = 'Triage-Markierung (Rot / Gelb / Grün / Schwarz)',
},
