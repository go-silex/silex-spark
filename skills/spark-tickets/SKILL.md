---
name: spark-tickets
description: "API Spark PAT spu_ : Pilotage, Idées, tâches, discussion, ressources/journeys/org/accueil, projets, liens, GitHub et utilisateurs. Triggers: \"spark tickets\" | \"spark idées\" | \"spark tasks\" | \"spark users\" | \"gérer utilisateurs spark\" | \"spark resources\" | \"spark journeys\" | \"spark orgchart\" | \"spark accueil\" | \"list tickets spark\" | \"crée un ticket spark\" | \"commente le ticket\" | \"board tâches\" | \"spark projects\" | \"spark links\" | \"spark api\" | \"spark meta\"."
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
| Tickets actionnables (non bloqués) | `bash "$SCRIPT" tickets actionable [clientSlug] [--json] [--include-internal]` |
| Créer ticket | `bash "$SCRIPT" tickets create <clientSlug> "Titre" "Body?" [--priority p0\|p1\|p2\|p3] [--type bug\|feature] [--project id\|name] [--score n] [--internal\|--public]` |
| Patch ticket | `bash "$SCRIPT" tickets patch <id\|ref> '{"priority":"p1"}' [--client slug]` |
| Scorer / filtrer par Score | `bash "$SCRIPT" tickets patch <id\|ref> '{"score":8}' [--client slug]` · `tickets search <clientSlug> --unscored` |
| Non retenu (+ doublon + commentaire) | `bash "$SCRIPT" tickets reject <id\|ref> [--client slug] [--duplicate <ref>] [--comment "…"]` |
| Détail ticket (+ comments) | `bash "$SCRIPT" tickets get <id\|ref> [--client slug]` |
| Lister commentaires | `bash "$SCRIPT" tickets comments list <id\|ref> [--client slug]` |
| Poster / répondre | `bash "$SCRIPT" tickets comments add <id\|ref> "body" [--parent N] [--internal] [--client slug]` — `--parent` = premier niveau, même fil (pilotage) |
| Lister issues GH liées | `bash "$SCRIPT" tickets github-list <id\|ref> [--client slug]` |
| Créer issue GitHub | `bash "$SCRIPT" tickets github-create <id\|ref> [--client slug]` |
| Lier issue GitHub | `bash "$SCRIPT" tickets github-link <id\|ref> "#42" [--client slug]` |
| Délier issue GitHub | `bash "$SCRIPT" tickets github-unlink <id\|ref> 42 [--client slug]` |
| Lister ressources | `bash "$SCRIPT" resources list <clientSlug>` |
| Détail ressource (+ body markdown) | `bash "$SCRIPT" resources get <id> [client]` |
| Créer lien | `bash "$SCRIPT" resources create <client> <title> <url> [--category <type de document>] [--internal]` |
| Créer markdown | `bash "$SCRIPT" resources create-md <client> <title> [body] [--category <type de document>] [--public]` |
| Créer fichier (PDF/image/vidéo) | `bash "$SCRIPT" resources create-file <client> <path/to/file> [title] [--category <type de document>] [--internal]` |
| Patch ressource | `bash "$SCRIPT" resources patch <id> '{"category":"Livrables"}' [--client slug]` |
| Supprimer ressource | `bash "$SCRIPT" resources delete <id> [client]` |
| Journeys list/create/get/patch/delete | `bash "$SCRIPT" journeys …` |
| Organigramme get/put | `bash "$SCRIPT" orgchart get\|put …` |
| Accueil get/patch | `bash "$SCRIPT" accueil get\|patch …` |
| Board Tâches (≠ tickets) | `bash "$SCRIPT" tasks list\|create …` |
| Rejeter une tâche | `bash "$SCRIPT" tasks reject <cuid> [--reason\|--comment "…"] [--duplicate\|--duplicate-of-task-id <cuid\|ref>] [--patch '{"priority":"p2"}'] [--client slug]` |
| Rétrograder une tâche | `bash "$SCRIPT" tasks demote-preview <cuid> [--client slug]` puis `tasks demote <cuid> --apply [--client slug]` |
| Gérer une Idée | `bash "$SCRIPT" ideas list\|create\|get\|patch\|delete\|promote …` |
| Rétrograder un ticket | `bash "$SCRIPT" tickets demote-preview <id\|ref> [--client slug]` puis `tickets demote <id\|ref> --apply [--client slug]` |
| Supprimer ticket | `bash "$SCRIPT" tickets delete <id\|ref> [--client slug]` |
| Discussion générique | `bash "$SCRIPT" comments list\|add\|edit\|delete …` · `activity <client> <taskCuid>` |
| Utilisateurs (owner) | `bash "$SCRIPT" users list [--client slug] [--role role] [--query texte]` · `users create\|get\|patch\|delete\|reset-password …` |
| Tâche get/patch/delete | `bash "$SCRIPT" tasks patch <cuid> '{"priority":"p1"}' [--client slug]` (idem `get`/`delete`) |
| Comments board tâches | `bash "$SCRIPT" tasks comments list\|add <cuid> … [--client slug] [--parent N]` — `--parent` = premier niveau, même fil (taches) |
| Lister projets | `bash "$SCRIPT" projects list <clientSlug> [--kind development]` |
| Lookup projet par dépôt GitHub | `bash "$SCRIPT" projects by-repo <owner>/<repo>` |
| Créer projet | `bash "$SCRIPT" projects create <clientSlug> "Nom" [kind] [color]` |
| Patch projet | `bash "$SCRIPT" projects patch <id> '{"name":"…"}'` |
| Supprimer projet | `bash "$SCRIPT" projects delete <id> [clientSlug]` |
| Lister liens | `bash "$SCRIPT" links list <client> [--task <id\|ref>] [--kind parent\|blocks]` |
| Créer lien | `bash "$SCRIPT" links add <client> <task> <relation> <other>` |
| Supprimer lien | `bash "$SCRIPT" links delete <client> <linkId>` |

