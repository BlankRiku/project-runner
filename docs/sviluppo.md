# Sviluppo

Note per chi compila Dev Runner, estende l’import o prepara un pacchetto. L’uso dell’app è nel [README](../README.md).

Serve macOS 13 e Swift 6.

```sh
swift test
swift run DevRunner
```

`swift run` mostra anche il Dock. Il bundle distribuito ha `LSUIElement` e resta solo nella barra dei menu.

I test che risolvono Tomcat e Java leggono tre percorsi da `.env` nella radice: `DEV_RUNNER_HOME`, `DEV_RUNNER_CATALINA_HOME` e `DEV_RUNNER_JAVA_HOME`. Copia `.env.example` in `.env` e inserisci le cartelle di questa macchina.

La configurazione dell’app sta in `~/.config/dev-runner/config.json`.

## Import

Lo scanner legge `.idea/runConfigurations`, `.idea/workspace.xml`, `.run/*.run.xml`, `.vscode/launch.json` e `.vscode/tasks.json` in ciascuna cartella del progetto (`roots`). I file di Visual Studio Code sono JSONC: commenti e virgole finali sono accettati. Le configurazioni finiscono nello stesso elenco dei runner di IntelliJ. Ogni run importata porta `sourceRoot`, così **Sincronizza** distingue configurazioni omonime in cartelle diverse. **Sincronizza** apre di nuovo l’elenco dello scan: le run già presenti partono selezionate, le nuove anche; deselezionare toglie la run (i runner manuali restano). Un `config.json` senza `roots` usa ancora solo `rootPath`.

| Origine | Comando |
| --- | --- |
| Tomcat | `catalina.sh run`, preceduto dal Before launch quando aggiorna l’artifact `war exploded` senza cancellare i jar già presenti in `WEB-INF/lib`. `CATALINA_HOME`, `JAVA_HOME` e `JRE_HOME` arrivano dalle impostazioni JetBrains |
| npm | `npm run <script>` |
| Python | interprete dello SDK e script o modulo indicati nella run |
| Flask (`Python.FlaskServer`) | `python -m flask run`, con `FLASK_APP` dal target. La porta è `FLASK_RUN_PORT`, altrimenti 5000 |
| Gunicorn | `python -m gunicorn` con i parametri della run Python |
| Maven | i goal della run. Il binario è quello impostato in IntelliJ: wrapper, Maven incluso nell’IDE o percorso custom |
| Spring Boot senza goal | `spring-boot:run` se nella radice c’è `pom.xml`, con la main class e il JDK di progetto |
| VS Code launch | comando ricostruito da `runtimeExecutable`, `program`, `module` o `args`. `request: attach` e una main class Java senza classpath restano senza comando, con una nota. La porta viene da `--port` o `--bind`, altrimenti da `PORT` o `FLASK_RUN_PORT` |
| VS Code compound | un runner che avvia in parallelo le launch referenziate. Ogni launch resta nella propria cartella, con le proprie variabili |
| VS Code task | `shell` e `process` usano `command` e `args`; `npm` usa `npm run <script>`. `dependsOn` entra nel comando. Una dipendenza con un’altra cartella viene eseguita lì. `gunicorn -c` legge il `bind` del file di configurazione |

L’interprete Python si risolve dal nome SDK in `jdk.table.xml`. Le variabili della run e il file indicato da `ENV_FILES` (o da `envFile` in VS Code) entrano nell’ambiente del runner. Per Tomcat, Make insieme alla build di un artifact `war exploded` compila, copia le dipendenze Maven in `WEB-INF/lib` e aggiorna le classi. I jar già presenti in quella cartella restano: `war:exploded` li cancellerebbe. Solo Make diventa `mvn -DskipTests -q compile`. Il JDK è il JRE alternativo della run, altrimenti quello di `.idea/misc.xml`. `JAVA_HOME` e `JRE_HOME` vengono riesportati dopo il profilo della shell, così non li sostituisce il Java della macchina. Gli altri Before launch di IntelliJ restano una nota. Un `preLaunchTask` di VS Code, se esiste in `tasks.json`, viene messo davanti al comando con `&&`. Si espandono solo `${workspaceFolder}`, `${workspaceRoot}`, `${workspaceFolderBasename}` e `${userHome}`.

Una configurazione non riconosciuta compare con il comando vuoto e una nota. Si può completare a mano: un comando modificato non viene sovrascritto da **Sincronizza**. In quel caso restano aggiornati nome, variabili e porta.

## Pacchetto

```sh
Scripts/package-app.sh
```

Lo script compila in release per Apple Silicon e Intel, unisce i due binari e crea `dist/DevRunner.app` e `dist/DevRunner.dmg`. Il DMG non è firmato. Contiene l’app e un collegamento ad Applicazioni. `dist/` non entra in git.

Va lanciato da un Mac Apple Silicon con Xcode, perché da lì produce entrambe le architetture. Il risultato richiede macOS 13, su Apple Silicon e su Intel.

Per una copia firmata da passare a mano, `Scripts/package-signed.sh` scrive in `dist-signed/`, cartella esclusa da git. Cerca nel portachiavi un’identità `Developer ID Application`.

## Icone

Sono due file distinti.

`Sources/DevRunner/Resources/MenuBarIcon.png` è il simbolo nella barra dei menu. Conta solo la trasparenza: i pixel opachi diventano la sagoma e il colore viene ignorato, così segue il tema chiaro o scuro. Lo sfondo deve essere trasparente.

`Sources/DevRunner/Resources/AppIcon.png` è l’icona a colori dell’app, quella del file in Finder e del Dock. Il pacchetto la converte in `AppIcon.icns`. L’app in esecuzione resta nella barra dei menu; l’icona a colori compare nel Dock quando apri una finestra, e sul file `DevRunner.app`.

Dopo una modifica a uno dei due PNG serve un nuovo `Scripts/package-app.sh`, oppure `swift run` durante lo sviluppo.
