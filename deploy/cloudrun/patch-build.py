#!/usr/bin/env python3
"""Apply the two build fixes needed when the API package is built from a fresh
upstream checkout. This is idempotent and is run by deploy/cloudrun/cloudbuild.yaml
before the Docker build.

Upstream builds `packages/api` with tsdown, but the `~/*` path alias is not
resolved in the Docker build context. The alias must be bundled into the CJS
output; otherwise the runtime looks for `/app/api/mcp/...` instead of the built
package under `/app/packages/api/dist`.
"""

from pathlib import Path

ROOT = Path('.')
TSCONFIG = ROOT / 'packages/api/tsconfig.json'
TSDOWN = ROOT / 'packages/api/tsdown.config.mjs'

# tsconfig.json is JSONC (it contains // comments), so patch it textually.
text = TSCONFIG.read_text()
if '"baseUrl"' not in text:
    anchor = '"rootDir": "../..",'
    if anchor not in text:
        raise SystemExit(
            'patch-build: packages/api/tsconfig.json changed shape; '
            'update deploy/cloudrun/patch-build.py before deploying',
        )
    TSCONFIG.write_text(text.replace(anchor, anchor + '\n    "baseUrl": ".",', 1))
    print('patch-build: added packages/api/tsconfig.json baseUrl')

text = TSDOWN.read_text()
if 'alias:' not in text:
    anchor = "  outDir: 'dist',\n  sourcemap: true,"
    if anchor not in text:
        raise SystemExit(
            'patch-build: packages/api/tsdown.config.mjs changed shape; '
            'update deploy/cloudrun/patch-build.py before deploying',
        )
    text = text.replace(
        anchor,
        "  outDir: 'dist',\n"
        "  sourcemap: true,\n"
        "  alias: {\n"
        "    '~': path.resolve(import.meta.dirname, 'src'),\n"
        "  },",
    )
    TSDOWN.write_text(text)
    print('patch-build: added packages/api/tsdown.config.mjs ~ alias')
