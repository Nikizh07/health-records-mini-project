// backend/services/ai/providers/sagemaker.js
// ============================================================
// AWS SageMaker real-time endpoint.
//
// SageMaker has NO standard payload shape: it depends on the serving
// container. The two functions directly below target the HuggingFace TGI
// container. To retarget another container, edit only those two.
// ============================================================

'use strict';

// ── Request / response mapping: edit these for a different container ──

// TGI rejects temperature 0, so greedy decoding is `do_sample: false` instead.
function toRequestBody({ system, user, maxTokens, temperature }) {
  return {
    inputs: `${system}\n\n${user}`,
    parameters: {
      max_new_tokens: maxTokens,
      return_full_text: false,
      ...(temperature > 0 ? { do_sample: true, temperature } : { do_sample: false }),
    },
  };
}

// TGI answers `[{ "generated_text": "..." }]`.
function fromResponseBody(body) {
  const first = Array.isArray(body) ? body[0] : body;
  return first?.generated_text;
}

// ─────────────────────────────────────────────────────────────

let client = null;

module.exports = {
  name: 'sagemaker',

  isConfigured() {
    return Boolean(
      process.env.AI_SAGEMAKER_ENDPOINT && (process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION)
    );
  },

  async complete({ system, user, maxTokens, temperature, signal }) {
    // Required lazily so OpenAI-compatible users never need the AWS SDK.
    const { SageMakerRuntimeClient, InvokeEndpointCommand } = require('@aws-sdk/client-sagemaker-runtime');
    client ??= new SageMakerRuntimeClient({});

    const out = await client.send(
      new InvokeEndpointCommand({
        EndpointName: process.env.AI_SAGEMAKER_ENDPOINT,
        ContentType: 'application/json',
        Accept: 'application/json',
        Body: JSON.stringify(toRequestBody({ system, user, maxTokens, temperature })),
      }),
      { abortSignal: signal }
    );

    return fromResponseBody(JSON.parse(Buffer.from(out.Body).toString('utf8')));
  },
};
