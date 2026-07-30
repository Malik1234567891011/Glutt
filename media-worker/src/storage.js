import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { createReadStream } from "node:fs";
import { config, r2Enabled } from "./config.js";

async function ensureDir(p) {
  await fs.mkdir(p, { recursive: true });
}

export async function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  const stream = createReadStream(filePath);
  for await (const chunk of stream) hash.update(chunk);
  return hash.digest("hex");
}

/** Local archive under MEDIA_DATA_DIR/objects/... mirrors R2 key layout. */
export async function putLocalObject(objectKey, sourceFilePath) {
  const dest = path.join(config.dataDir, "objects", objectKey);
  await ensureDir(path.dirname(dest));
  await fs.copyFile(sourceFilePath, dest);
  return { backend: "local", objectKey, absolutePath: dest };
}

export async function localObjectPath(objectKey) {
  return path.join(config.dataDir, "objects", objectKey);
}

export async function objectExists(objectKey) {
  try {
    await fs.access(await localObjectPath(objectKey));
    return true;
  } catch {
    return false;
  }
}

export async function putObject(objectKey, sourceFilePath) {
  // Always keep a local copy for pilot/dev playback.
  const local = await putLocalObject(objectKey, sourceFilePath);
  if (!r2Enabled()) return local;

  const { S3Client, PutObjectCommand } = await import("@aws-sdk/client-s3");
  const client = new S3Client({
    region: "auto",
    endpoint: `https://${config.r2.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: config.r2.accessKeyId,
      secretAccessKey: config.r2.secretAccessKey,
    },
  });
  const body = await fs.readFile(sourceFilePath);
  await client.send(new PutObjectCommand({
    Bucket: config.r2.bucket,
    Key: objectKey,
    Body: body,
  }));
  return { ...local, backend: "r2+local" };
}

export async function writeJsonObject(objectKey, data) {
  const tmp = path.join(config.workDir, `meta-${crypto.randomUUID()}.json`);
  await ensureDir(path.dirname(tmp));
  await fs.writeFile(tmp, JSON.stringify(data, null, 2));
  const out = await putObject(objectKey, tmp);
  await fs.unlink(tmp).catch(() => {});
  return out;
}
