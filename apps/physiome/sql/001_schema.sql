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

-- AUTOVACUUM COM LIMIAR ABSOLUTO (13-ago-2026).
--
-- Medido: health_samples tinha 1.736.445 linhas e o pg_stat estimava 17.305 — erro
-- de 100x. autovacuum e autoanalyze NUNCA haviam rodado nesta tabela, enquanto
-- rodavam normalmente nas vizinhas (space_weather_hires, weather_obs).
--
-- A causa e o gatilho PROPORCIONAL: autovacuum_analyze_scale_factor=0.1 exige 10%
-- da tabela modificada. Com 1,7 milhao de linhas isso sao 173 mil modificacoes, e o
-- ingest entra a conta-gotas — nunca cruza. A tabela foi carregada de uma vez pela
-- importacao historica e ficou orfa desde entao.
--
-- Consequencia: o planejador montava plano para TODA consulta desta tabela achando
-- que ela tinha 17 mil linhas. Um ANALYZE manual levou 0,3 s e corrigiu.
--
-- Limiar absoluto nao escala com o tamanho, entao nao pode starvar de novo.
-- Qualquer tabela grande alimentada a conta-gotas precisa do mesmo tratamento.
ALTER TABLE health_samples SET (
  autovacuum_analyze_scale_factor = 0.0,
  autovacuum_analyze_threshold    = 20000,
  autovacuum_vacuum_scale_factor  = 0.0,
  autovacuum_vacuum_threshold     = 50000
);

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
-- 2026-07: separate STATION weather (Open-Meteo model at the GPS location; temp_c/pressure_hpa)
-- from the user's true AMBIENT signals — the iPhone barometer's exact local pressure + altitude
-- (CMAltimeter) — plus the reverse-geocoded place. Ambient temperature is NOT captured: Apple
-- exposes no air-temperature sensor (only external BLE would). All nullable/idempotent.
ALTER TABLE weather_obs ADD COLUMN IF NOT EXISTS ambient_pressure_hpa DOUBLE PRECISION;
ALTER TABLE weather_obs ADD COLUMN IF NOT EXISTS altitude_m           DOUBLE PRECISION;
ALTER TABLE weather_obs ADD COLUMN IF NOT EXISTS city                 TEXT;
ALTER TABLE weather_obs ADD COLUMN IF NOT EXISTS place                TEXT;
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

-- High-resolution (native-cadence) space-weather series for intraday scientific correlation.
-- Long/EAV format so any metric at any cadence lands here with NO schema change: solar wind
-- speed + Bz are ingested at their native ~1-minute resolution (NOAA rtsw_*_1m, active source),
-- and X-ray / SME / quasi-real-time SYM-H can follow the same shape later. The coarse
-- `space_weather` snapshot table stays as-is (the "current value" card + daily aggregates);
-- this table is the fine substrate the intraday correlation model will join physiology against.
CREATE TABLE IF NOT EXISTS space_weather_hires (
  ts     TIMESTAMPTZ NOT NULL,
  metric TEXT        NOT NULL,   -- e.g. 'solar_wind_speed', 'bz', 'xray_flux'
  value  DOUBLE PRECISION NOT NULL,
  source TEXT,
  PRIMARY KEY (metric, ts)
);
CREATE INDEX IF NOT EXISTS space_weather_hires_metric_ts ON space_weather_hires (metric, ts DESC);
