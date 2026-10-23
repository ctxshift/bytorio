FROM nginx:stable-alpine

COPY site/deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/site/ /usr/share/nginx/html/

EXPOSE 8080
