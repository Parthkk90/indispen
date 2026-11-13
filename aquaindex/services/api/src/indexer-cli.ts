import { syncOnce } from './indexer'
const start = BigInt(process.env.START_BLOCK ?? '12079000')
syncOnce(start).then((r) => { console.log('synced', r); process.exit(0) }).catch((e) => { console.error(e); process.exit(1) })
