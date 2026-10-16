
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

# Download the model (30.9 GB) and check it.
COPY src/sha256sums.txt /tmp/sha256sums.txt
RUN python3 -c "import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1], revision=sys.argv[2], allow_patterns=['FP8/*'], local_dir='/tmp/model')" \
        "${MODEL_REPO}" "${MODEL_REVISION}" \
    && mkdir -p "$(dirname "${MODEL_PATH}")" \
    && mv /tmp/model/FP8 "${MODEL_PATH}" \
    && rm -rf /tmp/model \
    && cd "${MODEL_PATH}" \
    && sha256sum -c /tmp/sha256sums.txt \
    && rm /tmp/sha256sums.txt

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
