'use client'
import { useQuery } from '@tanstack/react-query'
import { API } from './config'

export async function get<T = any>(path: string): Promise<T> {
  const r = await fetch(`${API}${path}`)
  const j = await r.json()
  if (!r.ok) throw new Error(j.error ?? r.statusText)
  return j
}

export const useApi = <T = any>(path: string | null, refetchMs = 15000) =>
  useQuery<T>({ queryKey: ['api', path], queryFn: () => get<T>(path!), enabled: !!path, refetchInterval: refetchMs })
