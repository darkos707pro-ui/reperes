# Ouvrir l'Entraide (forum entre élèves)

L'onglet Entraide est en ligne mais **fermé** tant que le site n'est pas relié à un projet Supabase.
Compter 15 minutes, une seule fois.

## 1. Créer le projet (5 min)

1. Créer un compte sur <https://supabase.com> (gratuit), puis **New project**.
2. Nom : `reperes`. Mot de passe de base de données : en générer un et le garder dans un gestionnaire de mots de passe.
3. **Region : Europe (Paris, `eu-west-3`)**. Les données d'élèves restent ainsi dans l'Union européenne.

## 2. Régler l'authentification (3 min)

Dans **Authentication** :

1. **Sign In / Providers** → activer **Allow anonymous sign-ins**.
   Les élèves n'ont ni e-mail ni mot de passe à donner : leur appareil reçoit un identifiant anonyme, et le code du lycée débloque l'écriture.
2. **Rate Limits** → passer **anonymous sign-ins** de 30 à **300 par heure**.
   Une classe entière se connecte souvent depuis la même adresse IP (celle du lycée) : à 30, la 31ᵉ inscription de l'heure serait refusée.

## 3. Créer les tables et les règles (1 min)

**SQL Editor** → **New query** → coller tout le contenu de [`forum.sql`](forum.sql) → **Run**.
Le script peut être relancé sans perte de données (après une mise à jour, par exemple).

## 4. Créer les comptes modérateurs (3 min)

Pour toi et l'adulte référent :

1. **Authentication → Users → Add user → Create new user** : e-mail, mot de passe solide, cocher **Auto Confirm User**.
2. Dans **SQL Editor**, pour chaque modérateur :

```sql
insert into forum_moderators (user_id, label)
select id, 'Modération' from auth.users where email = 'adresse@exemple.fr';
```

## 5. Relier le site (2 min)

**Project Settings → API** : copier **Project URL** et la clé **publishable** (ou **anon public**).
Ces deux valeurs sont publiques par conception : la sécurité repose sur les règles du script, pas sur leur secret.
**Ne jamais copier la clé `secret` ni `service_role`.**

Les mettre dans `index.html`, ligne `const FORUM_CFG = ...` :

```js
const FORUM_CFG = ls.get("reperes-forum-cfg", null) || { url: "https://xxxx.supabase.co", key: "sb_publishable_xxx" };
```

(ou les envoyer pour que ce soit fait et testé à ta place).

## 6. Créer le premier code de lycée

Sur le site : onglet **Entraide** → **Espace modération** (en bas) → se connecter → **Créer un code**.
Distribuer le code en classe (oral, tableau, ENT), **jamais sur un réseau social public**.
Si un code circule hors du lycée : le désactiver et en créer un nouveau.

## Ce que fait la modération

| Protection | Comment |
|---|---|
| Pas de données personnelles | Pseudos ; e-mails, téléphones, réseaux sociaux et liens hors sites publics bloqués à l'envoi |
| Pas de contact privé | Aucun message privé ; « ajoute-moi sur Snap » est refusé |
| Insultes | Liste de mots refusés (basique : la vigilance humaine reste nécessaire) |
| Spam | 1 message toutes les 20 secondes, 30 par jour et par élève |
| Signalements | 3 signalements de personnes différentes masquent le message tout de suite ; un modérateur tranche ensuite |
| Comptes | Un modérateur peut bloquer un compte (ses messages sont masqués) et désactiver un code |

**Routine conseillée** : ouvrir l'Espace modération une fois par jour en période de vœux (janvier-avril) et de résultats (juin-juillet), une fois par semaine sinon.

## Limites à connaître

- **Projet gratuit mis en pause** : Supabase suspend un projet gratuit inactif depuis 7 jours (par exemple pendant les vacances). Il se relance d'un clic dans le tableau de bord ; pendant la pause, l'Entraide affiche « injoignable » et le reste du site fonctionne.
- **Un élève bloqué peut revenir** en effaçant les données de son navigateur, s'il a toujours le code : d'où l'intérêt de changer de code en cas d'abus répété.
- **Le filtre de mots ne remplace pas un humain** : il arrête les cas évidents, pas le harcèlement subtil.
- En cas de contenu illégal ou de danger pour un élève, prévenir le chef d'établissement ; pour un contenu illicite, la plateforme officielle est internet-signalement.gouv.fr (Pharos).
