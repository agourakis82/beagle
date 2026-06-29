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