Les trois créations utilisent **Documentation** par défaut. Types canoniques : **Cadrage**, **Livrables**, **Comptes-rendus**, **Présentations**, **Documentation**, **Devis**, **Factures**, **Contrats & NDA** ; un type libre ou historique reste accepté.

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
| `--project <cuid\|name>` | `projectId` — CUID recommandé. Nom : règle de création (« Résolution d’identifiants », ci-dessous). Sans `--project`, le projet par défaut configuré (`SPARK_PROJECT` / spark.yml) est envoyé et suit la même règle (404 possible) ; sans défaut configuré, le serveur rattache le seul projet Pilotage visible s'il n'y en a qu'un. |
| `--score <n>` | Score saisi dès le create — `1\|2\|3\|5\|8\|13\|21` (jouable) ou `34\|55` (préscore) ; staff only |

```bash
# Tech debt / note staff / travail agent → défaut OK (interne)
bash "$SCRIPT" tickets create acme "Tech debt: …" "…"

# Bug ou évolution **visible client** → OBLIGATOIRE --public
bash "$SCRIPT" tickets create acme "Bouton budget cassé" "…" --public

# Priorité haute dès le create
bash "$SCRIPT" tickets create acme "Images cassées" "…" --public --priority p0 --type feature
```

### Idées et conversions

Une Idée est une Task sans projet, statut, Score ni échéance. Le create est visible par défaut (`internal: false`), sans notif Slack ; `--internal` est réservé au staff Silex.

```bash
bash "$SCRIPT" ideas list acme
bash "$SCRIPT" ideas create acme "Une idée"
bash "$SCRIPT" ideas get <cuid> --client acme
bash "$SCRIPT" ideas patch <cuid> '{"title":"…"}' --client acme
bash "$SCRIPT" ideas promote <cuid> --client acme
bash "$SCRIPT" ideas delete <cuid> --client acme
```

`ideas/:id` et `tasks/:id` attendent un **CUID**. Pour une rétrogradation, le preview **ne modifie rien** ; la mutation exige littéralement `--apply` :

```bash
bash "$SCRIPT" tasks demote-preview <cuid> --client acme
bash "$SCRIPT" tasks demote <cuid> --apply --client acme
bash "$SCRIPT" tickets demote-preview 42 --client acme
bash "$SCRIPT" tickets demote 42 --apply --client acme
```

### Discussion générique, activité et utilisateurs

```bash
bash "$SCRIPT" comments list acme pilotage --target-type task --target-id <cuid>
bash "$SCRIPT" comments add acme pilotage task <cuid> "Message" [--parent N] [--internal]
bash "$SCRIPT" comments add acme organigramme page "" "Réponse à la page" --parent N
bash "$SCRIPT" comments edit <id> "Texte corrigé"
bash "$SCRIPT" comments delete <id>
bash "$SCRIPT" activity acme <taskCuid>
```

