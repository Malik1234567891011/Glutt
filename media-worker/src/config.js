import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

function env(name, fallback = "") {
  const v = process.env[name];
  return v == null || v === "" ? fallback : v;
}

export const config = {
  root,
  dataDir: path.resolve(env("MEDIA_DATA_DIR", path.join(root, "data"))),
  workDir: path.resolve(env("WORK_DIR", path.join(root, "work"))),
  storePath: path.resolve(env("MEDIA_STORE_PATH", path.join(root, "data", "store.json"))),
  maxDurationSeconds: Number(env("MEDIA_MAX_DURATION_S", "1200")),
  maxDownloadBytes: Number(env("MEDIA_MAX_DOWNLOAD_BYTES", String(800 * 1024 * 1024))),
  maxRedirects: Number(env("MEDIA_MAX_REDIRECTS", "5")),
  ytDlpBin: env("YT_DLP_BIN") || path.join(root, "bin", "yt-dlp"),
  ffmpegBin: env("FFMPEG_BIN", "ffmpeg"),
  ffprobeBin: env("FFPROBE_BIN", "ffprobe"),
  workerId: env("WORKER_ID", `worker-${process.pid}`),
  leaseSeconds: Number(env("JOB_LEASE_SECONDS", "900")),
  localPlaybackPort: Number(env("LOCAL_PLAYBACK_PORT", "8791")),
  // Optional cloud backends — empty = local filesystem archive.
  r2: {
    accountId: env("R2_ACCOUNT_ID"),
    accessKeyId: env("R2_ACCESS_KEY_ID"),
    secretAccessKey: env("R2_SECRET_ACCESS_KEY"),
    bucket: env("R2_BUCKET", "glutt-media"),
    publicBase: env("R2_PUBLIC_BASE", ""),
  },
  stream: {
    accountId: env("CF_STREAM_ACCOUNT_ID", env("R2_ACCOUNT_ID")),
    apiToken: env("CF_STREAM_API_TOKEN"),
  },
  supabase: {
    url: env("SUPABASE_URL"),
    serviceRoleKey: env("SUPABASE_SERVICE_ROLE_KEY"),
  },
  allowedHosts: new Set(
    (env(
      "MEDIA_ALLOWED_HOSTS",
      "youtube.com,www.youtube.com,youtu.be,m.youtube.com,tiktok.com,www.tiktok.com,vm.tiktok.com,vt.tiktok.com,instagram.com,www.instagram.com"
    ) || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean)
  ),
};

export function r2Enabled() {
  return Boolean(config.r2.accountId && config.r2.accessKeyId && config.r2.secretAccessKey);
}

export function streamEnabled() {
  return Boolean(config.stream.accountId && config.stream.apiToken);
}
