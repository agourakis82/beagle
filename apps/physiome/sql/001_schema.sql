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