Pour une page sans cible, conserver l’argument positionnel vide `""` : il devient `targetId: null` en JSON. L’identifiant non vide `"null"` reste une chaîne ; les cibles autres que `page` exigent un identifiant non vide.

Les commentaires génériques, l'historique et les Idées acceptent une **PAT personnelle `spu_…`**, jamais une clé M2M `spk_…`. `users` est plus strict : **owner Silex + PAT personnelle** uniquement (`tickets:read` list/get, `tickets:write` mutations) ; M2M et PAT non-owner sont refusées.

```bash
bash "$SCRIPT" users list --client acme --role client --query "collaborator"
bash "$SCRIPT" users create '{"email":"collaborator@example.com","name":"Collaborator","role":"client","clientSlug":"acme","sections":["pilotage"]}'
bash "$SCRIPT" users patch <id> '{"name":"Nouveau nom"}'
bash "$SCRIPT" users reset-password <id>
```

Create/reset renvoie le mot de passe généré une seule fois : le transmettre par un canal sûr, sans le mettre dans un exemple, un log ou un ticket. `--password` permet une valeur choisie si nécessaire.

### `tickets search` (filtres API)

```bash
bash "$SCRIPT" tickets search acme --priority p0 --status todo --limit 20
bash "$SCRIPT" tickets search acme --type feature --project App --query "github"
bash "$SCRIPT" tickets search acme --onRoadmap --priority p1,p2
bash "$SCRIPT" tickets search acme --unscored
bash "$SCRIPT" tickets search acme --score 34,55
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
| `--score <csv>` | `score=` | Entiers, match exact sur le Score effectif (`8`, `34,55`) ; **exclusif** avec `--unscored` |
| `--unscored` | `unscored=1` | Tickets **non scorés** (`score` vide) |
| `--scoreMode manual\|automatic` | `scoreMode=` | Parents : mode de score |
| `--limit N` | `limit=` | défaut **100** (list = sans plafond) |
| `--offset N` | `offset=` | défaut 0 |

Réponse : `{ tickets, total, limit, offset }` (+ `.links` par ticket).

### Score (échelle Fibonacci)

Le Score dit l'**ampleur**, `priority` l'urgence. C'est un champ de ticket comme les autres : `tickets patch` suffit, il n'existe **pas** de `spark.sh score`.

| Notion | Valeurs |
| --- | --- |
| Jouable | `1` `2` `3` `5` `8` `13` `21` |
| Préscore (à découper) | `34` `55` |
| Non scoré | champ **vide** — jamais `0` |

- Valeur hors échelle (`0`, `4`, demi-point) → **400**.
- **Lecture** ouverte à tout viewer du ticket (**client inclus**) ; **écriture** `score` / `scoreMode` **staff only** (client / M2M → 403).
- Parent (ticket avec enfants) : mode **`automatic`** → Score = **somme des enfants directs**. `PATCH score` y est refusé (**400**) → passer en manuel et poser le score dans le même PATCH : `{"scoreMode":"manual","score":13}`.
- `scoreMode` sur une **feuille** (sans enfant) → **400** : une feuille n'a pas de mode.
- Enfant non scoré : ignoré dans la somme, parent marqué **incomplet** (`scoreIncomplete`, `scoreUnscoredChildren`) — jamais 0.
- Somme gardée **brute** (16, 26 sont des résultats valides), jamais arrondie sur l'échelle.
- Surfacé sur les tickets d'un **projet de développement** (Pilotage) uniquement.

```bash
# Scorer une feuille
bash "$SCRIPT" tickets patch 42 '{"score":8}' --client acme
# Parent : passer en manuel et poser le score (un seul appel)
bash "$SCRIPT" tickets patch 77 '{"scoreMode":"manual","score":13}' --client acme
# Backlog à scorer · gros morceaux à découper
bash "$SCRIPT" tickets search acme --unscored
bash "$SCRIPT" tickets search acme --score 34,55
```

Champs DTO (list **et** get) : `score` (effectif) · `scoreManual` (saisi, conservé même en automatique) · `scoreMode` · `scoreSum` · `scoreIncomplete` · `scoreUnscoredChildren`.

### `tickets actionable` (filtre graphe)

Pas un filtre API : `tickets list` + classification locale.

Actionnable = ouvert (`new|todo|doing|staging`), pas duplicate, pas `blockedBy` un ticket **non-internal encore ouvert**, aucun ancêtre dans ce cas. Les internaux ne comptent pas comme bloqueurs et sont exclus du output (sauf `--include-internal`).

```bash
bash "$SCRIPT" tickets actionable acme
bash "$SCRIPT" tickets actionable acme --json
bash "$SCRIPT" tickets actionable --include-internal
```

Client comme `tickets list` (arg / `SPARK_CLIENT` / spark.yml). Pas de slug défaut hardcodé.

## Comportement agent

1. Parser l’intent (tickets / tasks / resources / journeys / org / accueil / projects / links / github / comments / meta).
2. Préférer le CLI (moins de contexte qu’un curl inventé). **Jamais** `get|post https://…` absolu (PAT).
3. Résumer en français : refs, surfaces, liens, issues GH, discussion, erreurs API.
4. Si 401 → `spark-setup`. Si 403 section → verrous Admin.
5. Un 403 = section verrouillée ou rôle insuffisant pour cette écriture.
6. Projets `development` = Pilotage ; défaut CLI create = `kind=development`.
7. GitHub : projet `githubEnabled` + repo ; `:id` = **cuid** ticket **ou** ref + `--client` (même règle que get/patch).
8. **Résolution d’identifiants** (unicité stricte) :
   - **CUID** → unique global, jamais ambigu. En création de ticket, il doit désigner un projet Pilotage ouvert et visible de l'espace, sinon **404**.
   - **Ref numérique** `#N` / `N` → unique par espace → **`--client <slug>`** si plusieurs espaces (sinon 400).
   - **Nom** (projet), **création de ticket** (`tickets create`) → nom exact (casse ignorée) de n'importe quel projet de l'espace : il doit être un projet Pilotage ouvert et visible, sinon **404** (pas de repli) ; sans nom exact, contenu dans le nom d'un seul projet Pilotage ouvert et visible. Plusieurs → **400** + `candidates` (projets Pilotage éligibles seulement) → passer le CUID. Aucun → **404**.
   - **Nom** (projet), **recherche** (`tickets search --project`) → projets ouverts de l'espace, tout type, exact puis contains. Plusieurs → **400** + `candidates`. Aucun → liste vide (200, pas d'erreur : vérifier le nom avant de conclure « aucun ticket »). **Ré-projet staff** : `tickets patch <id|ref> '{"projectId":"<cuid|nom>"}' [--client slug]` ; le projet cible peut être tout projet actif du même espace, exact puis contains (plusieurs → **400** + `candidates`, aucun → **404**). Les ré-projets successifs restent possibles tant que les droits sur la carte source courante le permettent ; après sortie de Pilotage, un staff limité à Pilotage peut recevoir **404**. Une cible non-Pilotage supprime `type` et `environment`, même fournis dans ce JSON ; une cible Pilotage les conserve. Depuis une cible non-Pilotage, fournir explicitement `type` (`bug` ou `feature`), et `environment` si `type` vaut `bug`. `{"projectId":null}` détache sans effacer ces signaux.
   - **`tasks get|patch|delete|comments`** → CUID seul (pas de ref), vérifié par le CLI (`c…`). L'espace d'un CUID ne se devine pas : le CLI n'utilise **jamais** le défaut `spark.yml` ici, seulement `--client` (ou le slug positionnel pour get/delete/comments list). Owner multi-espaces sans client → **400 « client requis »** : repasser avec `--client`. Compte mono-espace → son espace, flag inutile. L'exit code reste 0 sur une erreur API : lire le champ `error` du JSON.
