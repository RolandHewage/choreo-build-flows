ARG NGINX_IMAGE=choreoanonymouspullable.azurecr.io/nginxinc/nginx-unprivileged:stable-alpine-slim
FROM $NGINX_IMAGE
WORKDIR /app

# Update nginx user/group in alpine
ENV ENABLE_PERMISSIONS=TRUE
ENV DEBUG_PERMISSIONS=TRUE
ENV USER_NGINX=10015
ENV GROUP_NGINX=10015

COPY default.conf /etc/nginx/conf.d/default.conf
COPY error_404.html /usr/share/nginx/html/error_404.html

COPY . /usr/share/nginx/html/
USER root
RUN mkdir -p /app/public && \
  if [ -d /usr/share/nginx/html/public ]; \
  then cp -r /usr/share/nginx/html/public/* /app/public/; \
  fi && \
  rm -rf /usr/share/nginx/html/public && \
  ln -sf /app/public/ /usr/share/nginx/html/
USER 10015
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
