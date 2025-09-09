# Simple Dockerfile for Node 18+ no-deps feed generator
FROM node:20-alpine

WORKDIR /app

COPY package.json ./
COPY src ./src

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

CMD ["node", "src/server.js"]

