# Qwen3.8-27B Uncensored on RunPod Serverless

[Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) with its refusals removed ("abliterated") by OrcaRouter, in FP8, running in vLLM as a RunPod serverless worker. It is a coding and agent model: it calls tools, thinks before it answers, takes up to 262,144 tokens of context and can read images. The endpoint speaks the OpenAI API, so coding agents and OpenAI client libraries can use it directly.

All model files are baked into the Docker image, so the endpoint needs no network volume and no Hugging Face token.

> **This model has no safety refusals.** It answers requests the original Qwen3.8-27B refuses, including harmful and illegal ones. Anyone with the endpoint's API key gets that, so keep the key private. See [License](#license).

## What is in the image

| Part | What | Size |
| --- | --- | --- |
| Model weights | Qwen3.8-27B Uncensored: 27B dense, hybrid attention, block FP8, with its BF16 vision encoder and its MTP head | 30.9 GB |
| Inference server | vLLM 0.31.0, CUDA 13.0 build (`vllm/vllm-openai:v0.31.0`) | 9.0 GB download |
| Worker | RunPod SDK 1.12.0 and [handler.py](handler.py) | |

[handler.py](handler.py) starts `vllm serve` inside the container, waits until the model is loaded, then forwards each job to vLLM's OpenAI API. If vLLM crashes later, the worker stops so RunPod replaces it.

### Where the weights come from

