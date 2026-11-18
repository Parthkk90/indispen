/** @type {import('next').NextConfig} */
export default {
  transpilePackages: ['@aquaindex/shared', '@aquaindex/swapvm-sdk'],
  webpack: (config) => {
    config.resolve.extensionAlias = { '.js': ['.ts', '.tsx', '.js'] }
    config.resolve.fallback = { ...config.resolve.fallback, fs: false }
    return config
  }
}
