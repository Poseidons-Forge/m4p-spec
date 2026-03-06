FROM pandoc/extra:latest-ubuntu

# System dependencies: Node.js, fonts, curl, poppler, and Chromium runtime
# libs needed by Puppeteer (used by mermaid-cli for diagram rendering).
RUN apt-get update && apt-get install -y --no-install-recommends \
        nodejs npm curl \
        fonts-noto-core fonts-dejavu-core \
        poppler-utils \
        libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 \
        libxkbcommon0 libgbm1 libasound2t64 libpango-1.0-0 \
        libcairo2 libxdamage1 libxrandr2 libxcomposite1 libxshmfence1 libxfixes3 \
    && rm -rf /var/lib/apt/lists/*

# Pin TeX Live to the frozen 2025 repository (the rolling repo has moved to 2026)
RUN tlmgr option repository https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final \
    && tlmgr install newunicodechar

# Install npm deps to /opt/node_modules so they survive the volume mount.
# render.js resolves mmdc via __dirname/node_modules, so we symlink back.
WORKDIR /opt
COPY package.json package-lock.json ./
RUN npm ci

WORKDIR /spec

# Chromium runs as root inside Docker — needs --no-sandbox
ENV PUPPETEER_ARGS="--no-sandbox"

# Create a puppeteer config for mermaid-cli (mmdc -p flag)
RUN echo '{"args":["--no-sandbox"]}' > /opt/puppeteer-config.json

# Override pandoc entrypoint; default: build the PDF
ENTRYPOINT []
CMD ["sh", "-c", "ln -sfn /opt/node_modules node_modules && npm run pdf"]
