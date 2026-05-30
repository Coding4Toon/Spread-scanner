# Plan : Parallelisation Spread Scanner (Multi-Workflow)

## Context

Le scanner actuel tournait à 30s d'intervalle avec 1 workflow pour 73 tokens spot et 1 workflow pour 53 tokens futures. L'objectif est de descendre à 5 secondes en découpant les tokens en sous-groupes, chaque groupe géré par un workflow dédié. Cela multiplie la fréquence de scan sans changer la logique métier.

## Architecture cible

| Type | Workflows | Tokens/workflow | Intervalle |
|---|---|---|---|
| Spot | 7 | ~10-11 tokens | 5s |
| Futures | 5 | ~10-11 tokens | 5s |

73 spot / 7 = ~10.4 → 4 groupes de 10, 3 groupes de 11.
53 futures / 5 = ~10.6 → 2 groupes de 11, 3 groupes de 10. Tous les tokens sont conservés.

## Étape 1 : Migration DB

Ajout d'une colonne `group_id` sur les tables de tokens et les tables de scan.
Voir `supabase/migrations/004_add_group_id_parallelisation.sql`.

## Étape 2 : Désactivation des workflows legacy

- `LT8PIxYqhyloPEY9` — CEX/DEX Spread Scanner - MEXC vs Jupiter Solana → **inactif**
- `fraeBUMv6521C9A1` — CEX/DEX Spread Scanner - MEXC Futures vs Jupiter Solana → **inactif**

## Étape 3 : Nouveaux workflows

Voir `workflows/workflow-index.md` pour la liste complète des IDs n8n.

Chaque workflow ne change que 3 choses par rapport au template :
- **Nom** : `CEX/DEX Spread Scanner - Spot G{N}` ou `Futures G{N}`
- **Fetch DB Tokens URL** : `common_tokens?select=symbol,mint&group_id=eq.{N}`
- **Log Scan payload** : `group_id: {N}` ajouté

## Charge API estimée

| API | Avant | Après |
|---|---|---|
| MEXC `/ticker/price` | 2/min | 84/min (1.4/s) — OK |
| Jupiter `/price/v3` | 2/min | 144/min (2.4/s) — OK avec API key |

## Vérification

```sql
-- Vérifier la répartition des tokens par groupe
SELECT group_id, COUNT(*) FROM common_tokens GROUP BY group_id ORDER BY group_id;
SELECT group_id, COUNT(*) FROM common_tokens_futures GROUP BY group_id ORDER BY group_id;

-- Vérifier que les scans arrivent bien par groupe (après ~30s)
SELECT group_id, COUNT(*), MAX(scanned_at) FROM spread_scans GROUP BY group_id ORDER BY group_id;
SELECT group_id, COUNT(*), MAX(scanned_at) FROM spread_scans_futures GROUP BY group_id ORDER BY group_id;
```

---

## Update — Filtre direction DEX→CEX uniquement

**Contexte :** Seule la direction **Buy JUP → Sell MEXC** est intéressante (arb DEX→CEX). La direction inverse (Buy MEXC → Sell JUP) a été supprimée.

**Changement appliqué sur les 12 workflows** (nœud `Calculate Spreads`) :

```javascript
// Avant
if (absSpread >= 5) {
  spreads.push({ ..., direction: spreadPct > 0 ? 'Buy JUP -> Sell MEXC' : 'Buy MEXC -> Sell JUP' });
}

// Après
if (absSpread >= 5 && spreadPct > 0) {
  spreads.push({ ..., direction: 'Buy JUP -> Sell MEXC' });
}
```

```sql
-- Vérification : une seule direction en DB
SELECT DISTINCT direction FROM spread_alerts;
SELECT DISTINCT direction FROM spread_alerts_futures;
```

---

## Update — Production Hardening (2026-05-30)

### Clés API & Sécurité

- **MEXC API Key** : rotation vers nouvelle clé avec IP whitelist `72.62.70.105` (IP du serveur n8n)
- **Jupiter API** : 3 clés distribuées, 4 workflows par clé pour répartir la charge
  - Clé 1 → Spot G1-G4
  - Clé 2 (Corto) → Spot G5-G7 + Futures G1
  - Clé 3 (Thundori) → Futures G2-G5
- **RLS** : policies ajoutées sur 9 tables précédemment exposées sans protection (voir migration 005)

### Rate Limiting Jupiter (résolu)

- Retry avec **2s de backoff** entre tentatives (`waitBetweenTries: 2000`, `maxTries: 3`)
- **Jitter Delay** (0–3s aléatoire) ajouté comme premier node après Schedule Trigger — évite la synchronisation simultanée des 12 workflows sur le même tick

### Optimisation DB

- **Log Scan conditionnel** : déplacé après `Has Spreads?` — aucune insertion si 0 spread détecté (~95% des cycles silencieux)
- **Auto-prune** : trigger Postgres garde les **50 derniers scans par `group_id`** (illimité avant → croissance inutile)
- **FK CASCADE** : suppression d'un scan cascade automatiquement sur ses alertes liées
- **Données purgées** au 2026-05-30 — repartir de zéro après optimisation

### Jupiter 5min Price Change

- Nouveau node **`Fetch Jupiter Stats`** inséré sur la branche "spread détecté" uniquement
- Appel `api.jup.ag/ultra/v1/search?query={mint}&mode=strict` (endpoint public, pas de clé) par token en spread
- Champ `stats5m.priceChange` stocké dans colonne `jup_price_change_5m` (real) sur `spread_alerts` et `spread_alerts_futures`

### Flow final (par workflow)

```
Schedule Trigger (5s)
→ Jitter Delay (0–3s random)
→ MEXC Tickers (spot: /ticker/price | futures: /contract/ticker)
→ Build MEXC Price Map
→ Fetch DB Tokens (filtered by group_id)
→ Find Common Tokens
→ Prepare Batches
→ Fetch Jupiter Prices (api.jup.ag/price/v3, retry 3x backoff 2s)
→ Calculate Spreads (threshold ≥5%, Buy JUP→Sell MEXC only)
→ Has Spreads?
   └─ [false] → stop — nothing written to DB
   └─ [true]
      → Fetch Jupiter Stats (stats5m.priceChange via ultra/v1/search)
      → Log Scan → spread_scans / spread_scans_futures  (auto-pruned to 50/group)
      → Build MEXC Auth (pure-JS HMAC-SHA256, no external deps)
      → Fetch MEXC Deposit Status (capital/config/getall)
      → Enrich Spreads (deposit_open + jup_price_change_5m)
      → Save Spread Alerts → spread_alerts / spread_alerts_futures
```

### Migrations appliquées

| Fichier | Description |
|---|---|
| `005_rls_policies.sql` | RLS activé + policies anon sur 9 tables |
| `006_spread_scans_prune_and_cascade.sql` | Triggers auto-prune (50/group) + FK CASCADE |
| `007_add_jup_price_change_5m.sql` | Colonnes `jup_price_change_5m` sur les tables d'alertes |

### Schema final spread_alerts

```
id, scan_id, scanned_at, symbol, mint,
mexc_price, jup_price, spread_pct, abs_spread_pct,
direction, exchanges, deposit_open, jup_price_change_5m
```

### Credentials requis (voir credentials.example.json)

- Supabase project ref + anon key
- MEXC API key + secret (avec IP whitelist sur le serveur n8n)
- Jupiter API keys (3 clés recommandées pour 12 workflows)
