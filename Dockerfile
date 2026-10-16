
# Qwen3.8-27B Uncensored (FP8): coding and agent LLM with tool calling
# vLLM on RunPod Serverless, with an OpenAI-compatible API
# All model weights baked into the image.

ARG VLLM_VERSION=0.31.0
FROM vllm/vllm-openai:v${VLLM_VERSION}
ARG VLLM_VERSION

ENV PYTHONUNBUFFERED=1
ENV PIP_NO_INPUT=1
ENV PIP_NO_CACHE_DIR=1

# Add the RunPod SDK. vLLM, PyTorch and aiohttp come from the base image. Fail
# the build if installing the SDK replaced the base image's vLLM.
RUN python3 -m ensurepip --upgrade 2>/dev/null || true \
    && python3 -m pip install runpod==1.12.0 \
    && test "$(python3 -c 'import vllm; print(vllm.__version__)')" = "${VLLM_VERSION}"

# orcarouter/Qwen3.8-27B-Uncensored-FP8 is gated, and RunPod's GitHub build
# cannot be given a Hugging Face token. chimingw's repo below keeps a
# byte-for-byte copy of it in its FP8/ folder, and only that folder is
# downloaded. The repo is pinned to a commit, and src/sha256sums.txt fails the
# build if any file differs from the gated original.
# Declared here, not at the top, so the layers above stay cached when these move.
ARG MODEL_REPO=chimingw/Qwen3.8-27B-Uncensored-OrcaRouter-GGUF
ARG MODEL_REVISION=58ebd123013160600229eda180b5b17f3fb7af9d
ENV MODEL_PATH=/models/qwen3.8-27b-uncensored-fp8

# Download the model (30.9 GB), one weight file per layer: GHCR, where the
# GitHub Actions build pushes the image, rejects layers over 10 GB.
COPY src/download.sh src/sha256sums.txt /tmp/
RUN bash /tmp/download.sh LICENSE '*.json' '*.jinja' '*.txt'
RUN bash /tmp/download.sh model-00001-of-00007.safetensors
RUN bash /tmp/download.sh model-00002-of-00007.safetensors
RUN bash /tmp/download.sh model-00003-of-00007.safetensors
RUN bash /tmp/download.sh model-00004-of-00007.safetensors
RUN bash /tmp/download.sh model-00005-of-00007.safetensors
RUN bash /tmp/download.sh model-00006-of-00007.safetensors
RUN bash /tmp/download.sh model-00007-of-00007.safetensors
RUN cd "${MODEL_PATH}" \
    && sha256sum -c /tmp/sha256sums.txt \
    && rm /tmp/download.sh /tmp/sha256sums.txt

# The weights are in the image, so nothing reaches the Hugging Face Hub at run time.
ENV HF_HUB_OFFLINE=1
ENV TRANSFORMERS_OFFLINE=1

WORKDIR /

# Add the RunPod handler and startup script.
COPY src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# The base image's entrypoint is `vllm serve`; handler.py starts vLLM itself.
ENTRYPOINT ["/start.sh"]
CMD []
