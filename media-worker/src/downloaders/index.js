import path from "node:path";
import fs from "node:fs/promises";
import { config } from "../config.js";
import { runCommand } from "../spawn.js";
import { detectPlatform, validateSourceUrl, youtubeExternalId } from "../security.js";

/**
 * @typedef {object} SourceProbe
 * @property {string} platform
 * @property {string} [externalId]
 * @property {string} [title]
 * @property {string} [uploader]
 * @property {number} [durationSeconds]
 * @property {string} [thumbnail]
 * @property {boolean} [hasSubtitles]
 * @property {object} [raw]
 */

/** @typedef {{ filePath: string, infoPath?: string, ext: string, probe: SourceProbe }} DownloadedSource */

class BaseDownloader {
  canHandle(_url) {
    return false;
  }

  async probe(_url) {
    throw new Error("not implemented");
  }

  async download(_url, _destinationDirectory) {
    throw new Error("not implemented");
  }
}

export class YouTubeDownloader extends BaseDownloader {
  canHandle(url) {
    return detectPlatform(url) === "youtube";
  }

  async probe(url) {
    validateSourceUrl(url.href);
    // YouTube SABR / web-client breakage: prefer android+ios players.
    const { stdout } = await runCommand(config.ytDlpBin, [
      "--dump-single-json",
      "--skip-download",
      "--no-playlist",
      "--extractor-args", "youtube:player_client=android,ios,web",
      url.href,
    ], { timeoutMs: 120000 });
    const raw = JSON.parse(stdout);
    if (raw.is_live) {
      throw Object.assign(new Error("Livestreams not supported"), { code: "LIVE_REJECTED" });
    }
    if (raw.playlist_count && raw.playlist_count > 1) {
      throw Object.assign(new Error("Playlists not supported"), { code: "PLAYLIST_REJECTED" });
    }
    const duration = Number(raw.duration) || 0;
    if (duration > config.maxDurationSeconds) {
      throw Object.assign(new Error(`Duration ${duration}s exceeds max ${config.maxDurationSeconds}s`), {
        code: "DURATION_TOO_LONG",
      });
    }
    const probe = {
      platform: "youtube",
      externalId: raw.id || youtubeExternalId(url),
      title: raw.title || null,
      uploader: raw.uploader || raw.channel || null,
      durationSeconds: duration || null,
      thumbnail: raw.thumbnail || null,
      hasSubtitles: Boolean((raw.subtitles && Object.keys(raw.subtitles).length) || (raw.automatic_captions && Object.keys(raw.automatic_captions).length)),
      width: raw.width || null,
      height: raw.height || null,
      fps: raw.fps || null,
      formats: (raw.formats || []).slice(0, 40).map((f) => ({
        format_id: f.format_id,
        ext: f.ext,
        resolution: f.resolution,
        vcodec: f.vcodec,
        acodec: f.acodec,
        filesize: f.filesize || f.filesize_approx || null,
      })),
      estimatedBytes: raw.filesize || raw.filesize_approx || null,
      rawSummary: {
        webpage_url: raw.webpage_url,
        ext: raw.ext,
        format: raw.format,
      },
    };
    return probe;
  }

  async download(url, destinationDirectory) {
    validateSourceUrl(url.href);
    await fs.mkdir(destinationDirectory, { recursive: true });
    const outTemplate = path.join(destinationDirectory, "source.%(ext)s");
    // Subs are best-effort: a 429 on fr/es must not fail the master download.
    await runCommand(config.ytDlpBin, [
      "--no-playlist",
      "--extractor-args", "youtube:player_client=android,ios,web",
      "-f", "bv*[height<=1080]+ba/b[height<=1080]/18/best",
      "--merge-output-format", "mp4",
      "--write-info-json",
      "--write-thumbnail",
      "--write-auto-subs",
      "--sub-langs", "en.*",
      "--ignore-no-formats-error",
      "--retries", "5",
      "-o", outTemplate,
      url.href,
    ], { timeoutMs: 20 * 60 * 1000 });

    const files = await fs.readdir(destinationDirectory);
    const media = files.find((f) => /^source\.(mp4|mkv|webm|mov)$/i.test(f));
    if (!media) {
      throw Object.assign(new Error(`No media file after download: ${files.join(",")}`), {
        code: "DOWNLOAD_MISSING_FILE",
      });
    }
    const filePath = path.join(destinationDirectory, media);
    const st = await fs.stat(filePath);
    if (st.size > config.maxDownloadBytes) {
      throw Object.assign(new Error("Downloaded file exceeds size ceiling"), { code: "FILE_TOO_LARGE" });
    }
    const infoName = files.find((f) => f.endsWith(".info.json"));
    const probe = await this.probe(url);
    return {
      filePath,
      infoPath: infoName ? path.join(destinationDirectory, infoName) : undefined,
      ext: path.extname(media).slice(1).toLowerCase(),
      probe,
      bytes: st.size,
    };
  }
}

export class TikTokDownloader extends BaseDownloader {
  canHandle(url) {
    return detectPlatform(url) === "tiktok";
  }

