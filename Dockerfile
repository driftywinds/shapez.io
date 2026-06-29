# Stage 1: Build the game
FROM node:18 AS builder

WORKDIR /shapez.io

# Install system dependencies:
# - ffmpeg: audio/video processing
# - default-jre: required by some build tools
# - git: required by buildutils.js (getRevision)
# - make/gcc/g++/libpng-dev/zlib1g-dev: native compilation fallbacks
# - libjpeg-turbo-progs: provides jpegtran (replaces npm jpegtran-bin binary)
# - optipng: provides optipng (replaces npm optipng-bin binary)
# - gifsicle: provides gifsicle (replaces npm gifsicle binary)
# - pngquant: provides pngquant (replaces npm pngquant-bin binary)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg default-jre git \
    make gcc g++ \
    libpng-dev zlib1g-dev \
    libjpeg-turbo-progs optipng gifsicle pngquant \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install root dependencies first for better caching
COPY package.json yarn.lock ./
RUN yarn

# Install gulp build dependencies
# --ignore-scripts skips native binary download postinstall scripts
# (jpegtran-bin, optipng-bin, gifsicle, pngquant-bin) which fail on arm64.
# We provide system-level equivalents via symlinks instead.
COPY gulp ./gulp
WORKDIR /shapez.io/gulp
RUN yarn --ignore-scripts

# Symlink system binaries into where npm packages expect them
RUN mkdir -p node_modules/jpegtran-bin/vendor \
    node_modules/optipng-bin/vendor \
    node_modules/gifsicle/vendor \
    node_modules/pngquant-bin/vendor \
    && ln -sf "$(which jpegtran)" node_modules/jpegtran-bin/vendor/jpegtran \
    && ln -sf "$(which optipng)" node_modules/optipng-bin/vendor/optipng \
    && ln -sf "$(which gifsicle)" node_modules/gifsicle/vendor/gifsicle \
    && ln -sf "$(which pngquant)" node_modules/pngquant-bin/vendor/pngquant

WORKDIR /shapez.io

# Copy source files needed for build
COPY res ./res
COPY res_raw ./res_raw
COPY src/html ./src/html
COPY src/css ./src/css
COPY src/js ./src/js
COPY version ./version
COPY sync-translations.js ./
COPY translations ./translations
COPY .git ./.git
COPY electron ./electron

# Build the full version of the game
ENV NODE_OPTIONS=--openssl-legacy-provider
RUN cp src/js/core/config.local.template.js src/js/core/config.local.js
WORKDIR /shapez.io/gulp
RUN yarn gulp build.web-shapezio

# Stage 2: Serve with nginx
FROM nginx:alpine

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the built game files
COPY --from=builder /shapez.io/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
