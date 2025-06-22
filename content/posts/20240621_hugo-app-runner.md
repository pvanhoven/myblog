---
title: "Hugo App Runner"
date: 2025-06-21T10:21:01-06:00
draft: true
---

# Hosting a Hugo Blog in AWS App Runner

Hugo is great option to host a blog/static content site. Combining Hugo and AWS App Runner is a simple and straightforward approach to hosting your own blog at a reasonable cost. Few items this blog will walk through

- [Create a basic hugo site](#create-a-hugo-site)
- [Create an nginx Configuration File](#create-an-nginx-configuration-file)
- [Create an ECR Registry](#create-an-ecr-registry)
- [Create a Docker Container](#create-a-docker-container)
- [Building a Docker image for Hugo + NGINX](#building-a-docker-image-for-hugo--nginx)
- [Deploying to AWS App Runner](#deploying-to-aws-app-runner)
- [Request a domain in AWS](#request-a-domain-in-aws)
- [Create a hosted zone tied to your new domain in Route 53](#create-a-hosted-zone-tied-to-your-new-domain-in-route-53)
- [Request a public certificate to use with your App Runner custom domain](#request-a-public-certificate-to-use-with-your-app-runner-custom-domain)
- [Update App Runner with custom domains](#update-app-runner-with-custom-domains)

## Create a Hugo Site

Follow the Hugo [Quick Start](https://gohugo.io/getting-started/quick-start/) guide. A basic Hugo site is sufficient for this guide.

Be sure you can run `hugo` from a terminal to generate the `public` folder. This folder will be copied to the docker conainer and deployed to AWS.

## Create an nginx Configuration File

We'll create a docker container to host the nginx instance. This configuration file will be needed once we create the container.

Create a file named `nginx.conf`

```
server {
    listen       80;
    server_name  localhost  # add your custom domain(s) here
    root         /usr/share/nginx/html;
    index        index.html;

    # Enable gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Handle Hugo's pretty URLs
    location / {
        try_files $uri $uri/ $uri/index.html =404;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Handle 404 errors
    error_page 404 /404.html;
}
```

## Create an ECR Registry

ECR includes 500mb free storage (as of writing this blog post). Creating a private repository requires a name only. All other default settings are are sufficent

1. Search ECR from the AWS console
1. Click 'Create repository'
1. Enter repository name and 'Create'

## Create a Docker Container

This container can be run locally and can be pushed to AWS Elastic Container Registry (ECR).

Create a file named `Dockerfile`

```
FROM nginx:alpine

# Copy the Hugo-generated static files to nginx web root.
COPY public/ /usr/share/nginx/html/

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
```
