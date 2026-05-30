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
- **Fetch DB Tokens URL** : `common_tokens?select=symbol,mint,jup_volume_24h&group_id=eq.{N}`
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

### Jupiter Price Change

- Nouveau node **`Fetch Jupiter Stats`** (HTTP Request) sur la branche "spread détecté"
- Appel `api.jup.ag/tokens/v2/search?query={mint}` pour le top spread du cycle
- Fallback : `stats5m → stats1h → stats6h → stats24h → null`
- Colonne `jup_price_change` (real) sur `spread_alerts` et `spread_alerts_futures`
- Note : ANETON (token RWA Ondo tokenisé) retournera toujours null — pas de stats DEX disponibles

---

## Update — Optimisation Alertes & Filtres Qualité (2026-05-30)

### Déduplication intelligente des alertes

Trigger `BEFORE INSERT` sur `spread_alerts` et `spread_alerts_futures` :
- Si le même symbol a déjà été alerté dans les **5 dernières minutes** ET que le spread n'a pas changé de **±2%** → insert ignoré silencieusement
- Si le spread change de ≥2% dans la fenêtre → nouvelle alerte créée et fenêtre réinitialisée
- Header `Prefer: return=minimal,resolution=ignore-duplicates` ajouté comme filet de sécurité supplémentaire

Résultat : de ~7 alertes/minute/symbol → **max ~12 alertes/heure/symbol** (sauf si le spread évolue significativement)

### Filtres de qualité dans Calculate Spreads

Deux conditions supplémentaires pour valider un spread comme alerte :
1. **`liquidity > 0`** : extrait en temps réel de la réponse Jupiter `price/v3` (champ `liquidity` inclus dans la réponse)
2. **`volume > 0`** : `jup_volume_24h` depuis `common_tokens` / `common_tokens_futures` (mis à jour par les workflows Token Discovery)

```javascript
// Conditions de filtrage dans Calculate Spreads
if (liquidity <= 0 || volume <= 0) continue;  // skip zero-liquidity / zero-volume tokens
if (absSpread >= 5 && spreadPct > 0) { ... }   // threshold spread ≥ 5%
```

### Flow final (par workflow)

```
Schedule Trigger (5s)
→ Jitter Delay (0–3s random)
→ MEXC Tickers (spot: /ticker/price | futures: /contract/ticker)
→ Build MEXC Price Map
→ Fetch DB Tokens (symbol, mint, jup_volume_24h — filtered by group_id)
→ Find Common Tokens (+ volume from DB)
→ Prepare Batches
→ Fetch Jupiter Prices (price/v3 → usdPrice + liquidity, retry 3x/2s backoff)
→ Calculate Spreads
     filters: spread ≥ 5% AND liquidity > 0 AND volume > 0
→ Has Spreads?
   └─ [false] → stop — nothing written to DB
   └─ [true]
      → Fetch Jupiter Stats (tokens/v2/search → jup_price_change best timeframe)
      → Log Scan → spread_scans / spread_scans_futures (auto-pruned to 50/group)
      → Build MEXC Auth (pure-JS HMAC-SHA256)
      → Fetch MEXC Deposit Status
      → Enrich Spreads (deposit_open + jup_price_change)
      → Save Spread Alerts → spread_alerts / spread_alerts_futures
           dedup trigger: skip if same symbol < 5min ago AND spread change < 2%
```

### Migrations appliquées

| Fichier | Description |
|---|---|
| `005_rls_policies.sql` | RLS activé + policies anon sur 9 tables |
| `006_spread_scans_prune_and_cascade.sql` | Triggers auto-prune (50/group) + FK CASCADE |
| `007_add_jup_price_change_5m.sql` | Colonnes `jup_price_change_5m` (supprimées et remplacées par 008) |
| `008_alert_dedup_trigger_and_rename.sql` | Rename `jup_price_change_5m` → `jup_price_change` + triggers dedup 5min |
| `009_dedup_trigger_with_spread_change_threshold.sql` | Update trigger : autoriser nouvelle alerte si spread change ≥ 2% |

### Schema final spread_alerts

```
id, scan_id, scanned_at, symbol, mint,
mexc_price, jup_price, spread_pct, abs_spread_pct,
direction, exchanges, deposit_open, jup_price_change
```

### Credentials requis (voir credentials.example.json)

- Supabase project ref + anon key
- MEXC API key + secret (avec IP whitelist sur le serveur n8n)
- Jupiter API keys (3 clés recommandées pour 12 workflows)
