---
name: spark-setup
description: "Configure la clé API Spark (spu_) + défauts client/projet (spark.yml). Triggers: \"spark setup\" | \"config spark api\" | \"installe clé spark\" | \"spark-setup\"."
---

# spark-setup — Config machine + workspace Spark API

Écrit la PAT Spark (**sans commit**, hors git) **et** initialise les défauts `client` / `project` pour le CLI.

## Objectif

```
✅ ~/.config/silex/spark.env (chmod 600)
   SPARK_URL=https://spark.gosilex.com
   SPARK_USER_API_KEY=spu_…
✅ ~/.config/silex/spark.yml   (machine) et/ou ./config/spark.yml (projet)
   client: <slug>
   project: <optionnel>
✅ smoke: GET /api/v1/tickets?meta=1 → 200
✅ smoke: spark.sh config show → client résolu
```

## Étapes

### 1. Préflight

```bash
mkdir -p ~/.config/silex
chmod 700 ~/.config/silex
test -f ~/.config/silex/spark.env && echo "spark.env présent" || echo "spark.env absent"
test -f ~/.config/silex/spark.yml && echo "spark.yml présent" || echo "spark.yml absent"
```

Ne **pas** afficher le contenu de la clé.

### 2. Obtenir la clé

1. Demander si l’utilisateur a déjà une PAT (Spark → Mon compte → Clés API).
2. Sinon guider : générer une clé → coller **une fois**. Ne pas afficher la clé complète.

### 3. Écrire spark.env (secrets)

```bash
# KEY=spu_…  URL=https://spark.gosilex.com
umask 077
cat > ~/.config/silex/spark.env <<EOF
SPARK_URL=${URL:-https://spark.gosilex.com}
SPARK_USER_API_KEY=${KEY}
EOF
chmod 600 ~/.config/silex/spark.env
```

### 4. Défaut client / projet (non secret)

Demander le **slug** de l’espace Spark (celui de l’URL `spark.gosilex.com/<slug>`) et optionnellement un **projet**.

```bash
: "${CLAUDE_PLUGIN_ROOT:?plugin silex-spark manquant}"
SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/spark-tickets/scripts/spark.sh"

# Machine (toujours) — défaut global agents
bash "$SCRIPT" config init --client "${CLIENT_SLUG}" ${PROJECT:+--project "$PROJECT"} --global --force

# Projet courant (si dans un repo métier / checkout client) — commitable
# bash "$SCRIPT" config init --client "${CLIENT_SLUG}" ${PROJECT:+--project "$PROJECT"} --force
```

Fichiers :

| Path | Usage |
|------|--------|
| `~/.config/silex/spark.yml` | Défaut machine |
| `./config/spark.yml` | Défaut workspace (équipe) — prioritaire sur le global |
| `SPARK_CLIENT` / `SPARK_PROJECT` | Override ponctuel |

**Priorité** : arg CLI / `--client` → env → config projet → `~/.config/silex/spark.yml`.

Exemple YAML :

```yaml
# pas de secrets ici
client: acme
# project: App
# url: https://spark.gosilex.com
```

### 5. Smoke test

```bash
bash "$SCRIPT" meta | head -c 400
echo
bash "$SCRIPT" config show
# si client configuré :
bash "$SCRIPT" tickets list --limit 1 2>/dev/null || bash "$SCRIPT" tickets list | head -c 200
```

Attendu : JSON meta OK ; `config show` affiche `client:` résolu.

### 6. Rapport (sans secret)

```
## Spark setup
- spark.env : ✅|❌
- spark.yml (global / projet) : ✅|❌
- URL : https://spark.gosilex.com
- client défaut : acme
- project défaut : (unset) | App
- prefix clé : spu_xxxxxxxx…
- meta : HTTP 200 | erreur
- suite : skill spark-tickets (« tickets list » sans client si config OK)
- create : défaut **interne** ; visible dans l’espace → `--public`
```

## Notes

- Rotation PAT : révoquer, regénérer, réécrire `spark.env` (yml inchangé).
- Le défaut `client` évite `--client` à chaque commande ; override toujours possible.
- Visibilité create : défaut `internal: true` ; `--public` si le ticket doit apparaître dans l’espace.
