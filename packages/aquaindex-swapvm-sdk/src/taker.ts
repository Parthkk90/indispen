import { encodePacked, type Hex } from 'viem'

export interface TakerDataArgs {
  isExactIn: boolean
  isAToB: boolean // tokenIn is the lower-addressed token of the pair
  /** min amountOut (exactIn) or max amountIn (exactOut); 32-byte uint */
  threshold: bigint
  /** true: taker pays via transferFrom + Aqua push (required for Aqua strategies) */
  useTransferFromAndAquaPush?: boolean
  allowPartialFill?: boolean
}

/**
 * TakerTraitsLib.build for the hook-free case (no `to`, deadline, hooks, callbacks or signature).
 * The taker is implicit (msg.sender). Layout: 10 x uint16 slice ends, uint16 flags, uint256 threshold.
 * Verified byte-for-byte against Solidity in test/sdk.test.ts (golden.json `takerData`).
 */
export function buildTakerData(a: TakerDataArgs): Hex {
  const flags =
    (a.isExactIn ? 0x0001 : 0) |
    ((a.useTransferFromAndAquaPush ?? true) ? 0x0040 : 0) |
    (a.isAToB ? 0x0080 : 0) |
    (a.allowPartialFill ? 0x0100 : 0)
  const idx = Array(10).fill(32) as number[] // every slice ends at the 32-byte threshold
  // abi.encodePacked(index9..index0): index9 first
  const types = Array(10).fill('uint16') as 'uint16'[]
  return encodePacked([...types, 'uint16', 'uint256'], [...idx.reverse(), flags, a.threshold])
}
