-- The chat endpoint had no rate row, so every text AI call costed to $0.
--
-- `LLMClient` sends `gpt-4o` (its UserDefaults default), the proxy logs that
-- string verbatim, and `ai_usage_costed` LEFT JOINs `ai_rates` — a miss is a
-- zero, silently. `gpt-4o-mini` is seeded alongside it because the model is
-- swappable at runtime from Settings, and the next model to go unpriced would
-- fail exactly the same way.
--
-- OpenAI list prices, 2026-07: gpt-4o $2.50/1M in, $10.00/1M out;
-- gpt-4o-mini $0.15/1M in, $0.60/1M out.

insert into public.ai_rates (model, input_per_1k, output_per_1k)
values
  ('gpt-4o',      0.0025,  0.010),
  ('gpt-4o-mini', 0.00015, 0.0006)
on conflict (model) do update
  set input_per_1k  = excluded.input_per_1k,
      output_per_1k = excluded.output_per_1k;
