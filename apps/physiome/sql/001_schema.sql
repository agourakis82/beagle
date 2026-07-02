-- Beagle Physiome raw time-series store (sovereign; beagle-pg).
CREATE TABLE IF NOT EXISTS health_samples (
  uuid     UUID PRIMARY KEY,
  ts       TIMESTAMPTZ NOT NULL,
  end_ts   TIMESTAMPTZ,
  type     TEXT NOT NULL,
  value    DOUBLE PRECISION,
  unit     TEXT,
  source   TEXT,
  device   TEXT,
  metadata JSONB DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS health_samples_type_ts ON health_samples (type, ts);

CREATE TABLE IF NOT EXISTS weather_obs (
  ts           TIMESTAMPTZ NOT NULL,
  lat          DOUBLE PRECISION NOT NULL,
  lon          DOUBLE PRECISION NOT NULL,
  temp_c       DOUBLE PRECISION,
  pressure_hpa DOUBLE PRECISION,
  humidity     DOUBLE PRECISION,
  uv_index     DOUBLE PRECISION,
  precip       DOUBLE PRECISION,
  aqi          DOUBLE PRECISION,
  condition    TEXT,
  metadata     JSONB DEFAULT '{}'::jsonb,
  PRIMARY KEY (ts, lat, lon)
);

CREATE TABLE IF NOT EXISTS space_weather (
  ts               TIMESTAMPTZ PRIMARY KEY,
  kp               DOUBLE PRECISION,
  dst              DOUBLE PRECISION,
  f107             DOUBLE PRECISION,
  solar_wind_speed DOUBLE PRECISION,
  bz               DOUBLE PRECISION,
  source           TEXT
);
-- ensureSchema re-runs this file on every boot; the CREATE above is a no-op once the
-- table exists, so add dst to already-provisioned DBs idempotently here.
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS dst DOUBLE PRECISION;
-- 2026-07: high-cadence GFZ Hp30/Hp60 (30/60-min geomagnetic, finer than 3-hourly Kp)
-- + NMDB neutron-monitor rate (galactic cosmic ray / Forbush context). Fail-soft: null
-- when the upstream feed is missing, same as solar_wind_speed/bz.
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS hp30            DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS ap30            DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS hp60            DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS cosmic_ray_oulu DOUBLE PRECISION;
-- Schumann-resonance harmonic amplitude (relative 0..1), extracted from the Tomsk SOS
-- spectrogram image by apps/schumann (there is no numeric feed). EXPLORATORY proxy.
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f1     DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f2     DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f3     DOUBLE PRECISION;
-- 2026-07: NOAA GOES + OVATION + OMNI heliophysics channels. Fail-soft: null when the
-- upstream feed is missing, same as solar_wind_speed/cosmic_ray_oulu.
--   xray_flux    = GOES long-channel (0.1-0.8nm) X-ray flux W/m² (flare C/M/X context)
--   proton_flux  = GOES integral >=10 MeV proton flux protons/cm²/s (radiation-storm S-scale)
--   aurora_power = OVATION hemispheric-power proxy (summed grid aurora index, arb. units)
--   sym_h/ae_index = OMNI_HRO_1MIN ring-current / auroral-electrojet indices (nT). RETROSPECTIVE:
--     OMNI has ~40-day latency, so these are usually null in the live snapshot and only
--     backfilled for historical rows via ON CONFLICT.
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS xray_flux       DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS proton_flux     DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS aurora_power    DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS sym_h           DOUBLE PRECISION;
ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS ae_index        DOUBLE PRECISION;
