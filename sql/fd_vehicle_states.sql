-- =========================================================
--  d4rk_fd_utility – Datenbank Tabelle
--  Einmalig auf dem Server ausführen
-- =========================================================

CREATE TABLE IF NOT EXISTS `fd_vehicle_states` (
    `id`          INT           NOT NULL AUTO_INCREMENT,
    `plate`       VARCHAR(20)   NOT NULL,
    `state_key`   VARCHAR(50)   NOT NULL,
    `state_value` VARCHAR(255)  NOT NULL,
    `updated_at`  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_state` (`plate`, `state_key`),
    INDEX `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =========================================================
--  State Keys Referenz (was in state_key gespeichert wird)
-- =========================================================
--
--  Extrication:
--    door_0 ... door_5    BOOL   Tür entfernt
--    tire_0 ... tire_5    BOOL   Reifen entfernt
--    window_0 .. window_7 BOOL  Scheibe eingeschlagen
--    roof                 BOOL   Dach aufgeschnitten
--    airbag               BOOL   Airbag deaktiviert
--    battery              BOOL   Batterie entfernt
--    stabilized           BOOL   Fahrzeug stabilisiert
--
--  HazMat (kommt später):
--    fuel_leak            BOOL   Kraftstoff leckt
--    hazmat_zone          BOOL   Als Gefahrgut markiert
--
--  Andere Scripts lesen einfach:
--    SELECT * FROM fd_vehicle_states WHERE plate = 'ABC123';
--
-- =========================================================