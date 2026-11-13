import './globals.css'
import type { Metadata } from 'next'
import { Providers } from './providers'
import { Header } from '@/components/ui'

export const metadata: Metadata = { title: 'AquaIndex', description: 'Programmable index protocol on 1inch Aqua + custom SwapVM (Sepolia testnet demo)' }

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <Header />
          <main className="mx-auto max-w-6xl space-y-4 px-4 py-6">{children}</main>
        </Providers>
      </body>
    </html>
  )
}
