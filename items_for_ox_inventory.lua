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
['hydraulicspreader'] = {
    label       = 'Hydraulikspreizer',
    weight      = 15000,
    stack       = false,
    close       = true,
    description = 'Hydraulischer Rettungsspreizer – Fahrzeugtüren öffnen',
},

['rescuesaw'] = {
    label       = 'Rettungssäge',
    weight      = 12000,
    stack       = false,
    close       = true,
    description = 'Rettungssäge – Dach und Türen aufschneiden',
},

['tirecutters'] = {
    label       = 'Reifenschneider',
    weight      = 5000,
    stack       = false,
    close       = true,
    description = 'Reifenschneider für Fahrzeugextrication',
},

-- ── HazMat ───────────────────────────────────────────────
['oilbarrier'] = {
    label       = 'Ölsperre',
    weight      = 3000,
    stack       = true,
    close       = false,
    description = 'Platzierbare Ölsperre / Barriere',
},

['oilabsorbent'] = {
    label       = 'Ölbindemittel',
    weight      = 2000,
    stack       = true,
    close       = true,
    description = 'Ölbindemittel – auf Kraftstoffaustritt auftragen',
},

['broom'] = {
    label       = 'Besen',
    weight      = 1500,
    stack       = false,
    close       = false,
    description = 'Besen – Ölbindemittel zusammenkehren',
},

['hazmatsuit'] = {
    label       = 'HazMat Anzug',
    weight      = 8000,
    stack       = false,
    close       = true,
    description = 'Schutzanzug für HazMat-Einsätze',
},

['deconkit'] = {
    label       = 'Dekontaminationskit',
    weight      = 3000,
    stack       = true,
    close       = true,
    description = 'Dekontaminationskit – entfernt Kontamination von Spielern',
},

-- ── Scene Management ─────────────────────────────────────
['trafficcone'] = {
    label       = 'Verkehrskegel',
    weight      = 2000,
    stack       = true,
    close       = false,
    description = 'Verkehrskegel zur Absicherung der Einsatzstelle',
},

['safetybarrier'] = {
    label       = 'Absperrband',
    weight      = 4000,
    stack       = true,
    close       = false,
    description = 'Absperrband / Barriere für die Einsatzstelle',
},

['lightstand'] = {
    label       = 'Lichtmast',
    weight      = 10000,
    stack       = false,
    close       = false,
    description = 'Tragbarer Lichtmast für Nachteinsätze',
},

-- ── Equipment ────────────────────────────────────────────
['thermocam'] = {
    label       = 'Wärmebildkamera',
    weight      = 3000,
    stack       = false,
    close       = true,
    description = 'Wärmebildkamera zur Personensuche',
},

['fireextinguisher'] = {
    label       = 'Feuerlöscher',
    weight      = 8000,
    stack       = false,
    close       = false,
    description = 'Tragbarer CO₂-Feuerlöscher',
},

['ladder'] = {
    label       = 'Leiter',
    weight      = 12000,
    stack       = false,
    close       = false,
    description = 'Tragbare Leiter für den Feuerwehreinsatz',
},

['gasmask'] = {
    label       = 'Atemschutzmaske',
    weight      = 2000,
    stack       = false,
    close       = true,
    description = 'Atemschutzmaske – Schutz vor Rauch und Gasen',
},

-- ── Patient ──────────────────────────────────────────────
['spineboard'] = {
    label       = 'Spineboard',
    weight      = 7000,
    stack       = false,
    close       = false,
    description = 'Spineboard zur Patientenstabilisierung',
},

['triagetag'] = {
    label       = 'Triage-Tag',
    weight      = 100,
    stack       = true,
    close       = false,
    description = 'Triage-Markierung (Rot / Gelb / Grün / Schwarz)',
},