# =============================================================================
# n8n Dockerfile — tailored to this workflow's exact executeCommand nodes
# Target: Render Free Web Service (0.1 CPU / 512MB RAM)
# =============================================================================
# Base pinned to n8n 1.x (Alpine) instead of :latest — 2.x moves Code-node
# execution to a separate task-runner process by default (extra Node process
# = extra baseline RAM we can't afford on 512MB), and 1.x images are smaller.
# All node typeVersions this workflow uses — httpRequest 4.2, googleSheets 4.5,
# if 2.2, set 3.4, code 2, splitInBatches 3 — are supported well before 1.123,
# so nothing here needs 2.x.
# =============================================================================
FROM n8nio/n8n:1.123.52

USER root

# ffmpeg / ffprobe    -> Check Image Valid, TTS silent fallback, Check Voice Valid,
#                        Make Clip, Concat + BGM + Subtitle, Check Final Video,
#                        Generate Thumbnail, Extract QC Frames
# python3             -> Build Full SRT (subtitle timing), TTS JSON payload build
# py3-pip + edge-tts  -> TTS node's Eleven -> Edge -> Silent fallback voice
# curl                -> TTS node's direct ElevenLabs API call
# bash                -> executeCommand nodes use bash-style heredocs/expansion
# coreutils           -> real `sort -V` (busybox sort doesn't support -V reliably)
# gawk                -> the awk math used in Make Clip / Build Full SRT / TTS
# font-dejavu+fontconfig -> subtitle burn-in ("FontName=DejaVu Sans" in the
#                        Concat + BGM + Subtitle ffmpeg subtitles filter)
# tzdata              -> correct $now.toISO() / YouTube publishAt scheduling
RUN apk add --no-cache \
        ffmpeg \
        python3 \
        py3-pip \
        curl \
        bash \
        coreutils \
        gawk \
        font-dejavu \
        fontconfig \
        tzdata \
    && pip3 install --no-cache-dir --break-system-packages edge-tts \
    && fc-cache -f \
    && rm -rf /var/cache/apk/* /root/.cache /tmp/*

USER node

# ---- RAM safety, tuned for the 512MB Render Free instance -----------------
# N8N_DEFAULT_BINARY_DATA_MODE=filesystem is the single biggest lever: without
# it, every image/audio/video buffer passed between nodes stays IN MEMORY.
# max-old-space-size=280 caps the Node heap; that leaves ~230MB of headroom
# for Node's own process overhead + the ffmpeg/python/curl child processes
# this workflow spawns sequentially (all ffmpeg calls already use -threads 1,
# so they stay single-core and cheap on memory).
ENV N8N_DEFAULT_BINARY_DATA_MODE=filesystem \
    NODE_OPTIONS="--max-old-space-size=280" \
    UV_THREADPOOL_SIZE=2 \
    EXECUTIONS_DATA_SAVE_ON_SUCCESS=none \
    EXECUTIONS_DATA_SAVE_ON_ERROR=none \
    EXECUTIONS_DATA_PRUNE=true \
    EXECUTIONS_DATA_MAX_AGE=24 \
    N8N_METRICS=false \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_VERSION_NOTIFICATIONS_ENABLED=false \
    N8N_TEMPLATES_ENABLED=false \
    N8N_PUBLIC_API_DISABLED=true \
    N8N_SECURE_COOKIE=false \
    GENERIC_TIMEZONE=Asia/Dhaka \
    TZ=Asia/Dhaka

EXPOSE 5678

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD wget -q --spider http://localhost:5678/healthz || exit 1
