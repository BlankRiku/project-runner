# Dev Runner

I servizi locali, dalla barra dei menu.

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

Aggiungi la cartella del progetto e scegli le run da tenere.

| Ambiente | Configurazioni |
| --- | --- |
| IntelliJ e PyCharm | Tomcat, script npm, Python, Flask, Gunicorn, Maven, Spring Boot |
| Visual Studio Code | Avvii, avvii composti, task npm, shell e process |

Le variabili d’ambiente della run vengono applicate all’avvio. Una configurazione non riconosciuta compare comunque nell’elenco: completi il comando a mano. Un comando che hai modificato resta tuo: **Sincronizza** non lo sovrascrive.

Per un microservizio indica la sua cartella, non la root del repository. È lì che stanno le configurazioni.

## Come si usa

1. Clicca l’icona di Dev Runner nella barra dei menu.
2. Scegli **Aggiungi Progetto**, indica la cartella e seleziona le run da importare. In alternativa crea un runner manuale.
3. Premi **Avvia**. Se la porta prevista è già occupata, l’avvio si ferma e te lo segnala.
4. Apri **Log** per l’output, **Riavvia** dopo una modifica, **Libera porta** se qualcosa è rimasto in ascolto.
5. Usa **Sincronizza** quando cambi le run nell’IDE.

Dal pannello puoi anche aprire la configurazione salvata sul Mac, terminare tutti i servizi e uscire.

## Installazione

Serve **macOS 13** o successivo. L’app gira su Apple Silicon e su Intel.

Dalla cartella del progetto, su un Mac Apple Silicon con Xcode:

```sh
Scripts/package-app.sh
```

Lo script prepara entrambe le architetture e crea `dist/DevRunner.dmg`.

1. Apri il disco.
2. Trascina **Dev Runner** in **Applicazioni**.
3. Al primo avvio, se macOS blocca l’app perché il disco non è firmato, apri **Impostazioni di Sistema → Privacy e sicurezza** e consenti l’apertura.

L’icona compare nella barra dei menu.

## Licenza

Dev Runner è libero per uso personale, studio e hobby, e per enti non commerciali. L’uso commerciale non è consentito. I termini sono in [LICENSE](LICENSE).

## Configurazione

Progetti e runner restano sul Mac. Dal pannello, **Apri config.json** apre il file in cui sono salvati.

---

Compilazione, import nel dettaglio e pacchetto sono in [docs/sviluppo.md](docs/sviluppo.md).
