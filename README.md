# Repères – orientation post-bac

Application web réalisée pour un projet de Design Thinking sur l'orientation post-bac et Parcoursup.

- **Calendrier** officiel Parcoursup 2027 et échéances personnelles
- **Ma voie** pour les élèves qui ne savent pas quoi faire : plan en quatre semaines, questionnaire d'intérêts relié aux formations de la carte, solutions (césure, service civique, alternance, réorientation)
- **Carte** des 14 214 formations Parcoursup 2025 : places, taux d'accès, profil des admis, liste de vœux simulée
- **Portes ouvertes** : 1 558 journées 2026-2027 dans 872 établissements, filtres par date, région, distance et liste de vœux, ajout à l'agenda et export .ics, questions à poser, notation des visites
- **Tutoriels** : projet de formation motivé, CV, dossier, liste de vœux, après les résultats
- **Documents** stockés uniquement dans le navigateur de l'utilisateur
- **Qui contacter** : professeurs principaux, psychologue de l'Éducation nationale, Crous, assistance Parcoursup, aide psychologique, et le CIO le plus proche (annuaire Onisep)
- **Entraide** : forum entre élèves par salons (pseudos, code par lycée, signalements, modération). Mise en service : voir [`supabase/README.md`](supabase/README.md)
- **Application installable** sur téléphone et ordinateur, utilisable hors connexion après la première visite

Données : ministère de l'Enseignement supérieur, « Parcoursup 2025 – vœux de poursuite d'études et de réorientation », licence ouverte. Contours des départements : france-geojson (IGN / OpenStreetMap).

Les données personnelles (échéances, vœux, documents) restent dans le navigateur de chaque visiteur.

### Données mises à jour automatiquement

Le workflow `.github/workflows/maj-donnees.yml` relance `scripts/build_jpo.py` le 1er de chaque mois et publie `jpo.json` (portes ouvertes) et `orientation.json` (CIO). Lancement manuel : onglet Actions › « Mise à jour des données » › Run workflow.

À refaire à la main chaque année : les dates de `PS_EVENTS` dans `index.html` quand Parcoursup publie son calendrier (en octobre), et `formations-2025.json` quand le ministère publie les données de la session suivante.

### Portes ouvertes

`jpo.json` est généré par `scripts/build_jpo.py` à partir de l'Onisep (« Idéo-Structures d'enseignement supérieur et secondaire », licence ODbL), du ministère de l'Agriculture (« RefEA – Les journées portes ouvertes », licence ouverte) et de Parcoursup 2025 (lien formation → établissement). Seuls les établissements qui déclarent leurs dates à l'Onisep apparaissent.

Pour mettre les dates à jour (les établissements en ajoutent au fil de l'année), depuis la racine du dépôt :

```
python3 scripts/build_jpo.py
```

puis commiter `jpo.json`.

