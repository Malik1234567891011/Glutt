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
COPY fixtures ./fixtures

ENV MEDIA_DATA_DIR=/data
ENV WORK_DIR=/work
RUN mkdir -p /data /work

CMD ["npm", "run", "worker"]
