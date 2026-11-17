# Repères – orientation post-bac

Application web réalisée pour un projet de Design Thinking sur l'orientation post-bac et Parcoursup.

- **Calendrier** des étapes Parcoursup 2027 (dates estimées d'après 2026) et échéances personnelles
- **Carte** des 14 214 formations Parcoursup 2025 : places, taux d'accès, profil des admis, liste de vœux simulée
- **Portes ouvertes** : 1 558 journées 2026-2027 dans 872 établissements, filtres par date, région, distance et liste de vœux, ajout à l'agenda et export .ics, questions à poser, notation des visites
- **Tutoriels** : projet de formation motivé, CV, dossier, liste de vœux, après les résultats
- **Documents** stockés uniquement dans le navigateur de l'utilisateur
- **Rendez-vous** avec des intervenants (créneaux d'exemple)
- **Discussion** (salons prévus, messagerie à relier à un serveur)

Données : ministère de l'Enseignement supérieur, « Parcoursup 2025 – vœux de poursuite d'études et de réorientation », licence ouverte. Contours des départements : france-geojson (IGN / OpenStreetMap).

Les données personnelles (échéances, vœux, documents) restent dans le navigateur de chaque visiteur.

### Portes ouvertes

`jpo.json` est généré par `scripts/build_jpo.py` à partir de l'Onisep (« Idéo-Structures d'enseignement supérieur et secondaire », licence ODbL), du ministère de l'Agriculture (« RefEA – Les journées portes ouvertes », licence ouverte) et de Parcoursup 2025 (lien formation → établissement). Seuls les établissements qui déclarent leurs dates à l'Onisep apparaissent.

Pour mettre les dates à jour (les établissements en ajoutent au fil de l'année), depuis la racine du dépôt :

```
python3 scripts/build_jpo.py
```

puis commiter `jpo.json`.

