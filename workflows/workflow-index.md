# Spread Scanner — Workflow Index

Architecture: 12 parallel workflows at 5s interval (replaced 2 workflows at 30s).

## Spot Workflows (MEXC Spot vs Jupiter) — 7 groups, 73 tokens

| Workflow | n8n ID | Tokens (group_id) | Table |
|---|---|---|---|
| Spot G1 | JX88Gw4ppWNT0vuv | group_id = 1 (11 tokens) | spread_scans / spread_alerts |
| Spot G2 | LUpIxr0XzVqCmezN | group_id = 2 (11 tokens) | spread_scans / spread_alerts |
| Spot G3 | ZawcH4cQ6AEc6VDv | group_id = 3 (11 tokens) | spread_scans / spread_alerts |
| Spot G4 | GGcSV67shLtb5YCK | group_id = 4 (11 tokens) | spread_scans / spread_alerts |
| Spot G5 | U5VbED8t0IkTS0rS | group_id = 5 (11 tokens) | spread_scans / spread_alerts |
| Spot G6 | XauNaanIC6jyRQQS | group_id = 6 (11 tokens) | spread_scans / spread_alerts |
| Spot G7 | Hs2p1qZnPEQlYdF4 | group_id = 7 (7 tokens)  | spread_scans / spread_alerts |

## Futures Workflows (MEXC Futures vs Jupiter) — 5 groups, 53 tokens

| Workflow | n8n ID | Tokens (group_id) | Table |
|---|---|---|---|
| Futures G1 | bi1fccThboVkW8lK | group_id = 1 (11 tokens) | spread_scans_futures / spread_alerts_futures |
| Futures G2 | IbNvboPdZfqTflXh | group_id = 2 (11 tokens) | spread_scans_futures / spread_alerts_futures |
| Futures G3 | aTk4pwca0yBSVfI0 | group_id = 3 (11 tokens) | spread_scans_futures / spread_alerts_futures |
| Futures G4 | BdCXxPEGbM1YxtLm | group_id = 4 (11 tokens) | spread_scans_futures / spread_alerts_futures |
| Futures G5 | inwuU87vaI73bf3Y | group_id = 5 (9 tokens)  | spread_scans_futures / spread_alerts_futures |

## Deprecated Workflows (inactive)

| Workflow | n8n ID | Reason |
|---|---|---|
| CEX/DEX Spread Scanner - MEXC vs Jupiter Solana | LT8PIxYqhyloPEY9 | Replaced by Spot G1-G7 |
| CEX/DEX Spread Scanner - MEXC Futures vs Jupiter Solana | fraeBUMv6521C9A1 | Replaced by Futures G1-G5 |

## Key Parameters

- **Alert threshold**: ≥ 5% spread
- **Jupiter API**: `api.jup.ag/price/v3` with API key
- **MEXC Spot**: `api.mexc.com/api/v3/ticker/price`
- **MEXC Futures**: `contract.mexc.com/api/v1/contract/ticker`
- **Token assignment**: `common_tokens` / `common_tokens_futures` filtered by `group_id`
