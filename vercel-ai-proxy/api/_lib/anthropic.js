// Anthropic's Messages API, spoken in OpenAI's dialect.
//
// The app talks one shape to this proxy and always has. Rather than teach every
// caller a second one, the translation lives here: requests go in as
// `chat/completions`, come out as `/v1/messages`, and the reply is dressed back
// up as a choices array so nothing downstream can tell.
//
// Added for the knife grip check specifically. Measured across nine framings on
// one frame, GPT would not report a hand closed around a blade: minimal prompt,
// full frame, free description, forced choice, gpt-4.1 and gpt-5 all answered
// "on the handle" because hands are usually on handles. That is a prior, not a
// resolution problem, and a different family of model is the cheapest way to
// find out whether it is a prior this one shares.

export function isAnthropicModel(model) {
  return typeof model === "string" && model.startsWith("claude");
}

/// data:image/jpeg;base64,XXXX -> { media_type, data }
function splitDataURI(url) {
  const match = /^data:([^;]+);base64,(.*)$/.exec(url || "");
  if (!match) return null;
  return { media_type: match[1], data: match[2] };
}

/// OpenAI puts the system prompt in the messages array; Anthropic takes it as
/// its own top-level field and rejects it as a role.
export function toAnthropicRequest(body) {
  const systemParts = [];
  const messages = [];

  for (const message of body.messages || []) {
    if (message.role === "system") {
      systemParts.push(
        typeof message.content === "string"
          ? message.content
          : (message.content || []).map((p) => p.text || "").join("\n")
      );
      continue;
    }

    if (typeof message.content === "string") {
      messages.push({ role: message.role, content: message.content });
      continue;
    }

    const content = [];
    for (const part of message.content || []) {
      if (part.type === "text") {
        content.push({ type: "text", text: part.text });
      } else if (part.type === "image_url") {
        const image = splitDataURI(part.image_url && part.image_url.url);
        if (image) {
          content.push({ type: "image", source: { type: "base64", ...image } });
        }
      }
    }
    if (content.length) messages.push({ role: message.role, content });
  }

  const request = {
    model: body.model,
    // Anthropic requires this; OpenAI treats it as optional, so most callers
    // here send nothing and the default is what they get.
    //
    // 1500 was not enough and failed in the least obvious way: `finish_reason:
    // length`, `completion_tokens: 1500`, and an EMPTY string for content. A
    // truncated JSON object is indistinguishable from a model that said nothing,
    // and the app reported it as "I could not get a look".
    max_tokens: body.max_tokens || body.max_completion_tokens || 8000,
    messages,
  };
  if (systemParts.length) request.system = systemParts.join("\n\n");

  // `temperature` is NOT forwarded.
  //
  // Anthropic's newer models reject it outright: "`temperature` is deprecated
  // for this model", a 400 that killed every skill check while a hand-written
  // probe without one sailed through, which is a good lesson in testing the
  // request the app actually sends rather than the one you had to hand.
  //
  // Nothing is lost here. The caller sets it low to keep a visual judgement
  // steady, and these models do that themselves.

  // `response_format: json_object` has no Anthropic equivalent. Asking for it
  // in words is what the SDK docs recommend, and the caller is already parsing
  // JSON out of the text either way.
  if (body.response_format && body.response_format.type === "json_object") {
    request.system = `${request.system || ""}\n\nRespond with a single valid JSON object and nothing else. No prose, no code fences.`.trim();
  }
  return request;
}

/// Anthropic returns content blocks; the app expects choices[0].message.content.
export function toOpenAIResponse(payload) {
  const text = (payload.content || [])
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("");

  return {
    id: payload.id,
    object: "chat.completion",
    model: payload.model,
    choices: [
      {
        index: 0,
        message: { role: "assistant", content: text },
        finish_reason: payload.stop_reason === "max_tokens" ? "length" : "stop",
      },
    ],
    usage: {
      prompt_tokens: (payload.usage && payload.usage.input_tokens) || 0,
      completion_tokens: (payload.usage && payload.usage.output_tokens) || 0,
      total_tokens:
        ((payload.usage && payload.usage.input_tokens) || 0) +
        ((payload.usage && payload.usage.output_tokens) || 0),
    },
  };
}

export async function callAnthropic(body) {
  const key = (process.env.ANTHROPIC_API_KEY || "").trim();
  if (!key) {
    return { ok: false, status: 500, raw: JSON.stringify({ error: "Server misconfigured: missing ANTHROPIC_API_KEY" }) };
  }

  const headers = {
    "x-api-key": key,
    "anthropic-version": "2023-06-01",
    "Content-Type": "application/json",
  };

  // Identity-linked keys, the kind the console hands out to a person rather
  // than to a workspace, refuse to act until they are told which workspace they
  // are acting in: "anthropic-workspace-id is required when authenticating with
  // an identity-linked API key". Optional, because a plain workspace key does
  // not want it and sending an empty one is worse than sending none.
  const workspace = (process.env.ANTHROPIC_WORKSPACE_ID || "").trim();
  if (workspace) headers["anthropic-workspace-id"] = workspace;

  const upstream = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers,
    body: JSON.stringify(toAnthropicRequest(body)),
  });

  const raw = await upstream.text();
  if (!upstream.ok) return { ok: false, status: upstream.status, raw };

  try {
    return { ok: true, status: 200, raw: JSON.stringify(toOpenAIResponse(JSON.parse(raw))) };
  } catch {
    return { ok: false, status: 502, raw };
  }
}
