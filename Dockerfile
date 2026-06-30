# syntax=docker/dockerfile:1
# Stage 1: Build the game
FROM node:18 AS builder

WORKDIR /shapez.io

# Install system dependencies:
# - ffmpeg: audio/video processing
# - default-jre: required by some build tools
# - git: required by buildutils.js (getRevision)
# - make/gcc/g++/libpng-dev/zlib1g-dev: native compilation fallbacks
# - libjpeg-turbo-progs: provides jpegtran and cjpeg
# - optipng: provides optipng
# - gifsicle: provides gifsicle
# - pngquant: provides pngquant
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

# Install gulp build dependencies + symlink system binaries.
# --ignore-scripts skips postinstall scripts that download native binaries
# (these fail on arm64). We provide system-level equivalents via symlinks.
# Combined into single RUN with heredoc to avoid Docker layer caching issues.
COPY gulp ./gulp
WORKDIR /shapez.io/gulp
RUN yarn --ignore-scripts && sh <<'SCRIPT'
set -e
echo "Creating vendor dirs and symlinks for system binaries..."

# These npm packages expect native binaries in vendor/ subdirectories.
# --ignore-scripts skips their postinstall scripts that download binaries,
# and some (like mozjpeg) don't even include vendor/ in their npm tarball.
# Create the directories and symlink system equivalents.
for pkg in pngquant-bin jpegtran-bin optipng-bin mozjpeg gifsicle; do
    find node_modules -name "$pkg" -type d | while read dir; do
        mkdir -p "$dir/vendor"
    done
done

# Symlink each system binary into all matching vendor directories
find node_modules -path "*/pngquant-bin/vendor" -type d | while read dir; do
    ln -sf "$(which pngquant)" "$dir/pngquant"
done
find node_modules -path "*/jpegtran-bin/vendor" -type d | while read dir; do
    ln -sf "$(which jpegtran)" "$dir/jpegtran"
done
find node_modules -path "*/optipng-bin/vendor" -type d | while read dir; do
    ln -sf "$(which optipng)" "$dir/optipng"
done
find node_modules -path "*/gifsicle/vendor" -type d | while read dir; do
    ln -sf "$(which gifsicle)" "$dir/gifsicle"
done
find node_modules -path "*/mozjpeg/vendor" -type d | while read dir; do
    ln -sf "$(which cjpeg)" "$dir/cjpeg"
    ln -sf "$(which jpegtran)" "$dir/jpegtran"
done

# Verify all critical symlinks resolve to actual files
echo "Verifying symlinks..."
BROKEN=""
for link in $(find node_modules \
    -path "*/pngquant-bin/vendor/pngquant" \
    -o -path "*/jpegtran-bin/vendor/jpegtran" \
    -o -path "*/optipng-bin/vendor/optipng" \
    -o -path "*/gifsicle/vendor/gifsicle" \
    -o -path "*/mozjpeg/vendor/cjpeg" \
    -o -path "*/mozjpeg/vendor/jpegtran" | sort -u); do
    if [ ! -e "$link" ]; then
        BROKEN="$BROKEN $link"
    fi
done
if [ -n "$BROKEN" ]; then
    echo "FATAL: Broken symlinks:$BROKEN"
    exit 1
fi
echo "All binary symlinks verified OK"
SCRIPT

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
