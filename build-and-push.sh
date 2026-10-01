#!/usr/bin/env bash
# build-and-push.sh — Build the processor Docker image and push to ECR
# Run this before `terraform apply` on first deploy, and after any processor code change.

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PREFIX="${PREFIX:-obs-talk-demo}"
REPO_NAME="${PREFIX}-processor"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ECR_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}"

echo "▶ Creating ECR repository (if not exists)..."
aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${AWS_REGION}" \
  || aws ecr create-repository \
       --repository-name "${REPO_NAME}" \
       --region "${AWS_REGION}" \
       --image-scanning-configuration scanOnPush=true

echo "▶ Authenticating Docker with ECR..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "▶ Building image..."
docker build \
  --platform linux/amd64 \
  -t "${REPO_NAME}:${IMAGE_TAG}" \
  -f app/processor/Dockerfile \
  app/

echo "▶ Tagging and pushing..."
docker tag "${REPO_NAME}:${IMAGE_TAG}" "${ECR_REPO}:${IMAGE_TAG}"
docker push "${ECR_REPO}:${IMAGE_TAG}"

echo "✅ Image pushed: ${ECR_REPO}:${IMAGE_TAG}"
echo ""
echo "Next step: cd terraform/envs/demo && terraform apply"
