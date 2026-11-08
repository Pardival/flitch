<p align="center">
  <img src="art/preview/poses/wave.png" width="128" alt="Flitch, une loutre de rivière en pixel art avec un casque audio" style="image-rendering: pixelated">
</p>

<h1 align="center">Flitch</h1>

<p align="center">
  <b>Un assistant vocal pour macOS, incarné par une loutre en pixel art.</b><br>
  Maintiens une touche, pose ta question, elle te répond à voix haute.
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="docs/architecture.md">Architecture</a> ·
  <a href="https://github.com/Pardival/flitch/milestones">Feuille de route</a> ·
  <a href="CONTRIBUTING.md">Contribuer</a>
</p>

---

> **État : en cours de développement.** Rien à installer pour l'instant. Les [jalons](https://github.com/Pardival/flitch/milestones) montrent l'avancement vers la v0.1.

## Flitch, c'est quoi ?

La plupart des assistants IA sont une fenêtre de chat. Flitch est un **petit personnage qui vit sur ton écran** :

1. **Maintiens ⌥ droite.** La loutre apparaît dans un coin de l'écran : tête en bas dans un coin du haut, ou en surgissant du bord dans un coin du bas.
2. **Parle.** Elle t'écoute avec son casque. Ta voix est transcrite sur ton Mac.
3. **Relâche.** Elle réfléchit en cassant un coquillage avec son galet, puis **te répond à voix haute** avec une bulle.
4. Elle reste **15 secondes**, puis s'en va. Clique sur la bulle pour garder la réponse complète.

Demande-lui par exemple « Parle-moi de Napoléon » ou « Quelle est l'actualité aujourd'hui ? ».

<p align="center">
  <img src="art/preview/otter_concept.png" width="720" alt="Planche de la loutre : repos, écoute, réflexion, parole, joie, coucou, sommeil, apparition">
</p>

## Ce qui est prévu pour la v0.1

- **Ton IA, en un clic** :
  - *Continuer avec ChatGPT*, qui utilise ton abonnement Plus ou Pro ;
  - *Se connecter avec OpenRouter*, un seul compte pour Claude, Gemini, Grok, Mistral, DeepSeek, Qwen, Kimi… ;
  - des clés API ;
  - un **modèle local** (Ollama, LM Studio).
- **Des voix à tester avant de choisir** :
  - un *langage animal* gratuit ;
  - les voix Apple ;
  - des voix premium : ElevenLabs, OpenAI, Cartesia, Mistral, Gemini.
- **Recherche web** grâce à la recherche intégrée de ton fournisseur.
- **Une mémoire que tu contrôles** :
  - une fiche « À propos de moi » ;
  - ce qu'elle apprend en discutant, avec ton accord à chaque fois.

  Tout reste sur ton Mac.
- **Personnalités** : enthousiaste, calme, professionnel, blagueur, taquin.
- **Deux modes** : le **mode discret**, dans un coin de l'écran, ou le **mode Dock**, où elle se balade, danse et fait la sieste sur ton Dock.
- Anglais, français, espagnol.

## Confidentialité

- **Aucun serveur Flitch** : ton Mac parle directement au fournisseur que tu as choisi.
- Les clés et jetons sont rangés dans le **Trousseau de macOS**.
- Ta voix est transcrite sur l'appareil par défaut et **n'est jamais enregistrée**.
- L'historique et la mémoire sont un fichier local, que tu peux effacer quand tu veux.
- **Aucune télémétrie.**

## Prérequis

- macOS 26 ou plus récent

## Licence

- Code : [MIT](LICENSE)
- Dessins (sprites, personnages) : [CC BY 4.0](LICENSE-ART.md)
