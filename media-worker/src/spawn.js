import { spawn } from "node:child_process";

/**
 * Safe argv-array spawn. Never interpolate user input into a shell string.
 */
export function runCommand(bin, args, { cwd, timeoutMs = 30 * 60 * 1000, env } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, {
      cwd,
      env: env ? { ...process.env, ...env } : process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(Object.assign(new Error(`${bin} timed out`), { code: "CMD_TIMEOUT", stderr }));
    }, timeoutMs);
    child.stdout.on("data", (d) => {
      stdout += d.toString("utf8");
    });
    child.stderr.on("data", (d) => {
      stderr += d.toString("utf8");
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve({ stdout, stderr, code });
      else {
        const err = new Error(`${bin} exited ${code}: ${stderr.slice(-800)}`);
        err.code = "CMD_FAILED";
        err.stderr = stderr;
        err.stdout = stdout;
        reject(err);
      }
    });
  });
}
