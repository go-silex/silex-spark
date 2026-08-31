---
name: spark-tickets
description: "API Spark PAT spu_ : tickets Pilotage + discussion + board tasks + resources/journeys/org/accueil + projets + liens + GitHub. Triggers: \"spark tickets\" | \"spark tasks\" | \"spark resources\" | \"spark journeys\" | \"spark orgchart\" | \"spark accueil\" | \"list tickets spark\" | \"crée un ticket spark\" | \"commente le ticket\" | \"board tâches\" | \"spark projects\" | \"spark links\" | \"spark api\" | \"spark meta\"."
---

# spark-tickets — API Spark (PAT)

Appelle l’API **prod** Spark avec la clé personnelle `spu_…` (droits du compte).

Plugin SSOT : `go-silex/spark` → `plugins/silex-spark/`. Miroir public : `go-silex/silex-spark`.

**Ne jamais afficher la clé complète** dans le chat (prefix `spu_xxxxxxxx…` max).

## Config (résolution)

### Secrets (PAT)

Ordre (première source non vide) :

1. Env `SPARK_USER_API_KEY` (ou `SPARK_API_KEY` si préfixe `spu_`)
2. `~/.config/silex/spark.env` (`SPARK_URL` + `SPARK_USER_API_KEY`)
3. `~/.config/silex/spark-user-api-key` (clé seule)
4. BW note **`gosilex/spark-user-api-key`** (si `bw` + session agent)

URL défaut : `https://spark.gosilex.com` (sinon `url:` dans spark.yml).

Si aucune clé → skill **`spark-setup`**.

### Client / projet (défauts non secrets)

| Priorité | Source |
|----------|--------|
| 1 | Arg CLI / `--client` / `--project` |
| 2 | Env `SPARK_CLIENT` / `SPARK_PROJECT` |
| 3 | `./config/spark.yml` (ou `.spark.yml`, remonte les parents) |
| 4 | `~/.config/silex/spark.yml` |

```bash
bash "$SCRIPT" config show
bash "$SCRIPT" config init --client acme [--project App] [--global]
bash "$SCRIPT" config set client acme
# puis :
bash "$SCRIPT" tickets list              # client depuis yml
bash "$SCRIPT" tickets get 42            # --client implicite
bash "$SCRIPT" tickets patch 42 '{"priority":"p1"}'
```

## CLI

```bash
# Toujours via le plugin installé (marketplace) — jamais un path clone local.
: "${CLAUDE_PLUGIN_ROOT:?plugin silex-spark manquant — claude plugin install silex-spark@silex-spark}"
SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/spark-tickets/scripts/spark.sh"
[ -f "$SCRIPT" ] || { echo "spark.sh introuvable sous CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT" >&2; exit 1; }
chmod +x "$SCRIPT" 2>/dev/null || true
```

