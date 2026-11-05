/**
 * Meilisearch sidecars on Cloud Run lose their index when the instance scales
 * to zero or is replaced. Reset the MongoDB sync flags so the next startup
 * performs a full re-index into the fresh sidecar.
 *
 * This runs only when FORCE_MEILI_RESYNC=true and SEARCH=true.
 */
require('dotenv').config({ path: '/app/.env' });

const mongoose = require('mongoose');

async function main() {
  if (process.env.SEARCH !== 'true') {
    console.log('[meili-reset] SEARCH is not enabled; skipping');
    return;
  }

  const uri = process.env.MONGO_URI;
  if (!uri) {
    throw new Error('MONGO_URI is not set');
  }

  await mongoose.connect(uri, { serverSelectionTimeoutMS: 20000 });
  const db = mongoose.connection.db;

  for (const collectionName of ['messages', 'conversations']) {
    const result = await db
      .collection(collectionName)
      .updateMany({}, { $set: { _meiliIndex: false } });
    console.log(
      `[meili-reset] ${collectionName}: queued ${result.modifiedCount} document(s) for re-index`,
    );
  }

  await mongoose.disconnect();
}

main().catch((error) => {
  console.error('[meili-reset] failed:', error);
  process.exit(1);
});
