# Stage 1: Build the game
FROM node:18 AS builder

WORKDIR /shapez.io

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg default-jre git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies first for better caching
COPY package.json yarn.lock ./
RUN yarn

COPY gulp ./gulp
WORKDIR /shapez.io/gulp
RUN yarn

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