| Intent | Commande |
| --- | --- |
| Discovery tickets | `bash "$SCRIPT" meta` |
| Discovery liens | `bash "$SCRIPT" meta-links` |
| Discovery projets | `bash "$SCRIPT" meta-projects` |
| Catalogue v1 | `bash "$SCRIPT" v1` |
| Lister tickets (+ **links** inclus) | `bash "$SCRIPT" tickets list <clientSlug>` |
| Rechercher / filtrer tickets | `bash "$SCRIPT" tickets search <clientSlug> [options]` |
| Créer ticket | `bash "$SCRIPT" tickets create <clientSlug> "Titre" "Body?" [--priority p0\|p1\|p2\|p3] [--type bug\|feature] [--project id\|name] [--internal\|--public]` |
| Patch ticket | `bash "$SCRIPT" tickets patch <id\|ref> '{"priority":"p1"}' [--client slug]` |
| Non retenu (+ doublon + commentaire) | `bash "$SCRIPT" tickets reject <id\|ref> [--client slug] [--duplicate <ref>] [--comment "…"]` |
| Détail ticket (+ comments) | `bash "$SCRIPT" tickets get <id\|ref> [--client slug]` |
| Lister commentaires | `bash "$SCRIPT" tickets comments list <id\|ref> [--client slug]` |
| Poster / répondre | `bash "$SCRIPT" tickets comments add <id\|ref> "body" [--parent N] [--internal] [--client slug]` |
| Lister issues GH liées | `bash "$SCRIPT" tickets github-list <id\|ref> [--client slug]` |
| Créer issue GitHub | `bash "$SCRIPT" tickets github-create <id\|ref> [--client slug]` |
| Lier issue GitHub | `bash "$SCRIPT" tickets github-link <id\|ref> "#42" [--client slug]` |
| Délier issue GitHub | `bash "$SCRIPT" tickets github-unlink <id\|ref> 42 [--client slug]` |
| Lister ressources | `bash "$SCRIPT" resources list <clientSlug>` |
| Détail ressource (+ body markdown) | `bash "$SCRIPT" resources get <id> [client]` |
| Créer lien | `bash "$SCRIPT" resources create <client> <title> <url> [--category Lectures] [--internal]` |
| Créer markdown (CR) | `bash "$SCRIPT" resources create-md <client> <title> [body] [--category Comptes-rendus] [--public]` |
| Créer fichier (PDF/image/vidéo) | `bash "$SCRIPT" resources create-file <client> <path/to/file> [title] [--category Lectures] [--internal]` |
| Patch ressource | `bash "$SCRIPT" resources patch <id> '{"title":"…","body":"…"}' [--client slug]` |
| Supprimer ressource | `bash "$SCRIPT" resources delete <id> [client]` |
| Journeys list/create/get/patch/delete | `bash "$SCRIPT" journeys …` |
| Organigramme get/put | `bash "$SCRIPT" orgchart get\|put …` |
| Accueil get/patch | `bash "$SCRIPT" accueil get\|patch …` |
| Board Tâches (≠ tickets) | `bash "$SCRIPT" tasks list\|create\|get\|patch\|delete …` |
| Comments board tâches | `bash "$SCRIPT" tasks comments list\|add …` |
| Lister projets | `bash "$SCRIPT" projects list <clientSlug> [--kind development]` |
| Lookup projet par dépôt GitHub | `bash "$SCRIPT" projects by-repo <owner>/<repo>` |
| Créer projet | `bash "$SCRIPT" projects create <clientSlug> "Nom" [kind] [color]` |
| Patch projet | `bash "$SCRIPT" projects patch <id> '{"name":"…"}'` |
| Supprimer projet | `bash "$SCRIPT" projects delete <id> [clientSlug]` |
| Lister liens | `bash "$SCRIPT" links list <client> [--task <id\|ref>] [--kind parent\|blocks]` |
| Créer lien | `bash "$SCRIPT" links add <client> <task> <relation> <other>` |
| Supprimer lien | `bash "$SCRIPT" links delete <client> <linkId>` |

### Relations (`links add`)

| relation | Effet |
| --- | --- |
| `parent` | other = **parent** de task |
| `child` | other = **enfant** de task |
| `blocks` | task **bloque** other |
| `blocked_by` | task est **bloquée par** other |
| `duplicates` | task est **doublon de** other (canonique) |
| `duplicated_by` | other est **doublon de** task |

`task` / `other` : cuid **ou** ref (`42`, `#42`).

```bash
# #12 parent de #18
bash "$SCRIPT" links add acme 18 parent 12
# #18 bloquée par #12
bash "$SCRIPT" links add acme 18 blocked_by 12
# #147 est un doublon de #149
bash "$SCRIPT" links add acme 147 duplicates 149
# Non retenu + doublon + commentaire (atomique)
bash "$SCRIPT" tickets reject 147 --client acme --duplicate 149 --comment "Doublon du besoin"
```

Si le compte accède à **plusieurs espaces**, passer le slug (`--client` / arg).  
`tickets list` renvoie **toujours** `ticket.links` : `{ parent, children, blocks, blockedBy, duplicatesOf, duplicatedBy }`.

### `tickets create` — visibilité + priorité

| Flag | Effet (PAT staff / agent) |
| --- | --- |
| *(aucun)* | **`internal: true`** — défaut API staff (safe agents) |
| `--internal` | `internal: true` (explicite) |
| `--public` | `internal: false` (visible client + notifs client) |
| `--priority p0\|p1\|p2\|p3` | Priorité dès le create (défaut API **p2** si omis) |
| `--type bug\|feature` | Type ticket (défaut API **feature**) |
| `--project <cuid\|name>` | `projectId` — CUID ou nom **unique** (ambigu → 400). Omis : rattache le seul projet Pilotage s'il n'y en a qu'un. |

