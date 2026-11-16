# ROADMAP — Accès Wifirst automatique

Référence : `DOCUMENT_MAITRE.md` v1.0 (2026-11-16).
Règle : une case ne se coche qu'avec une preuve dans `VALIDATION_LOG.md`. Aucune tâche n'est lancée
sans le feu vert du maître, car les essais réseau coupent sa connexion.

## Phase 0 — Cadrage (terminée)

- [x] Rassembler l'historique (2 exports, 6 300 lignes) et l'état machine.
- [x] Écrire `DOCUMENT_MAITRE.md`, `ROADMAP.md`, `VALIDATION_LOG.md`.
- [x] Archiver les preuves du portail dans `evidence/`.
- [x] Rédiger le rapport de diagnostic complet.
- [ ] Valider le document maître par le maître du projet.

## Phase 1 — Trancher la faisabilité MAC (bloquante)

- [ ] T-1 : commande unique d'écriture d'une MAC `02:…` (12 caractères), redémarrage carte, contrôle.
- [ ] Consigner le résultat (MAC cible vs MAC constatée).
- [ ] Décision : si échec, ouvrir la voie « partage de connexion » (phase 1 bis) et geler la phase 2.
- [ ] Nettoyage : supprimer `NetworkAddress` pour revenir à la MAC d'origine.

## Phase 1 bis — Partage de connexion (si T-1 échoue)

- [ ] Choisir le support : téléphone en MAC privée + partage, ou routeur dédié.
- [ ] Documenter le pas-à-pas et les limites (une seule identité vue par Wifirst).
- [ ] Adapter la stratégie de renouvellement (le script vise alors l'appareil partageur).

## Phase 2 — Valider l'API de création de compte

- [ ] T-2 : `GET /` + `index.txt` + `GET /api/settings` sur bocal neuf, vérifier `box_token` et le
      fragment `freezone`.
- [ ] `POST /api/guest_users` avec le `guest_user` complet exigé par le descripteur.
- [ ] Contrôler l'absence de 400 et lire le corps complet (succès ou refus de quota).
- [ ] Mesurer le code et le message exact d'un refus de quota, pour le traitement automatisé.

## Phase 3 — Écrire le script v3

- [ ] `Wifirst-Farm.ps1` : générateur 12 caractères/`02`, écriture registre, vérification, restauration.
- [ ] Attente de réassociation + IPv4 valide + portail joignable.
- [ ] Chaîne portail : bocal neuf, token, settings, fragment dynamique, `guest_user` complet.
- [ ] Connexion 443, contrôle `generate_204`, journalisation intégrale.
- [ ] Chien de garde `api/connect` + secours `PAY/<epoch_ms>`.
- [ ] `Ctrl+C` = sortie propre + MAC d'origine restaurée.

## Phase 4 — Exécuter et valider

- [ ] T-3 : un cycle complet, consigné.
- [ ] T-4 : deux cycles, vérifier le renouvellement.
- [ ] Vérifier la stabilité sur une journée de travail réelle.

## Phase 5 — Finition

- [ ] Lanceur `.bat` en administrateur (déjà cadré dans l'historique).
- [ ] Rapport final + mise à jour du document maître (3 états renseignés).
- [ ] Consigner les limites constatées (nombre de comptes par MAC, durée réelle du crédit).

## Sujets ouverts

- Durée exacte du crédit freezone et règle de quota réellement appliquée (par MAC, IP, e-mail, hotspot).
- Comportement du SSID après changement de MAC si le pilote refuse la valeur : reconnexion auto ou non.
- Compte réel à utiliser pour recevoir d'éventuels e-mails (aucune confirmation par e-mail dans le flux
  actuel, donc jetables acceptés).
