#!/usr/bin/env bash
set -euo pipefail

# Deploy CloudFront+S3 stack.
# Usage: ./infra/deploy-stacks.sh --domain example.com --hosted-zone-id Z123... [--env dev] [--bucket-prefix myblog] [--region us-east-1]

print_usage() {
  cat <<EOF
Usage: $0 --domain DOMAIN --hosted-zone-id ZONEID [options]

Required:
  --domain DOMAIN                Apex domain (e.g., phillvanhoven.com)
  --hosted-zone-id ZONEID       Route53 hosted zone ID for the domain

Options:
  --env ENV                     Environment (dev|prod). Default: dev
  --bucket-prefix PREFIX        Prefix for S3 bucket name. Default: myblog
  --region REGION               Region to deploy main stack in. Default: us-east-1
  --certificate-arn ARN         If provided, skip ACM creation and use this ARN
  --main-stack-name NAME        Name for main stack. Default: cf-site-${ENV}
  --wait-seconds SECONDS        Max wait for certificate issuance. Default: 1800 (30m)
  -h, --help                    Show this help
EOF
}

# Defaults
ENV=dev
BUCKET_PREFIX=myblog
REGION=us-east-1
CERTIFICATE_ARN=""
MAIN_STACK_NAME=""
WAIT_SECONDS=1800

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2;;
    --hosted-zone-id) HOSTED_ZONE_ID="$2"; shift 2;;
    --env) ENV="$2"; shift 2;;
    --bucket-prefix) BUCKET_PREFIX="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --certificate-arn) CERTIFICATE_ARN="$2"; shift 2;;
    --main-stack-name) MAIN_STACK_NAME="$2"; shift 2;;
    --wait-seconds) WAIT_SECONDS="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown argument: $1"; print_usage; exit 1;;
  esac
done

if [[ -z "${DOMAIN-}" || -z "${HOSTED_ZONE_ID-}" ]]; then
  echo "Error: --domain and --hosted-zone-id are required"
  print_usage
  exit 2
fi

: ${MAIN_STACK_NAME:="cf-site-${ENV}"}

echo "Deploying stacks for domain=${DOMAIN}, env=${ENV}, region=${REGION}"

# Create a CloudFormation change set (plan) instead of immediately deploying
echo "Preparing change set for main CloudFormation stack (${MAIN_STACK_NAME}) in region ${REGION}..."

CHANGE_SET_NAME="changeset-$(date +%s)"
# Determine whether this will be a CREATE or UPDATE
if aws cloudformation describe-stacks --stack-name "$MAIN_STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
  CHANGE_SET_TYPE=UPDATE
else
  CHANGE_SET_TYPE=CREATE
fi

echo "Creating change set ($CHANGE_SET_TYPE) named ${CHANGE_SET_NAME}..."
aws cloudformation create-change-set \
  --stack-name "$MAIN_STACK_NAME" \
  --change-set-name "$CHANGE_SET_NAME" \
  --change-set-type "$CHANGE_SET_TYPE" \
  --template-body file://cloudfront-s3-route53.yml \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
    ParameterKey=Environment,ParameterValue="$ENV" \
    ParameterKey=DomainName,ParameterValue="$DOMAIN" \
    ParameterKey=HostedZoneId,ParameterValue="$HOSTED_ZONE_ID" \
    ParameterKey=CertificateArn,ParameterValue="$CERTIFICATE_ARN" \
    ParameterKey=BucketNamePrefix,ParameterValue="$BUCKET_PREFIX"

echo "Waiting for change set creation to complete..."
if ! aws cloudformation wait change-set-create-complete --stack-name "$MAIN_STACK_NAME" --change-set-name "$CHANGE_SET_NAME" --region "$REGION"; then
  echo "Change set creation failed. Describing change set and recent stack events for debugging..."
  aws cloudformation describe-change-set --stack-name "$MAIN_STACK_NAME" --change-set-name "$CHANGE_SET_NAME" --region "$REGION" --output json || true
  aws cloudformation describe-stack-events --stack-name "$MAIN_STACK_NAME" --region "$REGION" || true
  exit 1
fi

echo "Change set created. Planned changes:"
aws cloudformation describe-change-set \
  --stack-name "$MAIN_STACK_NAME" \
  --change-set-name "$CHANGE_SET_NAME" \
  --region "$REGION" \
  --query 'Changes[].ResourceChange.{Action:Action,LogicalResourceId:LogicalResourceId,Replacement:Replacement}' --output table

read -r -p "Execute change set? (y/N): " EXECUTE_ANS
if [[ "$EXECUTE_ANS" =~ ^[Yy]$ ]]; then
  echo "Executing change set..."
  aws cloudformation execute-change-set --stack-name "$MAIN_STACK_NAME" --change-set-name "$CHANGE_SET_NAME" --region "$REGION"
  echo "Waiting for stack operation to complete..."
  if [[ "$CHANGE_SET_TYPE" == "CREATE" ]]; then
    aws cloudformation wait stack-create-complete --stack-name "$MAIN_STACK_NAME" --region "$REGION"
  else
    aws cloudformation wait stack-update-complete --stack-name "$MAIN_STACK_NAME" --region "$REGION"
  fi
  echo "Stack operation complete."
else
  echo "Change set created but not executed. To execute later run:"
  echo "  aws cloudformation execute-change-set --stack-name \"$MAIN_STACK_NAME\" --change-set-name \"$CHANGE_SET_NAME\" --region \"$REGION\""
fi

# If stack exists now, show outputs
if aws cloudformation describe-stacks --stack-name "$MAIN_STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Fetching stack outputs..."
  aws cloudformation describe-stacks --stack-name "$MAIN_STACK_NAME" --region "$REGION" --query "Stacks[0].Outputs" --output table
fi

cat <<EOF
Done. Next steps:
  - Upload site content: aws s3 sync public/ s3://<bucketname> --acl private
  - Create invalidation: aws cloudfront create-invalidation --distribution-id <id> --paths "/*"
  - Monitor certificate and DNS propagation.
EOF
