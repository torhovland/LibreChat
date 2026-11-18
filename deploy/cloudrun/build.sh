#!/usr/bin/env bash
# Build the API image with Cloud Build.
#
# Plain `gcloud builds submit .` silently drops packages/api/tsconfig.json:
# gcloud's .gitignore matcher treats the legacy `api/tsconfig.json` rule as a
# suffix match, and the API build patch then cannot find the file. Archive the
# source explicitly and submit the object instead.
set -euo pipefail

PROJECT_ID=${PROJECT_ID:-librechat-513719}
REGION=${REGION:-europe-north1}
TAG=${TAG:-$(git rev-parse --short=12 HEAD)}
ARCHIVE=${ARCHIVE:-/tmp/librechat-source-${TAG}.tgz}

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

tar -czf "$ARCHIVE" \
  --exclude='./.git' \
  --exclude='./node_modules' \
  --exclude='./data-node' \
  --exclude='./uploads' \
  --exclude='./images' \
  --exclude='./logs' \
  --exclude='./meili_data*' \
  --exclude='./prep-stream-dev-restack' \
  .

SOURCE="gs://${PROJECT_ID}_cloudbuild/source/gha-${TAG}.tgz"
gsutil cp "$ARCHIVE" "$SOURCE"

gcloud builds submit "$SOURCE" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --config=deploy/cloudrun/cloudbuild.yaml \
  --substitutions=_TAG="$TAG"
