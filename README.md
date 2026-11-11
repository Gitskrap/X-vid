# <img src="assets/app_icon.png" alt="Icône de Twitter vidéo" width="40" /> Twit Vid — Twitter vidéo

**Twit Vid** est un client Android open source, développé en **Flutter**, pour regarder les **vidéos publiques de X (Twitter)** dans un fil vertical, sans l'interface classique du réseau social.

> **Dépôt GitHub :** `Gitskrap/twit-vid`  
> **Nom sur le téléphone :** **Twitter vidéo**  
> **Dernière version publiée vérifiée :** [v0.25.0](https://github.com/Gitskrap/twit-vid/releases/tag/v0.25.0)  
> **Téléchargement Android :** [APK ARM64 signé](https://github.com/Gitskrap/twit-vid/releases/download/v0.25.0/Twitter-video-0.25.0-arm64.apk)

Ce projet est un **fork indépendant de [XFlow](https://github.com/Alchemist-Aloha/xflow)**. Il n'est ni développé ni approuvé par X Corp.

## Fonctionnalités

- **Fil « Vidéos » personnalisé** : recommandations issues des **J’aime enregistrés dans l’application**, des vidéos effectivement regardées, des comptes suivis localement et des hashtags favoris.
- **Vidéos de plus de 15 secondes uniquement** dans le fil principal ; les durées inconnues sont vérifiées par le lecteur lorsqu'il le peut.
- **J’aime et Je n’aime pas privés à l’application** : aucune action de like/dislike envoyée au compte X. Un 👎 masque la vidéo et réduit les propositions similaires.
- **Compteurs publics de X** : le nombre de J’aime affiché reste celui communiqué par X, et non celui des réactions locales.
- **Hashtags favoris et blacklist** : suivre un thème pour améliorer les recommandations, ou exclure les vidéos portant certains hashtags.
- **Abonnements locaux** : ajouter ou retirer des comptes publics dans l'application sans les suivre sur X ; l'accès aux vidéos dépend toutefois des sources disponibles.
- **Recherche de vidéos et de hashtags** : tentative par X, source publique de secours, puis résultats déjà présents dans le cache si le réseau ou les services échouent.
- **Lecteur vertical** : défilement fluide, barre de progression manipulable, son coupé au démarrage, mode paysage et plein écran conservé lors du changement de vidéo.
- **Google Cast (bêta)** : envoi de la vidéo au téléviseur via un relais Wi-Fi local, contrôle du volume et tentative de lecture automatique de la suivante.
- **Cache et historique locaux** : mémorisation des vidéos vues pour limiter les répétitions entre les sessions.

Les fonctionnalités dépendant de X ou d'un service public tiers peuvent être limitées, interrompues ou retourner des résultats incomplets. L'enchaînement Cast reste à valider selon les téléviseurs et les formats vidéo.

## Installer sur Android

1. Ouvrir la [page des versions](https://github.com/Gitskrap/twit-vid/releases/latest).
2. Télécharger le fichier **`Twitter-video-…-arm64.apk`** de la dernière version.
3. L'ouvrir sur un téléphone Android ARM64 et autoriser l'installation depuis cette source si Android le demande.
4. Pour les prochaines mises à jour, installer le nouvel APK **par-dessus l'application existante** : le paquet Android et la signature doivent rester identiques.

**Version actuelle :** [Twitter-video-0.25.0-arm64.apk](https://github.com/Gitskrap/twit-vid/releases/download/v0.25.0/Twitter-video-0.25.0-arm64.apk).

L'accès à un compte X est facultatif pour les fonctions locales, mais certaines vidéos ou certaines recherches peuvent nécessiter une session X valide.

## Développement

**Prérequis :** Flutter ≥ 3.44.0, Dart ≥ 3.12.0 et JDK 17 pour Android. La CI utilise Flutter 3.47.6.

```bash
git clone https://github.com/Gitskrap/twit-vid.git
cd twit-vid
flutter pub get
flutter analyze
flutter test
flutter run
```

Pour générer un APK Android local :

```bash
flutter build apk --release --target-platform android-arm64
```

La génération **release** demande les informations de signature privée configurées dans `android/key.properties`. Le dépôt ne contient ni la clé ni ses mots de passe. La [CI Android](.github/workflows/twitter-video-android.yml) utilise des secrets GitHub pour signer et publier les APK avec une clé stable.

**Important :** le nom interne du package Flutter reste `xflow` et le namespace Android historique reste en place pour préserver les imports et la compatibilité. Le nom public du dépôt et celui de l'application sont indépendants de ces identifiants techniques. Le paquet Android installé est `fr.twittervideo.client`.

## Organisation du code

| Chemin | Rôle |
| --- | --- |
| `lib/features/feed/` | Fil Vidéos, hashtags, réactions et recommandations |
| `lib/features/search/` | Recherche de vidéos |
| `lib/features/cast/` | Google Cast et relais local |
| `lib/features/player/` | Lecture vidéo, barre de progression et audio |
| `lib/features/subscriptions/` | Abonnements enregistrés sur le téléphone |
| `lib/core/` | Clients X/publics, modèles et base de données |
| `test/` | Tests automatiques |
| `TWITTER-VIDEO.md` | Historique technique des anciennes versions |

## Confidentialité et limites

Les J’aime, Je n’aime pas, abonnements et listes de hashtags sont conservés **localement** dans l'application. Les mots-clés utilisés pour récupérer les vidéos sont envoyés aux services de recherche sollicités ; ce n'est donc **pas** un mode de navigation totalement hors ligne. Le Cast peut transmettre le flux vidéo par le réseau local, sans dupliquer l'écran du téléphone.

Le projet utilise des interfaces **non officielles** de X et peut être affecté par leurs restrictions, des liens vidéo temporaires ou les limites de Google Cast.

## Licence et crédits

Projet distribué sous licence **MIT**, voir [LICENSE](LICENSE). Fork de [XFlow](https://github.com/Alchemist-Aloha/xflow) ; une partie de la couche de connexion et de données provient également de [Squawker](https://github.com/j-fb/squawker). Merci aux contributeurs des projets d'origine.

Les contributions et signalements de bugs sont bienvenus via les [issues GitHub](https://github.com/Gitskrap/twit-vid/issues).
