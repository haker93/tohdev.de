# Build stage
FROM hugomods/hugo:latest AS builder

WORKDIR /src

# Copy project files
COPY . .

# Build Hugo site
RUN hugo --minify

# Production stage with nginx
FROM nginx:alpine

# Copy built site from builder
COPY --from=builder /src/public /usr/share/nginx/html

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
