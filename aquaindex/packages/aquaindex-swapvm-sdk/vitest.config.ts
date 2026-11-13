import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    // @1inch/swap-vm-sdk's ESM build imports extensionless paths from @1inch/byte-utils; inline so Vite resolves them.
    server: { deps: { inline: [/@1inch\//] } }
  }
})
