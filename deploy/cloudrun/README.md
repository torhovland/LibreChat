# Deploy LibreChat to Cloud Run

This directory contains the Cloud Run deployment for this fork. It is designed
for a single-user deployment with a free MongoDB Atlas M0 cluster, a GCS bucket
for uploads/images, and a Meilisearch sidecar.

## Architecture

- `librechat` Cloud Run service
  - `api`: this fork, built from `Dockerfile.multi` target `api-build`
  - `meilisearch`: sidecar on `127.0.0.1:7700`
  - `/app/uploads` and `/app/client/public/images`: GCS FUSE mounts
  - `/app/.env` and `/app/librechat.yaml`: Secret Manager volumes
- `librechat-admin` Cloud Run service (the admin panel image)
- MongoDB Atlas M0 for the `LibreChat` database
- Cloud Run domain mappings for the public and admin hostnames

Because the Meilisearch sidecar has no persistent disk, `reset-meili.js` clears
the MongoDB `_meiliIndex` flags on every container start. The API then rebuilds
the search index into the fresh sidecar. This is intentional; 2.5k messages
index in a few seconds.

## Prerequisites

- A GCP project with billing enabled
- `gcloud auth login`
- APIs enabled:
  `run`, `artifactregistry`, `cloudbuild`, `secretmanager`, `siteverification`,
  `iam`, `storage`, `logging`, `monitoring`
- A free MongoDB Atlas M0 cluster and a `mongodb+srv://.../LibreChat` URI.
  The database name is required; without it Mongoose connects to `test`.
- `hovland.co` verified in Google Search Console
- The `CREDS_KEY`, `CREDS_IV`, `JWT_SECRET` and `JWT_REFRESH_SECRET` values from
  the old deployment. All four are often in `/app/data/.env.temp`, not `.env`;
  copying only `CREDS_IV` is not enough.
- Run `npm run migrate:tenant-indexes` once after restoring a pre-v0.8.7
  database, before starting the API. Otherwise startup logs `Index build
  failed` for `email_1`, `messageId_1`, `conversationId_1`, and similar.

## Automated deployment

Two GitHub Actions workflows own the deployment:

- `.github/workflows/deploy-cloudrun.yml` builds the current commit with Cloud
  Build and deploys it on every push to `main`, on manual dispatch, or when
  called by the sync workflow.
- `.github/workflows/sync-upstream.yml` runs daily at 04:00 UTC, merges
  `LibreChat-AI/LibreChat:main` into this fork's `main`, and then calls the
  deploy workflow if anything changed.

Authentication uses GitHub OIDC + Workload Identity Federation, so there are no
long-lived GCP keys in GitHub. The deploy service account is
`github-deploy@librechat-513719.iam.gserviceaccount.com`.

Database migrations are **not** automatic. If an upstream release requires one
(for example the tenant-index migration), run it manually per `UPGRADING.md`
before or after the deploy. The deploy workflow only replaces the Cloud Run
revision; a failed `/health` smoke test rolls traffic back to the previous
revision.

## Build

```sh
./deploy/cloudrun/build.sh
```

The script archives the source and submits the archive explicitly. A plain
`gcloud builds submit .` drops `packages/api/tsconfig.json` because gcloud's
`.gitignore` matcher treats the legacy `api/tsconfig.json` rule as a suffix
match. `cloudbuild.yaml` runs `deploy/cloudrun/patch-build.py` first. The patch is kept
out of the tracked upstream files so daily upstream merges stay clean. If you
build with plain `docker build` instead of Cloud Build, run the patch first:

```sh
python3 deploy/cloudrun/patch-build.py
docker build -f Dockerfile.multi --target api-build -t librechat-api-base:cloudrun .
docker build -f deploy/cloudrun/Dockerfile \
  --build-arg BASE_IMAGE=librechat-api-base:cloudrun \
  -t <artifact-registry>/librechat/api:local .
```

## Deploy

```sh
export PROJECT_ID=librechat-513719
export REGION=europe-north1
export BUCKET=librechat-513719-files
export SERVICE_ACCOUNT=librechat-run@librechat-513719.iam.gserviceaccount.com
export IMAGE=europe-north1-docker.pkg.dev/librechat-513719/librechat/api:<tag>
export ADMIN_IMAGE=europe-north1-docker.pkg.dev/librechat-513719/librechat/admin-panel:latest
export DOMAIN=librechat.hovland.co

envsubst < deploy/cloudrun/service.yaml.tmpl > /tmp/librechat-service.yaml
envsubst < deploy/cloudrun/admin-service.yaml.tmpl > /tmp/librechat-admin-service.yaml

gcloud run services replace /tmp/librechat-service.yaml --region="$REGION"
gcloud run services replace /tmp/librechat-admin-service.yaml --region="$REGION"

gcloud run services add-iam-policy-binding librechat \
  --region="$REGION" --member=allUsers --role=roles/run.invoker
gcloud run services add-iam-policy-binding librechat-admin \
  --region="$REGION" --member=allUsers --role=roles/run.invoker
```

## Domain mappings

```sh
gcloud beta run domain-mappings create \
  --service=librechat --domain=librechat.hovland.co \
  --region=europe-north1 --project=librechat-513719

gcloud beta run domain-mappings create \
  --service=librechat-admin --domain=admin.librechat.hovland.co \
  --region=europe-north1 --project=librechat-513719

gcloud beta run domain-mappings describe \
  --domain=librechat.hovland.co \
  --region=europe-north1 --project=librechat-513719 \
  --format='yaml(status.resourceRecords)'
```

Add the returned DNS records at the registrar. Managed TLS normally provisions
in about 15 minutes (up to 24 hours).

## Migrating data

1. Stop the local API (keep Mongo running):
   `docker stop LibreChat admin-panel`
2. Dump:
   ```sh
   docker exec chat-mongodb mongodump --db LibreChat --archive --gzip \
     > /tmp/librechat-final.gz
   ```
3. Restore to Atlas:
   ```sh
   docker run --rm -i -v /tmp:/backup:ro mongo:8.0.20 \
     mongorestore --uri="$ATLAS_URI" --archive=/backup/librechat-final.gz --gzip --drop
   ```
4. Mirror files:
   ```sh
   gsutil -m rsync -r -d /home/tor/projects/LibreChat-local/uploads gs://librechat-513719-files/uploads
   gsutil -m rsync -r -d /home/tor/projects/LibreChat-local/images gs://librechat-513719-files/images
   ```
5. Update the `librechat-env` secret with the real `MONGO_URI`, then roll a new
   revision so the entrypoint resets the Meili flags:
   ```sh
   gcloud secrets versions add librechat-env --data-file=production.env
   gcloud run services update librechat --region=europe-north1 \
     --update-env-vars=DATA_REVISION=$(date +%s)
   ```

## Notes

- `ALLOW_REGISTRATION=false` is set in the production env.
- `SCHEDULES_SINGLE_PROCESS=true` is set because Cloud Run is limited to one
  replica and Redis is not used.
- `ADMIN_PANEL_URL=https://admin.librechat.hovland.co` must match the admin
  service hostname for the API's same-origin check.
- Cloud Run domain mapping is a Preview feature. For production-grade TLS
  (TLS 1.2+ only, wildcard certificates), put a global external HTTPS load
  balancer in front of the services instead.
- Cold starts rebuild the Meili index; the first request after idle can take
  ~15–30 seconds.
