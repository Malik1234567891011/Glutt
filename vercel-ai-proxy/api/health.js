export default function handler(_req, res) {
  res.status(200).json({
    ok: true,
    service: "glutt-vercel-ai-proxy",
    timestamp: new Date().toISOString(),
  });
}