```bash
# Tech debt / note staff / travail agent → défaut OK (interne)
bash "$SCRIPT" tickets create acme "Tech debt: …" "…"

# Bug ou évolution **visible client** → OBLIGATOIRE --public
bash "$SCRIPT" tickets create acme "Bouton budget cassé" "…" --public

# Priorité haute dès le create
bash "$SCRIPT" tickets create acme "Images cassées" "…" --public --priority p0 --type feature
```

### `tickets search` (filtres API)

```bash
bash "$SCRIPT" tickets search acme --priority p0 --status todo --limit 20
bash "$SCRIPT" tickets search acme --type feature --project App --query "github"
bash "$SCRIPT" tickets search acme --onRoadmap --priority p1,p2
```

| Option | Query API | Notes |
| --- | --- | --- |
| `--priority p0\|p1\|…` | `priority=` | CSV accepté |
| `--status todo\|…` | `status=` | CSV accepté |
| `--type bug\|feature` | `type=` | |
| `--project <id\|name>` | `project=` | CUID ou **nom unique** ; si plusieurs matchs → 400 + `candidates` (passer le CUID) |
| `--onRoadmap` | `onRoadmap=1` | aussi `--onRoadmap=false` |
| `--internal` | `internal=1` | staff |
| `--assignee <id>` | `assignee=` | User.id |
| `--query "…"` | `query=` | title + description |
| `--limit N` | `limit=` | défaut **100** (list = sans plafond) |
| `--offset N` | `offset=` | défaut 0 |

Réponse : `{ tickets, total, limit, offset }` (+ `.links` par ticket).

## Comportement agent

1. Parser l’intent (tickets / tasks / resources / journeys / org / accueil / projects / links / github / comments / meta).
2. Préférer le CLI (moins de contexte qu’un curl inventé). **Jamais** `get|post https://…` absolu (PAT).
3. Résumer en français : refs, surfaces, liens, issues GH, discussion, erreurs API.
4. Si 401 → `spark-setup`. Si 403 section → verrous Admin.
5. Un 403 = section verrouillée ou rôle insuffisant pour cette écriture.
6. Projets `development` = Pilotage ; défaut CLI create = `kind=development`.
7. GitHub : projet `githubEnabled` + repo ; `:id` = **cuid** ticket **ou** ref + `--client` (même règle que get/patch).
8. **Résolution d’identifiants** (unicité stricte) :
   - **CUID** → toujours OK (unique global).
   - **Ref numérique** `#N` / `N` → unique par espace → **`--client <slug>`** si plusieurs espaces (sinon 400).
   - **Nom** (projet) → exactement 1 match (exact puis contains) ; sinon **400** + `candidates` → passer le CUID.
9. Scopes `tickets:read|write` = **API v1 générique** (toutes surfaces), pas « tickets only ».

### Discussion (comments = fil Task)

Vocabulaire : **tickets** = Pilotage · **tasks** = board Tâches · **task-links** = relations · **comments** = Discussion (tickets *ou* tasks).

```bash
# Lire ticket + fil
bash "$SCRIPT" tickets get <cuid|ref> [--client slug]
# Patch (ref → --client si plusieurs espaces)
bash "$SCRIPT" tickets patch 42 '{"priority":"p1"}' --client acme
# Poster / répondre
bash "$SCRIPT" tickets comments add 42 "Message" --client acme [--parent N] [--internal]
```

### Visibilité à la création (règles obligatoires)

Le défaut API/CLI staff est **`internal: true`**. Ticket **visible client** → **`--public`** (sinon pas de notif / pas visible client).

| Intention | Flag CLI | Notes |
| --- | --- | --- |
| Tech debt, ops, note staff, spawn agent, chantier interne | *(aucun)* ou `--internal` | **Défaut recommandé** |
| Bug / évolution **à montrer au client** | **`--public` obligatoire** | Sinon le client ne le voit pas + pas de notif client |

**Interdit** : créer un ticket « client » sans `--public` en espérant le défaut public ; patcher `internal` *après* create pour rattraper une notif déjà partie. Passer `--priority` au create. Après create, vérifier `internal` et `priority` renvoyés par l’API.