The uncensored FP8 build is [orcarouter/Qwen3.8-27B-Uncensored-FP8](https://huggingface.co/orcarouter/Qwen3.8-27B-Uncensored-FP8). It is gated: its files only download with a Hugging Face token (access is granted automatically), and RunPod's GitHub build cannot be given one.

[chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-GGUF](https://huggingface.co/chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-GGUF) is an unofficial preservation release of that model. Besides its GGUF files, it keeps a byte-for-byte copy of OrcaRouter's repo in its `FP8/` folder. The Dockerfile downloads only that folder (30.9 GB of the repo's 178 GB), pinned to commit `58ebd123013160600229eda180b5b17f3fb7af9d`, so its content cannot change.

How the copy was checked against the gated original, on 2026-10-17, using Hugging Face's file listings (they show file hashes even for gated repos):

- The seven weight files and `tokenizer.json` have the SHA-256 that Hugging Face lists for OrcaRouter's own files.
- The ten small files (configs, chat template, tokenizer settings, license) have the same git blob hash as OrcaRouter's.
- Only `README.md` differs, and it is not checked.

[src/sha256sums.txt](src/sha256sums.txt) holds the SHA-256 of all 18 files, and the build fails if any downloaded file does not match.

If the copy is ever deleted, rebuilds fail until `MODEL_REPO` and `MODEL_REVISION` in the Dockerfile point somewhere else. Images that are already built keep working.

## Deploy

RunPod builds the image from this repo; nothing is built locally.

1. In the RunPod console, go to **Serverless → New Endpoint → Import Git Repository** and pick this repo, branch `main`, Dockerfile path `Dockerfile`.
2. Set the endpoint options below.
3. Deploy. After that, every push to `main` starts a new build.

| Setting | Value | Why |
| --- | --- | --- |
| Allowed CUDA Versions | `13.0` | vLLM's default image is built for CUDA 13.0 and needs NVIDIA driver 580 or newer. On an older host the worker exits at startup and says so. |
| GPU | 48 GB on Ada or newer (L40S, L40, RTX 6000 Ada), or H100 / H200 | The weights take 30.9 GB and the rest holds the KV cache, so smaller cards do not fit. Ada, Hopper and Blackwell run FP8 in hardware. Ampere cards (A40, RTX A6000, A100) do not and have not been tried. |
| Execution timeout | `1800` s to start | The default is 600 s, and a reply with long thinking can run past it. |
| Max workers | 1 while testing | |

A new worker loads the weights onto the GPU, and vLLM compiles the model and records CUDA graphs before the first job runs. This has not been timed on this image, so expect it to take minutes. Jobs wait in the queue until the worker is ready.

Environment variables, all optional:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MAX_MODEL_LEN` | `131072` | Longest prompt plus reply, in tokens. The model's native limit is `262144`. See [Context length](#context-length). |
| `MAX_CONCURRENCY` | `8` | Jobs one worker runs at the same time. vLLM batches them on the GPU, so they share its speed and its KV cache. |
| `GPU_MEMORY_UTILIZATION` | `0.92` | Share of GPU memory vLLM may use. |
| `KV_CACHE_DTYPE` | `fp8` | KV cache precision. `auto` stores it in BF16, which halves the context that fits. |
| `MTP_TOKENS` | `3` | Tokens the MTP head drafts per step for the full model to check. This usually speeds up generation and never changes the output. `0` turns it off. |
| `SERVED_MODEL_NAME` | `qwen3.8-27b` | Model name in responses. Requests can send any `model`; the worker replaces it with this one. |
| `EXTRA_VLLM_ARGS` | | More `vllm serve` flags, with shell-style quoting. For example, `--language-model-only` drops the vision encoder to free memory for KV cache. |
| `VLLM_STARTUP_TIMEOUT` | `1200` | Seconds to wait for vLLM to load before the worker gives up. |
| `REQUEST_TIMEOUT` | `3600` | Seconds a single request to vLLM may take. |

RunPod's GitHub builds are limited to an 80 GB image, 160 minutes in total, and 30 minutes for the `docker build` step. This image is about 40 GB to download (9 GB base image and 31 GB of weights). The weights download in Hugging Face's high-performance mode to save time, but speeds still vary a lot between builds, so if one times out, start it again.

### When a build fails

Every push to `main` starts a new build, so pushing a commit is also how to retry a failed one. RunPod's docs say a new GitHub release is needed, but on this endpoint a push was enough: the build started 14 seconds after the push.

If the log stops at `[internal] booting buildkit`, the build failed on RunPod's build machine before it read the Dockerfile, so no change to this repo fixes it. One example is `OCI runtime create failed ... unsafe procfs detected ... invalid cross-device link`. Push a commit to try again. If the same error comes back, report it to RunPod support with the build log. On 2026-10-16 it failed this way on two builds in a row.

## Requests

### OpenAI-compatible URL

Coding agents and OpenAI client libraries need three values:

| | |
| --- | --- |
| Base URL | `https://api.runpod.ai/v2/<ENDPOINT_ID>/openai/v1` |
| API key | Your RunPod API key |
| Model | `qwen3.8-27b` (any name works) |

```bash
curl https://api.runpod.ai/v2/<ENDPOINT_ID>/openai/v1/chat/completions \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3.8-27b", "messages": [{"role": "user", "content": "Write a binary search in Rust."}], "max_tokens": 8192}'
```

```python
from openai import OpenAI

client = OpenAI(base_url="https://api.runpod.ai/v2/<ENDPOINT_ID>/openai/v1", api_key="<RUNPOD_API_KEY>")
stream = client.chat.completions.create(
    model="qwen3.8-27b",
    messages=[{"role": "user", "content": "Write a binary search in Rust."}],
    max_tokens=8192,
    stream=True,
)
for chunk in stream:
    if chunk.choices:
        print(chunk.choices[0].delta.content or "", end="", flush=True)
```

Tools, `tool_choice` and streaming work as in the OpenAI API, and tool calls come back as standard `tool_calls`. RunPod hands these requests to the worker as `{"openai_route": ..., "openai_input": ...}`, the same way it does for its own vLLM worker, and the handler passes them to vLLM unchanged. Only `/v1/` routes are accepted.

### /run and /runsync

`input` is an OpenAI chat completions body, or a text completions body with `prompt` instead of `messages`:

```bash
curl -X POST https://api.runpod.ai/v2/<ENDPOINT_ID>/runsync \
  -H "Authorization: Bearer $RUNPOD_API_KEY" \
  -H "Content-Type: application/json" \
  -d @test_input.json
```

The output is a list, because the handler is able to stream. Without `stream`, the list holds one chat completion:

```json
{
  "status": "COMPLETED",
  "output": [
    {
      "choices": [{ "message": { "role": "assistant", "reasoning": "...", "content": "..." }, "finish_reason": "stop" }],
      "usage": { "prompt_tokens": "...", "completion_tokens": "...", "total_tokens": "..." }
    }
  ]
}
```

With `"stream": true`, send the job to `/run` and read `/stream/<job_id>`. Each item is one chunk, with the new text in `choices[0].delta`.

When a request fails, the job is marked FAILED and `error` holds vLLM's message, for example when `max_tokens` is larger than the context allows.

Unlike the ComfyUI workers, this one has no S3 upload and no Lambda callbacks: the reply comes back in the job output.

Three ready-made requests are in the repo. They take the place of the ComfyUI workers' workflow files, because a language model has no graph; `input` is the request body itself.

- [test_input.json](test_input.json): a short coding question with thinking off. Small and quick, for a first test.
- [sample-req-chat.json](sample-req-chat.json): a debugging question with thinking on, using Qwen's sampling settings for thinking mode.
- [sample-req-tools.json](sample-req-tools.json): one step of a coding-agent loop. It defines three tools and contains a failed test run that `run_command` returned. The reply should be the next tool call, most likely `read_file`.

### Thinking

Thinking is on by default. It comes back in the message's `reasoning` field (`delta.reasoning` when streaming), and the answer in `content`.

| To | Add to the request |
| --- | --- |
| Turn thinking off | `"chat_template_kwargs": {"enable_thinking": false}` |
| Think less | `"reasoning_effort": "medium"` or `"low"`. The default is `"xhigh"`; other values are rejected. |
| Keep only the latest turn's thinking | `"chat_template_kwargs": {"preserve_thinking": false}` |

By default, thinking from earlier assistant turns stays in the prompt when the client sends it back in each message's `reasoning` field. Qwen recommends this for agents, since the model does not have to work out the same things again.

When a request leaves out sampling settings, vLLM uses the model's own defaults: `temperature` 1.0, `top_p` 0.95, `top_k` 20. Those are Qwen's settings for thinking mode. With thinking off, Qwen recommends `temperature` 0.7, `top_p` 0.8 and `presence_penalty` 1.5, as in [test_input.json](test_input.json).

Thinking can take thousands of tokens before the answer starts, so a small `max_tokens` can end a reply before it has any `content`.

### Images

The model also reads images sent as `image_url` parts of a message, as base64 `data:` URLs. RunPod limits the size of a request, so scale large images down first.

## Context length

`MAX_MODEL_LEN` sets the context, up to the native 262,144 tokens. Only 16 of the model's 64 layers keep a KV cache; the others use linear attention with a fixed-size state. Long contexts therefore need less memory than in most models this size. How much fits on each GPU has not been measured here. vLLM prints it at startup (`GPU KV cache size: ... tokens`), and if `MAX_MODEL_LEN` does not fit, vLLM stops at startup and the worker log says why.

Qwen documents up to 1,000,000 tokens with YaRN. That takes `VLLM_ALLOW_LONG_MAX_MODEL_LEN=1`, `MAX_MODEL_LEN=1000000`, the `--hf-overrides` value from [Qwen's model card](https://huggingface.co/Qwen/Qwen3.8-27B-FP8) in `EXTRA_VLLM_ARGS`, and much more GPU memory. It has not been tried on this worker. Qwen advises adding it only when long contexts are needed, because this kind of YaRN scaling applies to every prompt, short ones too.

## License

The weights are under the [Apache License 2.0](https://huggingface.co/Qwen/Qwen3.8-27B/blob/main/LICENSE), from Qwen3.8-27B through OrcaRouter's build and chimingw's copy. It allows commercial use and hosting. The license file ships in the image next to the weights.

The license does not restrict what the model is used for, but OrcaRouter's card is direct about what the abliteration does: the model "will comply with harmful, unethical, offensive, or illegal requests that the original Qwen3.8-27B would refuse". OrcaRouter releases it for research such as red-teaming and studying refusals. Laws and RunPod's terms still apply, and whoever runs the endpoint is responsible for what it produces. If other people can reach it, put your own checks in front of it.

OrcaRouter's figures for refusal rates and for how close the model stays to the original's scores are its own and were not checked here.

vLLM is under the Apache License 2.0. The worker code in this repo has no license file yet.
