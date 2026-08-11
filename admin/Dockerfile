# Stage 1: Build the React application
FROM node:20-alpine AS build-stage
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Serve the application with Nginx
FROM nginx:alpine
COPY --from=build-stage /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
# Shared proxy directives, included by every backend-facing location.
COPY nginx-proxy.conf /etc/nginx/nginx-proxy.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
