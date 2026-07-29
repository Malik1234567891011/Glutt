#!/usr/bin/env python3
"""Generate an image with Gemini (Nano Banana Pro) from a prompt file + reference images."""
import argparse, base64, json, mimetypes, os, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = open(os.path.join(HERE, ".gemini_key")).read().strip()


def part_for(path):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        return {"inline_data": {"mime_type": mime, "data": base64.b64encode(f.read()).decode()}}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt-file", required=True)
    ap.add_argument("--refs", nargs="*", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--model", default="gemini-3-pro-image")
    ap.add_argument("--ar", default="9:16")
    ap.add_argument("--size", default="2K")
    a = ap.parse_args()

    prompt = open(a.prompt_file).read()
    parts = [{"text": prompt}] + [part_for(r) for r in a.refs]
    body = {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "imageConfig": {"aspectRatio": a.ar, "imageSize": a.size},
        },
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{a.model}:generateContent"
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": KEY},
    )
    resp = None
    for attempt in range(6):
        try:
            resp = json.load(urllib.request.urlopen(req, timeout=600))
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:400]
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                wait = 20 * (attempt + 1)
                print(f"HTTP {e.code}, retry {attempt+1}/5 in {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            print("HTTP", e.code, detail, file=sys.stderr)
            sys.exit(1)
    if resp is None:
        print("exhausted retries", file=sys.stderr)
        sys.exit(1)

    cands = resp.get("candidates") or []
    if not cands:
        print("NO CANDIDATES:", json.dumps(resp)[:2000], file=sys.stderr)
        sys.exit(1)
    saved = []
    for p in cands[0].get("content", {}).get("parts", []):
        blob = p.get("inlineData") or p.get("inline_data")
        if blob:
            with open(a.out, "wb") as f:
                f.write(base64.b64decode(blob["data"]))
            saved.append(a.out)
        elif p.get("text"):
            print("MODEL TEXT:", p["text"][:800], file=sys.stderr)
    if not saved:
        print("NO IMAGE. finishReason=", cands[0].get("finishReason"), file=sys.stderr)
        sys.exit(1)
    print("OK", a.out, os.path.getsize(a.out), "bytes")


if __name__ == "__main__":
    main()