  async probe(url) {
    validateSourceUrl(url.href);
    // Do NOT reuse YouTube player_client args — they break TikTok extractors.
    const { stdout } = await runCommand(config.ytDlpBin, [
      "--dump-single-json",
      "--skip-download",
      "--no-playlist",
      url.href,
    ], { timeoutMs: 120000 });
    const raw = JSON.parse(stdout);
    if (raw.is_live) {
      throw Object.assign(new Error("Livestreams not supported"), { code: "LIVE_REJECTED" });
    }
    const duration = Number(raw.duration) || 0;
    if (duration > config.maxDurationSeconds) {
      throw Object.assign(new Error(`Duration ${duration}s exceeds max ${config.maxDurationSeconds}s`), {
        code: "DURATION_TOO_LONG",
      });
    }
    return {
      platform: "tiktok",
      externalId: raw.id || raw.display_id || null,
      title: raw.title || raw.description?.slice?.(0, 120) || null,
      uploader: raw.uploader || raw.creator || raw.channel || null,
      durationSeconds: duration || null,
      thumbnail: raw.thumbnail || null,
      hasSubtitles: Boolean(
        (raw.subtitles && Object.keys(raw.subtitles).length)
        || (raw.automatic_captions && Object.keys(raw.automatic_captions).length)
      ),
      width: raw.width || null,
      height: raw.height || null,
      fps: raw.fps || null,
      formats: (raw.formats || []).slice(0, 40).map((f) => ({
        format_id: f.format_id,
        ext: f.ext,
        resolution: f.resolution,
        vcodec: f.vcodec,
        acodec: f.acodec,
        filesize: f.filesize || f.filesize_approx || null,
      })),
      estimatedBytes: raw.filesize || raw.filesize_approx || null,
      rawSummary: {
        webpage_url: raw.webpage_url,
        ext: raw.ext,
        format: raw.format,
      },
    };
  }

  async download(url, destinationDirectory) {
    validateSourceUrl(url.href);
    await fs.mkdir(destinationDirectory, { recursive: true });
    const outTemplate = path.join(destinationDirectory, "source.%(ext)s");
    await runCommand(config.ytDlpBin, [
      "--no-playlist",
      // Prefer progressive h264+aac ("download" / h264_*). bytevc1/h265 TikTok
      // variants often claim aac in metadata but ship video-only — that kills
      // normalize→extractAudio and loses chef speech for analysis.
      "-f", "download/best[vcodec^=h264]/best[ext=mp4]/best",
      "--merge-output-format", "mp4",
      "--write-info-json",
      "--write-thumbnail",
      "--retries", "5",
      "-o", outTemplate,
      url.href,
    ], { timeoutMs: 20 * 60 * 1000 });

    const files = await fs.readdir(destinationDirectory);
    const media = files.find((f) => /^source\.(mp4|mkv|webm|mov)$/i.test(f));
    if (!media) {
      throw Object.assign(new Error(`No media file after download: ${files.join(",")}`), {
        code: "DOWNLOAD_MISSING_FILE",
      });
    }
    const filePath = path.join(destinationDirectory, media);
    const st = await fs.stat(filePath);
    if (st.size > config.maxDownloadBytes) {
      throw Object.assign(new Error("Downloaded file exceeds size ceiling"), { code: "FILE_TOO_LARGE" });
    }
    const probe = await this.probe(url);
    return {
      filePath,
      infoPath: files.find((f) => f.endsWith(".info.json"))
        ? path.join(destinationDirectory, files.find((f) => f.endsWith(".info.json")))
        : undefined,
      ext: path.extname(media).slice(1).toLowerCase(),
      probe: { ...probe, platform: "tiktok" },
      bytes: st.size,
    };
  }
}

export class InstagramDownloader extends BaseDownloader {
  canHandle(url) {
    return detectPlatform(url) === "instagram";
  }

  async probe(url) {
    const yt = new YouTubeDownloader();
    const probe = await yt.probe(url);
    return { ...probe, platform: "instagram" };
  }

  async download(url, destinationDirectory) {
    const yt = new YouTubeDownloader();
    const out = await yt.download(url, destinationDirectory);
    out.probe = { ...out.probe, platform: "instagram" };
    return out;
  }
}

export class DirectFileDownloader extends BaseDownloader {
  canHandle(url) {
    return /\.(mp4|mov|m4v|webm)(\?|$)/i.test(url.pathname);
  }

  async probe(url) {
    validateSourceUrl(url.href);
    return {
      platform: "web",
      externalId: null,
      title: path.basename(url.pathname),
      durationSeconds: null,
    };
  }

  async download(_url, _destinationDirectory) {
    throw Object.assign(new Error("Direct HTTPS file download not enabled in pilot"), {
      code: "DIRECT_DOWNLOAD_DISABLED",
    });
  }
}

export class CreatorUploadDownloader extends BaseDownloader {
  canHandle() {
    return false; // Selected explicitly by job type, not URL.
  }
}

export class GenericWebVideoDownloader extends BaseDownloader {
  canHandle(url) {
    return detectPlatform(url) === "web";
  }

  async probe(url) {
    validateSourceUrl(url.href);
    throw Object.assign(new Error("Generic web video probe not enabled in pilot"), {
      code: "GENERIC_WEB_DISABLED",
    });
  }
}

const registry = [
  new YouTubeDownloader(),
  new TikTokDownloader(),
  new InstagramDownloader(),
  new DirectFileDownloader(),
  new GenericWebVideoDownloader(),
];

export function downloaderFor(urlString) {
  const url = validateSourceUrl(urlString);
  const d = registry.find((x) => x.canHandle(url));
  if (!d) {
    throw Object.assign(new Error("No downloader for URL"), { code: "UNSUPPORTED_URL" });
  }
  return { downloader: d, url };
}

export { BaseDownloader };
