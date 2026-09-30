# Built from the repository root (docker-compose sets context: .) so the image
# can include content/language-packs alongside the API code.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY backend/app ./app
COPY backend/db ./db
COPY content/language-packs ./content/language-packs
ENV LANGUAGE_PACKS_DIR=/srv/content/language-packs

RUN useradd --system --uid 10001 neuro && mkdir -p /srv/uploads && chown neuro /srv/uploads
USER neuro

# Trust X-Forwarded-For only from the reverse proxy / dashboard (comma-separated IPs),
# otherwise clients could spoof their IP to dodge per-IP limits.
ENV FORWARDED_ALLOW_IPS=127.0.0.1
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
