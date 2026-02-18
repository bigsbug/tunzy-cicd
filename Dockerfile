# ---------- FRONTEND BUILD ----------
FROM node:20-alpine AS frontend-build

WORKDIR /frontend

COPY tunzy-frontend/package*.json ./
RUN npm ci

COPY tunzy-frontend/ .
ENV VITE_REACT_APP_BASE_URL_API="/api"
RUN npm run build


# ---------- PYTHON DEP BUILD ----------
FROM python:3.12-slim AS python-build

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /backend

# install minimal tools just for dependency install
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# install uv
RUN curl -Ls https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# copy dependency files first (better cache)
COPY tunzy-backend/pyproject.toml \
     tunzy-backend/uv.lock ./

# install only production deps, no cache
RUN uv sync --no-dev --no-cache

# copy backend source
COPY tunzy-backend .

# ---- FFMPEG BUILDER ----
FROM debian:bookworm-slim AS ffmpeg-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

ADD https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz /tmp/ffmpeg.tar.xz

RUN tar -xJf /tmp/ffmpeg.tar.xz -C /tmp \
    && mv /tmp/ffmpeg-*-static/ffmpeg /ffmpeg \
    && mv /tmp/ffmpeg-*-static/ffprobe /ffprobe

# ---------- FINAL RUNTIME ----------
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /backend

# add uv
COPY --from=python-build /root/.local /root/.local
ENV PATH="/root/.local/bin:$PATH"



# Install ONLY minimal runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---- Install ffmpeg ----
COPY --from=ffmpeg-build /ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-build /ffprobe /usr/local/bin/ffprobe

# copy python environment from builder
COPY --from=python-build /usr/local /usr/local

# copy backend source
COPY --from=python-build /backend /backend

# copy frontend build
COPY --from=frontend-build /frontend/dist ./static/frontend

# data folder
RUN mkdir -p /data/musics

ENV db_url="sqlite:////data/data.db"
ENV download_folder="/data/musics"


EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
