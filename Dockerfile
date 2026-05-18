FROM node:22-slim

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production
COPY index.js prompts.js ./

ENV SYNTHESIS_BACKEND=claude
ENV OLLAMA_HOST=http://host.docker.internal:11434
ENV OLLAMA_MODEL=qwq:32b
ENV CLAUDE_MODEL=claude-haiku-4-5-20251001
ENV PORT=3250

EXPOSE ${PORT}

# supergateway wraps stdio MCP server as streamableHttp endpoint
CMD ["npx", "supergateway", \
     "--stdio", "node /app/index.js", \
     "--outputTransport", "streamableHttp", \
     "--port", "3250", \
     "--cors", \
     "--logLevel", "none", \
     "--healthEndpoint", "/health"]
