// backend/services/ai/providers/bedrock.js
// ============================================================
// AWS Bedrock via the Converse API, which handles each model family's
// prompt template (no hand-rolled Llama tokens).
//
// Credentials come from the default AWS chain: AWS_PROFILE locally, the
// ECS task role in production. No access keys in env.
// ============================================================

'use strict';

let client = null;

module.exports = {
  name: 'bedrock',

  isConfigured() {
    return Boolean(process.env.AI_MODEL && (process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION));
  },

  async complete({ system, user, maxTokens, temperature, signal }) {
    // Required lazily so OpenAI-compatible users never need the AWS SDK.
    const { BedrockRuntimeClient, ConverseCommand } = require('@aws-sdk/client-bedrock-runtime');
    client ??= new BedrockRuntimeClient({});

    const out = await client.send(
      new ConverseCommand({
        modelId: process.env.AI_MODEL,
        system: [{ text: system }],
        messages: [{ role: 'user', content: [{ text: user }] }],
        inferenceConfig: { maxTokens, temperature },
      }),
      { abortSignal: signal }
    );

    return (out.output?.message?.content || [])
      .map((block) => block.text)
      .filter(Boolean)
      .join('');
  },
};
