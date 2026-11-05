# Twitter vidéo

Fork libre de [XFlow](https://github.com/Alchemist-Aloha/xflow) sous licence MIT, pour Android.

**Objectif :** navigation verticale façon TikTok, mais uniquement avec les vidéos de X/Twitter.

## Bêta 0.1.0
- Vidéos uniquement dans le fil, y compris pour les anciennes données en cache.
- Interface sombre, nom Android « Twitter vidéo », identifiant indépendant `fr.twittervideo.client`.
- Préparation des lecteurs limitée aux vidéos précédente, actuelle et suivante.
- Évite les mises à jour du pool vidéo pendant le rendu Flutter.
- Cache par défaut réduit à 250 Mo, chargement par lots plus petits.

## APK Android
Aller sur [Actions](https://github.com/Gitskrap/X-vid/actions/workflows/twitter-video-android.yml), sélectionner le dernier build réussi, puis télécharger **Twitter-video-Android-ARM64** ; décompresser le ZIP pour installer l'APK.

L'application utilise les accès non officiels à X hérités de XFlow, qui peuvent cesser de fonctionner. Bêta non encore testée sur téléphone. Le build release utilise pour l'instant la signature *debug* héritée de XFlow : une signature persistante sera nécessaire pour les futures mises à jour. Aucune affiliation avec X Corp.

## Licence
Code originel : MIT © 2026 Alchemist-Aloha. Ce fork conserve la licence du projet amont et ses avis.

## Version 0.3.0
- Lecture fiable des dates Twitter (format classique, ISO 8601 et epoch millisecondes).
- Date de secours extraite de l'identifiant Snowflake X, y compris pour les vidéos anciennes en cache.
- Affichage de la date complète et de l'heure sur chaque commentaire.
- Tests automatiques des conversions temporelles avant compilation.

## Version 0.4.0 — Google Cast (bêta)
- Bouton **Caster** sur chaque vidéo, remplaçant l'ancien bouton Partager qui n'était pas fonctionnel.
- Recherche des Chromecast / TV Google Cast et sélection du récepteur.
- Envoie uniquement l'URL HTTPS MP4 au récepteur standard Google Cast. **Pas de mirroring** du téléphone, aucun texte du tweet ni commentaire envoyé.
- Lecture du flux sur le téléviseur, et pause de la même vidéo sur le téléphone ; arrêt de diffusion depuis le sélecteur.
- Limitation importante : les URL X/Twitter protégées, temporaires ou nécessitant des cookies peuvent ne pas fonctionner sur le téléviseur. L'appareil Cast doit pouvoir accéder directement au CDN de X.
- Bibliothèque : flutter_chrome_cast 2.0.0 (BSD-3-Clause).

## Version 0.5.0
- Attend que la session Cast soit réellement connectée avant d'envoyer LOAD.
- N'affiche la réussite qu'après confirmation de la lecture (état PLAYING remonté par le téléviseur).
- Affiche les erreurs et délais d'attente dans le sélecteur Cast.
- Bouton fiole sur chaque appareil pour tester un MP4 public Google, isolant les erreurs du lecteur Cast de celles des vidéos X.

## Signature stable — à configurer une fois
Les anciennes versions utilisaient une clé Android de debug différente à chaque build. Pour ne plus devoir désinstaller aux prochaines mises à jour, les builds nécessitent désormais la même clé de signature permanente. Ne publiez jamais cette clé ou son mot de passe.

Dans le dépôt GitHub : Settings → Secrets and variables → Actions → New repository secret. Créer **ANDROID_KEYSTORE_BASE64** (valeur du fichier privé fourni) et **ANDROID_SIGNING_PASSWORD** (valeur du second fichier privé). Rejouer le workflow GitHub Actions après avoir configuré les deux secrets.

Le fichier de clé original (.p12) et son mot de passe doivent être conservés à part, en lieu sûr. Une fois le premier APK signé avec cette clé installé, les versions suivantes pourront être installées sans perte de données à condition de préserver le même identifiant Android (`fr.twittervideo.client`), la même signature et d'incrémenter le numéro de version. Une **dernière désinstallation** de la 0.4.0 peut être nécessaire : la clé de debug originale de ses builds n'est plus disponible.

## Version 0.6.0 — toucher pour passer en plein écran
- Un appui sur la zone de la vidéo ouvre le lecteur en plein écran, sans couper la lecture.
- Orientation paysage automatique pour les vidéos horizontales et portrait pour les autres.
- Les boutons d’interaction au-dessus de la vidéo restent cliquables et ne déclenchent pas le plein écran.
- Retour avec le bouton quitter le plein écran du lecteur ou la navigation Android ; les commandes de lecture restent accessibles dans le lecteur plein écran.
- Signature Android permanente identique à la version 0.5.0.