### GitHub (Task 1..n issues)

```bash
# Créer une issue GH depuis le ticket Spark (cuid ou ref + --client)
bash "$SCRIPT" tickets github-create <cuid>
bash "$SCRIPT" tickets github-create 42 --client acme
# Lier une issue existante (plusieurs tickets peuvent partager le même #)
bash "$SCRIPT" tickets github-link <cuid> "#42"
# Lister / délier
bash "$SCRIPT" tickets github-list 42 --client acme
bash "$SCRIPT" tickets github-unlink <cuid> 42
```

## Endpoints

| Méthode | Path | Scope |
| --- | --- | --- |
| GET | `/api/v1/tickets?meta=1` | read **ou** write |
| GET | `/api/v1/tickets?client=<slug>` | `tickets:read` (+ `.links` toujours) |
| GET | `/api/v1/tickets?client=&…&include=comments` | `tickets:read` — embed Discussion optionnel |
| GET | `/api/v1/tickets?client=&priority=&status=&type=&project=&onRoadmap=&internal=&assignee=&query=&limit=&offset=` | `tickets:read` — filtres list/search |
| POST | `/api/v1/tickets` | `tickets:write` (body optionnel `images: string[]`) |
| GET | `/api/v1/tickets/:id` | `tickets:read` — détail + `comments` + links |
| PATCH | `/api/v1/tickets/:id` | `tickets:write` |
| GET | `/api/v1/tickets/:id/comments` | `tickets:read` — Discussion |
| POST | `/api/v1/tickets/:id/comments` | `tickets:write` — `{ body, parentId?, internal? }` |
| POST | `/api/v1/tickets/upload` | `tickets:write` — FormData `file` + `clientSlug?` → `{ url }` |
| GET | `/uploads/<slug>/tickets/…` | cookie session **ou** Bearer PAT (`tickets:read\|write`) |
| POST | `/api/v1/tickets/:id/github-issue` | `tickets:write` → **créer** issue GH |
| GET | `/api/v1/tickets/:id/github-issues` | `tickets:read` → **lister** |
| POST | `/api/v1/tickets/:id/github-issues` | `tickets:write` → **lier** `{ reference }` |
| DELETE | `/api/v1/tickets/:id/github-issues?issueNumber=N` | `tickets:write` → **délier** |
| GET | `/api/v1/projects?meta=1` | read **ou** write |
| GET | `/api/v1/projects?client=` | `tickets:read` |
| GET | `/api/v1/projects/by-repo?owner=&repo=` | `tickets:read` ; match owner/repo **case-sensitive** ; **404** si dépôt inconnu ou `githubEnabled` false |
| POST | `/api/v1/projects` | `tickets:write` |
| PATCH | `/api/v1/projects/:id` | `tickets:write` |
| DELETE | `/api/v1/projects/:id` | `tickets:write` |
| GET | `/api/v1/task-links?meta=1` | read **ou** write |
| GET | `/api/v1/task-links?client=` | `tickets:read` |
| POST | `/api/v1/task-links` | `tickets:write` |
| DELETE | `/api/v1/task-links/:id?client=` | `tickets:write` |
| GET/POST | `/api/v1/tickets/:id/links` | nested |
| DELETE | `/api/v1/tickets/:id/links/:linkId` | nested |
| GET/POST | `/api/v1/resources` | section ressources |
| GET/PATCH/DELETE | `/api/v1/resources/:id` | get body markdown ; patch title/body/internal ; hard delete |
| GET | `/uploads/<slug>/resources/…` | cookie ou PAT |
| GET/POST | `/api/v1/journeys` | section flux |
| GET/PATCH/DELETE | `/api/v1/journeys/:id` | |
| GET/PUT | `/api/v1/orgchart` | section organigramme |
| GET/PATCH | `/api/v1/accueil` | section accueil |
| GET/POST | `/api/v1/tasks` | board Tâches ≠ tickets Pilotage |
| GET/PATCH/DELETE | `/api/v1/tasks/:id` | board CRUD |
| GET/POST | `/api/v1/tasks/:id/comments` | Discussion board |

API prod : https://spark.gosilex.com
