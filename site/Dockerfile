FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund --frozen-lockfile || npm install --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginx:alpine
# Site is built with base: /essence, so assets reference /essence/...
# Drop the static files under /essence/ so request paths align.
COPY --from=builder /app/dist /usr/share/nginx/html/essence
COPY nginx.conf /etc/nginx/conf.d/default.conf
