// backend/services/ai/providers/openaiCompatible.js
// ============================================================
// Any OpenAI-compatible /chat/completions endpoint: OpenAI, Gemini,
// Groq, OpenRouter, Ollama, vLLM, LM Studio… Plain fetch, no SDK.
// ============================================================

'use strict';

module.exports = {
  name: 'openai-compatible',

  isConfigured() {
    return Boolean(process.env.AI_BASE_URL && process.env.AI_API_KEY && process.env.AI_MODEL);
  },

  async complete({ system, user, maxTokens, temperature, signal }) {
    const res = await fetch(`${process.env.AI_BASE_URL.replace(/\/+$/, '')}/chat/completions`, {
      method: 'POST',
      signal,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.AI_API_KEY}`,
      },
      body: JSON.stringify({
        model: process.env.AI_MODEL,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        temperature,
        max_tokens: maxTokens,
        // Most compatible endpoints accept this; the few that reject it are why it is a flag.
        ...(process.env.AI_JSON_MODE === 'true' ? { response_format: { type: 'json_object' } } : {}),
      }),
    });

    if (!res.ok) {
      throw new Error(`HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
    }

    const data = await res.json();
    return data?.choices?.[0]?.message?.content;
  },
};
