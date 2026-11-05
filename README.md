# Dev Runner

I servizi locali, dalla barra dei menu.

[Scarica per macOS](https://github.com/BlankRiku/project-runner/releases/latest) · macOS 13 o successivo · Apple Silicon e Intel

Dev Runner è un’app per macOS che avvia, ferma e riavvia i progetti su cui lavori, usando le run configuration già definite in IntelliJ, PyCharm e Visual Studio Code. L’icona sta nella barra dei menu: da lì vedi cosa è acceso e agisci senza riaprire l’IDE.

## A cosa serve

Su una macchina di sviluppo convivono spesso più servizi: un’applicazione Java, un frontend npm, un server Python. Le istruzioni per avviarli sono già scritte nelle configurazioni dell’IDE. Dev Runner le legge e le rende disponibili in un pannello unico, sempre a un clic.

## Cosa puoi fare

- Vedere quanti servizi sono attivi, anche sul numero accanto all’icona.
- Avviare, fermare e riavviare ogni runner, con lo stato in chiaro: fermo, in avvio, in esecuzione o in errore.
- Aprire i log, cercarli, copiarli e svuotarli.
- Sincronizzare le configurazioni quando le aggiorni nell’IDE.
- Liberare la porta di un servizio rimasta occupata.
- Attivare il debug Java e collegare il debugger dell’IDE.
- Aprire la cartella del progetto nel Finder o nel Terminale.
- Creare un runner a mano, quando non c’è una configurazione da importare.
- Modificare nome, comando, cartella di lavoro, porta e variabili d’ambiente.
- Fermare tutti i servizi insieme. Chiudendo l’app, i processi avviati vengono fermati.

## Cosa importa

Aggiungi una o più cartelle al progetto e scegli le run da tenere. Frontend e backend in repository distinti possono stare nello stesso blocco.

| Ambiente | Configurazioni |
| --- | --- |
| IntelliJ e PyCharm | Tomcat, script npm, Python, Flask, Gunicorn, Maven, Spring Boot |
| Visual Studio Code | Avvii, avvii composti, task npm, shell e process |

Le variabili d’ambiente della run vengono applicate all’avvio. Una configurazione non riconosciuta compare comunque nell’elenco: completi il comando a mano. Un comando che hai modificato resta tuo: **Sincronizza** non lo sovrascrive.

Per un microservizio indica la sua cartella, non la root del repository. È lì che stanno le configurazioni. Un progetto può avere più cartelle: **Sincronizza** le rilegge tutte.

## Come si usa

1. Clicca l’icona di Dev Runner nella barra dei menu.
2. Scegli **Aggiungi Progetto**, indica una o più cartelle e seleziona le run da importare. In alternativa crea un runner manuale. Su un progetto già presente, **Cartella** ne aggiunge un’altra.
3. Premi **Avvia**. Se la porta prevista è già occupata, l’avvio si ferma e te lo segnala.
4. Apri **Log** per l’output, **Riavvia** dopo una modifica, **Libera porta** se qualcosa è rimasto in ascolto.
5. Usa **Sincronizza** quando cambi le run nell’IDE: vedi di nuovo l’elenco e scegli cosa tenere o togliere.

Dal pannello puoi anche aprire la configurazione salvata sul Mac, terminare tutti i servizi e uscire.

## Installazione

Serve **macOS 13** o successivo. L’app gira su Apple Silicon e su Intel.

1. Scarica [`DevRunner.dmg`](https://github.com/BlankRiku/project-runner/releases/latest) dalla release.
2. Apri il disco e trascina **Dev Runner** in **Applicazioni**.
3. Il disco della release **non è firmato**. Al primo avvio, se macOS blocca l’app, apri **Impostazioni di Sistema → Privacy e sicurezza** e consenti l’apertura.

L’icona compare nella barra dei menu.

Per compilare da sorgente, su un Mac Apple Silicon con Xcode: `Scripts/package-app.sh`. Lo script prepara entrambe le architetture e crea `dist/DevRunner.dmg`. I dettagli sono in [docs/sviluppo.md](docs/sviluppo.md).

## Licenza

Dev Runner è libero per uso personale, studio e hobby, e per enti non commerciali. L’uso commerciale non è consentito. I termini sono in [LICENSE](LICENSE).

## Configurazione

Progetti e runner restano sul Mac. Dal pannello, **Apri config.json** apre il file in cui sono salvati.

## 🤝 Supporta il progetto

Se Dev Runner ti ha semplificato le sessioni di sviluppo, ti ha tenuto i servizi a portata di mano o ti ha fatto risparmiare tempo, puoi supportare chi lo sviluppa. Le donazioni aiutano a tenere vivo il progetto e a finanziare i prossimi aggiornamenti.

### 💖 Come supportare

Puoi inviare una donazione direttamente con PayPal:

<p align="center">
  <a href="https://www.paypal.me/BlankRiku" target="_blank">
    <img src="https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal" alt="Dona con PayPal" />
  </a>
</p>

---

Compilazione, import nel dettaglio e pacchetto sono in [docs/sviluppo.md](docs/sviluppo.md).
