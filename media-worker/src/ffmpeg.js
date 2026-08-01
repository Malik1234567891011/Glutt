import { config } from "./config.js";
import { runCommand } from "./spawn.js";

export async function ffprobeJson(filePath) {
  const { stdout } = await runCommand(config.ffprobeBin, [
    "-v", "quiet",
    "-print_format", "json",
    "-show_format",
    "-show_streams",
    filePath,
  ], { timeoutMs: 60000 });
  return JSON.parse(stdout);
}

export function summarizeProbe(probe) {
  const video = (probe.streams || []).find((s) => s.codec_type === "video");
  const audio = (probe.streams || []).find((s) => s.codec_type === "audio");
  const duration = Number(probe.format?.duration) || (video ? Number(video.duration) : 0) || null;
  return {
    durationSeconds: duration,
    sizeBytes: Number(probe.format?.size) || null,
    formatName: probe.format?.format_name || null,
    videoCodec: video?.codec_name || null,
    audioCodec: audio?.codec_name || null,
    width: video?.width || null,
    height: video?.height || null,
    rotation: video?.tags?.rotate || video?.side_data_list?.find?.((x) => x.rotation != null)?.rotation || null,
    fps: video?.avg_frame_rate || video?.r_frame_rate || null,
  };
}

/** Normalized mezzanine: H.264/AAC, ≤1080p, 30fps, preserve aspect. */
export async function normalizeMezzanine(inputPath, outputPath) {
  await runCommand(config.ffmpegBin, [
    "-y",
    "-i", inputPath,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-vf", "fps=30,scale='min(1920,iw)':'-2'",
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "20",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "160k",
    "-ar", "48000",
    "-ac", "2",
    "-movflags", "+faststart",
    outputPath,
  ], { timeoutMs: 30 * 60 * 1000 });
}

/** Analysis proxy: ~540p, 15fps, mono AAC. */
export async function makeAnalysisProxy(inputPath, outputPath) {
  await runCommand(config.ffmpegBin, [
    "-y",
    "-i", inputPath,
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-vf", "fps=15,scale='min(960,iw)':'-2'",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-crf", "28",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "64k",
    "-ac", "1",
    "-ar", "44100",
    "-movflags", "+faststart",
    outputPath,
  ], { timeoutMs: 20 * 60 * 1000 });
}

export async function extractAudio(inputPath, outputPath) {
  const probe = await ffprobeJson(inputPath);
  const hasAudio = (probe.streams || []).some((s) => s.codec_type === "audio");
  if (!hasAudio) {
    return { skipped: true, reason: "no_audio_stream" };
  }
  await runCommand(config.ffmpegBin, [
    "-y",
    "-i", inputPath,
    "-vn",
    "-c:a", "aac",
    "-b:a", "96k",
    outputPath,
  ], { timeoutMs: 10 * 60 * 1000 });
  return { skipped: false };
}

/** Accurate re-encode clip (not stream-copy). */
export async function materializeClip(inputPath, outputPath, startSeconds, durationSeconds) {
  await runCommand(config.ffmpegBin, [
    "-y",
    "-ss", String(startSeconds),
    "-i", inputPath,
    "-t", String(durationSeconds),
    "-map", "0:v:0",
    "-map", "0:a:0?",
    "-c:v", "libx264",
    "-preset", "medium",
    "-crf", "19",
    "-c:a", "aac",
    "-b:a", "160k",
    "-movflags", "+faststart",
    outputPath,
  ], { timeoutMs: 15 * 60 * 1000 });
}

export async function extractThumbnail(inputPath, outputPath, atSeconds) {
  await runCommand(config.ffmpegBin, [
    "-y",
    "-ss", String(atSeconds),
    "-i", inputPath,
    "-frames:v", "1",
    "-q:v", "2",
    outputPath,
  ], { timeoutMs: 60000 });
}

/**
 * 9:16 cook canvas from landscape (or any) footage.
 * Blurred cover background + sharp fit foreground — avoids the mushy
 * center-crop upscale when the master is only 360p/480p.
 */
export async function makeVerticalBlurFill(inputPath, outputPath, {
  width = 1080,
  height = 1920,
} = {}) {
  const filter = [
    `[0:v]scale=${width}:${height}:force_original_aspect_ratio=increase:flags=lanczos,crop=${width}:${height},gblur=sigma=18[bg]`,
    `[0:v]scale=${width}:${height}:force_original_aspect_ratio=decrease:flags=lanczos[fg]`,
    `[bg][fg]overlay=(W-w)/2:(H-h)/2`,
  ].join(";");
  await runCommand(config.ffmpegBin, [
    "-y",
    "-i", inputPath,
    "-filter_complex", filter,
    "-map", "0:a:0?",
    "-c:v", "libx264",
    "-preset", "medium",
    // These stream to a phone mid-cook. crf 18 put a 75s clip at 42MB (~4.5Mbps),
    // which stalls on cellular; most of the frame is blurred backdrop that does
    // not need those bits. The cap bounds the worst case for busy pan footage.
    "-crf", "24",
    "-maxrate", "2500k",
    "-bufsize", "5000k",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "128k",
    "-movflags", "+faststart",
    outputPath,
  ], { timeoutMs: 20 * 60 * 1000 });
}
