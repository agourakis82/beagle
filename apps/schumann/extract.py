#!/usr/bin/env python3
"""Schumann-resonance amplitude extractor for the Beagle physiome ingest.

There is no clean numeric Schumann feed — the observatories (Tomsk, Cumiana) publish
rendered spectrogram PNGs, not data. So we do our own extraction from the Tomsk SOS
spectrogram (http://sosrff.tsu.ru/new/shm.jpg): read the image's own colorbar as a
colour->value LUT, then read the resonance-line amplitude in a window around each SR
harmonic (7.83 / 14.3 / 20.8 Hz) at the most-recent time column.

HONESTY: this is a PROXY derived from a third-party JPEG render — RELATIVE units (0..1),
NOT calibrated field strength, and dependent on the upstream image template. It is an
EXPLORATORY signal: the physiological evidence base (Schumann -> HRV/affect) did not
survive adversarial verification. Pre-register any hypothesis using it as speculative.

Fail-soft throughout: any fetch/parse/geometry failure logs and exits 0 without writing,
so a bad upstream image never crashes the CronJob or writes garbage.
"""
import os
import sys
from datetime import datetime, timezone

import numpy as np
import requests
from PIL import Image

IMAGE_URL = os.environ.get("SCHUMANN_IMAGE_URL", "http://sosrff.tsu.ru/new/shm.jpg")
DSN = os.environ.get("PHYSIOME_PG_DSN")

# --- Tomsk shm.jpg template geometry (stable layout; validated against SR harmonic
# positions: detected peaks land at 8.3 Hz ~ fundamental and exactly 14.3 Hz). ---
EXPECTED_SIZE = (1540, 460)
CBX, CB_TOP, CB_BOT = 1519, 22, 430   # colorbar column + vertical extent
Y0_HZ, Y40_HZ = 18, 445               # pixel rows for 0 Hz (top) and 40 Hz (bottom)
XL, XR = 58, 1450                     # plotting area x-range (data, left of the logo)
HARMONICS_HZ = [7.83, 14.3, 20.8]     # fundamental + 2 harmonics (strongest/most-studied)
BAND_HZ = 1.0                         # ± window absorbing small calibration drift


def log(msg):
    print(f"[schumann] {msg}", flush=True)


def fetch_image():
    # Prefer a verified TLS connection. sosrff.tsu.ru currently 301-redirects http->https
    # and ships an EXPIRED cert, so verification fails today; degrade to unverified ONLY on
    # a TLS error (public university host, public non-sensitive JPEG, exploratory signal —
    # and the size check + fail-soft extraction bound what a tampered image could do). If
    # Tomsk ever renews the cert, verification silently resumes.
    from io import BytesIO
    hdrs = {"User-Agent": "beagle-physiome-schumann/1 (research)"}
    try:
        r = requests.get(IMAGE_URL, timeout=25, allow_redirects=True, verify=True, headers=hdrs)
    except requests.exceptions.SSLError as e:
        log(f"TLS verify failed ({e}); upstream cert is expired — retrying unverified")
        r = requests.get(IMAGE_URL, timeout=25, allow_redirects=True, verify=False, headers=hdrs)
    r.raise_for_status()
    return np.asarray(Image.open(BytesIO(r.content)).convert("RGB")).astype(float)


def extract(im):
    h, w, _ = im.shape
    if (w, h) != EXPECTED_SIZE:
        raise ValueError(f"unexpected image size {w}x{h}, template calibration invalid")

    # colorbar LUT: value 1.0 = top (white/high) .. 0.0 = bottom (black/low)
    cb = im[CB_TOP:CB_BOT, CBX, :]
    cbv = 1.0 - (np.arange(CB_TOP, CB_BOT) - CB_TOP) / (CB_BOT - CB_TOP)

    def val(px):
        return float(cbv[np.argmin(((cb - px) ** 2).sum(1))])

    def hz2y(hz):
        return Y0_HZ + (hz / 40.0) * (Y40_HZ - Y0_HZ)

    # latest-data column: the 3-day image is filled black on the right for not-yet-recorded
    # time. Real data (even low power) carries a blue haze; pure-black future does not.
    blue_frac = (im[Y0_HZ:Y40_HZ, XL:XR, 2] > 28).mean(axis=0)
    cols = np.where(blue_frac > 0.15)[0] + XL
    if len(cols) == 0:
        raise ValueError("no data columns found (blank/blocked image)")
    x_now = int(cols.max())

    def harmonic(hz):
        y_lo, y_hi = int(hz2y(hz - BAND_HZ)), int(hz2y(hz + BAND_HZ))
        peaks = []
        for x in range(max(XL, x_now - 5), x_now + 1):    # avg last ~6 time columns
            band = [val(im[y, x]) for y in range(y_lo, y_hi + 1)]
            peaks.append(max(band))                       # peak of the band = the resonance line
        return round(float(np.mean(peaks)), 4)

    return {f"schumann_f{i + 1}": harmonic(hz) for i, hz in enumerate(HARMONICS_HZ)}


def upsert(vals):
    # Round to the nearest 30-min grid (Hp30 cadence) so daily aggregation aligns cleanly.
    import psycopg2  # deferred: only the DB path needs the driver (keeps extract testable)

    now = datetime.now(timezone.utc)
    ts = now.replace(minute=(0 if now.minute < 30 else 30), second=0, microsecond=0)
    conn = psycopg2.connect(DSN)
    try:
        with conn, conn.cursor() as cur:
            cur.execute(
                "ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f1 DOUBLE PRECISION;"
                "ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f2 DOUBLE PRECISION;"
                "ALTER TABLE space_weather ADD COLUMN IF NOT EXISTS schumann_f3 DOUBLE PRECISION;"
            )
            cur.execute(
                """INSERT INTO space_weather (ts, schumann_f1, schumann_f2, schumann_f3, source)
                   VALUES (%s,%s,%s,%s,'tomsk-sos-image')
                   ON CONFLICT (ts) DO UPDATE SET
                     schumann_f1=EXCLUDED.schumann_f1, schumann_f2=EXCLUDED.schumann_f2,
                     schumann_f3=EXCLUDED.schumann_f3""",
                (ts, vals["schumann_f1"], vals["schumann_f2"], vals["schumann_f3"]),
            )
        return ts.isoformat()
    finally:
        conn.close()


def main():
    if not DSN:
        log("PHYSIOME_PG_DSN not set — abort")
        return 1
    try:
        import urllib3
        urllib3.disable_warnings()  # quiet the expired-cert InsecureRequestWarning
    except Exception:
        pass
    try:
        im = fetch_image()
        vals = extract(im)
    except Exception as e:  # fail-soft: never write garbage, never crash the CronJob
        log(f"extraction failed ({type(e).__name__}: {e}) — skipping write")
        return 0
    try:
        ts = upsert(vals)
        log(f"upserted ts={ts} {vals}")
    except Exception as e:
        log(f"db upsert failed ({type(e).__name__}: {e})")
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
