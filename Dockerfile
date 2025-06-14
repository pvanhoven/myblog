FROM nginx:alpine

# Install nginx-mod-http-headers-more, this is used to modify response headers (hide Server header)
# RUN apk add --no-cache nginx-mod-http-headers-more

# Load the headers-more module
# RUN echo "load_module modules/ngx_http_headers_more_filter_module.so;" > /etc/nginx/modules/headers-more.conf

# Copy custom nginx main configuration that includes module loading
# COPY nginx-main.conf /etc/nginx/nginx.conf

# Copy the Hugo-generated static files to nginx web root
COPY public/ /usr/share/nginx/html/

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
