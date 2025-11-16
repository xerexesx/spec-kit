# Flux d'édition itératif des spécifications

## Problème à résoudre

De nombreux utilisateurs de Spec Kit souhaitent affiner une spécification existante après retour d'équipe, clarification métier ou découverte d'un bug. Aujourd'hui, `/speckit.specify` crée systématiquement un nouveau répertoire `specs/<numero>-<nom>/` et une branche associée. Cette approche marche pour un flux 0 → 1, mais elle devient lourde quand on veut simplement:

- mettre à jour une exigence existante dans la même branche;
- documenter une correction après `/speckit.implement` sans repartir de zéro;
- réconcilier des specs avec un produit brownfield qui évolue en continu.

Faute de mode "mise à jour", les équipes bricolent (`git cherry-pick`, copie de fichiers, ré-exécution de `/speckit.specify`), ce qui introduit des divergences entre artefacts et branches. Le problème est aggravé par la nomenclature automatique des branches (ex: `001-...`, `002-...`) qui peut se répéter ou ne pas respecter le contexte courant.

## Principes d'amélioration

1. **Favoriser les specs vivantes** – une spec doit pouvoir être modifiée autant de fois que nécessaire sans quitter son branchement d'origine.
2. **Séparer net-nouveau vs incrémental** – les flux de type "nouvelle fonctionnalité" doivent rester possibles, mais l'utilisateur doit pouvoir signaler qu'il affine un artefact existant.
3. **Réduire les opérations manuelles** – limiter les manipulations Git ou les copier-coller pour garder une experience fiable.
4. **Documenter les variantes (brownfield, bugfix, tiny spec)** – expliquer explicitement comment itérer dans des contextes différents.

## Fonctionnalités disponibles

### `/speckit.specify --update-current`

- Le script `create-new-feature.(sh|ps1)` accepte désormais `--update-current` et renvoie `MODE=update` dans son JSON. Aucun nouvel ID n'est généré: la commande réutilise le dossier `specs/<branch>/` déjà présent.
- Utilisez ce mode lorsque vous souhaitez réécrire intégralement `spec.md` (par exemple après une revue importante) tout en conservant la même branche. Les checklists générées sont réutilisées et les backups sont conservés dans le dossier `specs/<branch>/checklists/`.
- Si aucun dossier ne correspond à la branche courante, le script émet une erreur claire pour éviter toute perte de données.

### `/speckit.update`

- Nouvelle commande dédiée aux modifications incrémentales. Le script `update-feature.(sh|ps1)` détecte automatiquement `FEATURE_DIR`, créé des snapshots `.bak` et expose des options:
  - `--targets spec|plan|tasks|all` pour limiter les fichiers à éditer.
  - `--clarify-only` afin de collecter les questions sans toucher aux fichiers.
  - `--skip-checklists` pour différer la mise à jour des checklists.
  - `--no-backup` si vous travaillez déjà dans une branche jetable.
- Le JSON de sortie contient `TARGETS`, `FILES`, `BACKUPS`, `CLARIFY_ONLY`, `SKIP_CHECKLISTS` pour guider l'agent. Chaque run se termine par une recommandation explicite (`/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`) en fonction des artefacts touchés.
- En cas de fichier manquant (ex: `plan.md` non généré), la commande échoue immédiatement avec un message "run /speckit.plan first" pour éviter les divergences.

### `/speckit.tiny` et dossier `tiny-specs/`

- Pour les correctifs rapides, `/speckit.tiny` crée un fichier dans `specs/<branch>/tiny-specs/<slug>.md` basé sur `tiny-spec-template.md`.
- Le JSON indique `TINY_SPEC` et `SLUG` afin que l'agent puisse remplir le fichier et lier le mini-brief à `spec.md`/`plan.md`.
- Chaque tiny spec doit indiquer son impact et mentionner quand il faudra relancer `/speckit.update` pour propager la décision dans les artefacts principaux.

### Couverture brownfield & multi-agents

- Les scripts Bash/PowerShell sont installés dans `.specify/scripts/` et référencés automatiquement dans toutes les intégrations d'agents (Copilot, Claude, Cursor, etc.) via `templates/commands/*.md`.
- Grâce à `SPECIFY_FEATURE`, le flux fonctionne même sans dépôt Git (par exemple sur une branche "brownfield" importée). Les scripts recherchent toujours `specs/<prefix>-*` avant d'écrire.
- `tiny-specs/` reste dans le même dossier que les autres artefacts, ce qui simplifie l'archivage et la migration multi-branches.

### Nommage cohérent

- Les scripts continuent de générer des identifiants `00X-<slug>` pour les nouveaux features, mais lorsqu'on opère en mise à jour, c'est la structure existante qui fait foi. Les backups `.bak.<timestamp>` sont déposés à côté des fichiers ciblés pour faciliter les revues.

## Résultat

- Les utilisateurs disposent d'une commande officielle pour éditer une spec en place, sans création de branches inutiles.
- La documentation décrit clairement comment itérer et rester en phase avec la réalité produit, même dans des projets brownfield.
- Les workflows "tiny spec" et bugfix offrent une alternative légère pour les tâches incrémentales.
- Les noms de dossiers et branches restent cohérents, réduisant les erreurs lors des fusions et des automatisations.

Cette démarche permet de réduire la friction rapportée dans les issues (#1130, #620, #1136, #1118, #1173, #1066, #1165, #1151, #619, #1174) tout en conservant les avantages du flux net-nouveau existant.
