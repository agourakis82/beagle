# Beagle Schumann-resonance extractor — one-shot CronJob entrypoint.
# Reads the Tomsk SOS spectrogram PNG, extracts SR harmonic amplitude via its colorbar,
# upserts schumann_f1/f2/f3 into the physiome space_weather table. Build context = repo root.
FROM python:3.12-slim
WORKDIR /app
COPY apps/schumann/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY apps/schumann/extract.py ./
CMD ["python", "extract.py"]
