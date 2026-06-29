CloudFront + S3 migration for this Hugo blog

Overview
- This repository contains a Hugo static site (see content/, hugo.toml, Dockerfile).
- Infra to migrate hosting from App Runner to CloudFront+S3 is under infra/.

Files of interest (infra/):
- infra/acm-cert-us-east-1.yml — CloudFormation stack to request an ACM certificate in us-east-1 (DNS validation via Route53). Deploy this first.
- infra/cloudfront-s3-route53.yml — Main CloudFormation template to create the S3 site bucket, CloudFront distribution (OAI), and Route53 alias records. Pass the CertificateArn from the ACM stack.
- infra/deploy-policy.yml — Minimal IAM managed policy for upload and invalidation. Bind to a CI/CD role or deploy user with the BucketName parameter.
- infra/deploy-stacks.sh — Helper script to deploy ACM stack (us-east-1), wait for certificate issuance, then deploy the main CloudFormation stack.

Quick deploy workflow (dev)
1. Ensure AWS CLI is configured for the target dev account and you have permissions for CloudFormation/ACM/Route53/S3/CloudFront.

2. Request ACM certificate (us-east-1) and wait for issuance:
   ./infra/deploy-stacks.sh --domain phillvanhoven.com --hosted-zone-id Z<HOSTEDZONEID> --env dev --bucket-prefix myblog

3. Build the Hugo site (local machine or CI) before uploading to S3:
   - Install Hugo (see https://gohugo.io/getting-started/installation/)
   - Build for production with minification:
       hugo --minify
     This writes the generated static files to the public/ directory by default.
   - (Optional) If you need to set baseURL at build time:
       hugo --minify --baseURL "https://phillvanhoven.com/"

4. Upload the generated site to the S3 bucket created by the CloudFormation stack:
   - Find the bucket name in CloudFormation stack outputs (SiteBucketName).
   - Sync public/ to S3 (recommended flags shown):
       aws s3 sync public/ s3://<bucketname> --acl private --delete \
         --cache-control "public, max-age=31536000, immutable" \
         --exclude "index.html" --content-type "text/html; charset=utf-8"
     Note: You may want to set finer-grained cache-control headers per file type. The example is illustrative.

5. Create a CloudFront invalidation to refresh cached content:
   aws cloudfront create-invalidation --distribution-id <id> --paths "/*"

Notes and caveats
- ACM certificate must be created in us-east-1 for CloudFront. infra/acm-cert-us-east-1.yml includes an explanation.
- The ACM stack requests a wildcard certificate (*.example.com) with SANs for the apex and www. This covers subdomains and simplifies reuse.
- The deploy helper infra/deploy-stacks.sh waits for the certificate to reach ISSUED state before deploying the main stack.
- The S3 bucket is configured with public access blocked and a bucket policy that permits CloudFront to read via an Origin Access Identity.

Questions or next steps
- If desired, deploy-stacks.sh can be extended to upload public/ and create invalidations automatically; confirm if this should be enabled.