9. Scopes `tickets:read|write` = **API v1 générique** (toutes surfaces), pas « tickets only ».

### Discussion (comments = fil Task)

Vocabulaire : **tickets** = Pilotage · **tasks** = board Tâches · **task-links** = relations · **comments** = Discussion (tickets *ou* tasks). Chaque commentaire expose `sectionKey` (filtrer avant `--parent`) et `editedAt` (null = jamais modifié ; sinon afficher « modifié »).

```bash
# Lire ticket + fil
bash "$SCRIPT" tickets get <cuid|ref> [--client slug]
# Patch (ref → --client si plusieurs espaces)
bash "$SCRIPT" tickets patch 42 '{"priority":"p1"}' --client acme
# Poster / répondre (--parent = premier niveau, même fil)
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
| GET | `/api/v1/tickets?client=&…&score=&unscored=&scoreMode=&priority=&status=&type=&project=&onRoadmap=&internal=&assignee=&query=&limit=&offset=` | `tickets:read` — filtres list/search (`score` + `unscored` ensemble → 400) |
| POST | `/api/v1/tickets` | `tickets:write` (body optionnel `images: string[]`) |
| GET | `/api/v1/tickets/:id` | `tickets:read` — détail + `comments` + links |
| PATCH | `/api/v1/tickets/:id` | `tickets:write` |
| GET | `/api/v1/tickets/:id/comments` | `tickets:read` — Discussion |
| POST | `/api/v1/tickets/:id/comments` | `tickets:write` — `{ body, parentId?, internal? }` ; `comments[]` portent `sectionKey` (filtrer avant `--parent`) ; `parentId` = commentaire de premier niveau **du fil pilotage** (sinon 400) |
| POST | `/api/v1/tickets/upload` | `tickets:write` — FormData `file` + `clientSlug?` → `{ url }` |
| GET | `/uploads/<slug>/tickets/…` | cookie session **ou** Bearer PAT (`tickets:read\|write`) |
| POST | `/api/v1/tickets/:id/github-issue` | `tickets:write` → **créer** issue GH |
| GET | `/api/v1/tickets/:id/github-issues` | `tickets:read` → **lister** |
| POST | `/api/v1/tickets/:id/github-issues` | `tickets:write` → **lier** `{ reference }` |
| DELETE | `/api/v1/tickets/:id/github-issues?issueNumber=N` | `tickets:write` → **délier** |
| DELETE | `/api/v1/tickets/:id?client=` | `tickets:write` — CUID ou ref ; PAT personnelle, pas M2M |
| GET/POST | `/api/v1/tickets/:id/demote?client=` | `tickets:read` preview sans écriture / `tickets:write` mutation — CUID ou ref |
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
| GET/PATCH/DELETE | `/api/v1/resources/:id` | get body markdown ; PATCH accepte notamment `{ "category": "Livrables" }` ; hard delete |
| GET | `/uploads/<slug>/resources/…` | cookie ou PAT |
| GET/POST | `/api/v1/journeys` | section flux |
| GET/PATCH/DELETE | `/api/v1/journeys/:id` | |
| GET/PUT | `/api/v1/orgchart` | section organigramme |
| GET/PATCH | `/api/v1/accueil` | section accueil |
| GET/POST | `/api/v1/tasks` | board Tâches ≠ tickets Pilotage |
| GET/PATCH/DELETE | `/api/v1/tasks/:id` | board CRUD |
| GET/POST | `/api/v1/tasks/:id/comments` | Discussion board — `comments[]` portent `sectionKey` ; `parentId` = premier niveau **du fil taches** |
| POST | `/api/v1/tasks/:id/reject?client=` | `tickets:write` — `{ reason?, duplicateOf?, patch? }`, task CUID, PAT personnelle |
| GET/POST | `/api/v1/tasks/:id/demote?client=` | preview sans écriture / mutation, task CUID, PAT personnelle |
| GET/POST | `/api/v1/ideas?client=` | list / create `{ clientSlug, title, internal? }`, PAT personnelle, pas M2M |
| GET/PATCH/DELETE | `/api/v1/ideas/:id?client=` | Idée CUID, PAT personnelle |
| POST | `/api/v1/ideas/:id/promote?client=` | `tickets:write`, Idée CUID, PAT personnelle |
| GET/POST | `/api/v1/comments` | Discussion générique ; GET `client,section,targetType?,targetId?`, POST `{clientSlug,sectionKey,targetType,targetId?,body,parentId?,internal?}` ; PAT personnelle |
| PATCH/DELETE | `/api/v1/comments/:id` | `tickets:write`, PAT personnelle |
| GET | `/api/v1/task-activity?client=&taskId=` | `tickets:read`, PAT personnelle |
| GET/POST | `/api/v1/users` | **owner Silex + PAT personnelle** ; `tickets:read` list, `tickets:write` create |
| GET/PATCH/DELETE | `/api/v1/users/:id` | **owner Silex + PAT personnelle** |
| POST | `/api/v1/users/:id/password` | **owner Silex + PAT personnelle** ; retourne le secret généré une seule fois |

API prod : https://spark.gosilex.com
