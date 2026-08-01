FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    python3 \
    python3-pip \
    ca-certificates \
    curl \
  && pip3 install --no-cache-dir --break-system-packages yt-dlp \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
COPY scripts ./scripts
COPY fixtures ./fixtures

ENV MEDIA_DATA_DIR=/data
ENV WORK_DIR=/work
ENV YT_DLP_BIN=yt-dlp
RUN mkdir -p /data /work

# The Supabase claim loop, not `npm run worker` — the latter drains the local
# JSON store, which is empty in a fresh container, so nothing would ever run.
# Needs SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in the environment.
CMD ["npm", "run", "claim:supabase", "--", "--loop", "--interval=30"]
