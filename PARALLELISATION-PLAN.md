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
