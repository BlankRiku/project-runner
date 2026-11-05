# Dev Runner

App per la barra dei menu di macOS che avvia, ferma e riavvia i progetti locali usando le run configuration di IntelliJ, PyCharm e Visual Studio Code.

La configurazione resta in `~/.config/dev-runner/config.json`.

## Configurazioni importate

Lo scanner legge `.idea/runConfigurations`, `.idea/workspace.xml`, `.run/*.run.xml`, `.vscode/launch.json` e `.vscode/tasks.json`. I file di Visual Studio Code sono JSONC: commenti e virgole finali sono accettati. Le configurazioni finiscono nello stesso elenco dei runner di IntelliJ.

| Origine | Comando |
| --- | --- |
| Tomcat | `catalina.sh run`, con `CATALINA_HOME` e `JAVA_HOME` risolti dalle impostazioni JetBrains |
| npm | `npm run <script>` |
| Python | interprete dello SDK e script o modulo indicati nella run |
| Flask (`Python.FlaskServer`) | `python -m flask run`, con `FLASK_APP` dal target. La porta è `FLASK_RUN_PORT`, altrimenti 5000 |
| Gunicorn | `python -m gunicorn` con i parametri della run Python |
| Maven | i goal della run. Il binario è quello impostato in IntelliJ: wrapper, Maven incluso nell’IDE o percorso custom |
| Spring Boot senza goal | `spring-boot:run` se nella radice c’è `pom.xml`, con la main class e il JDK di progetto |
| VS Code launch | comando ricostruito da `runtimeExecutable`, `program`, `module` o `args`. `request: attach` e una main class Java senza classpath restano senza comando, con una nota |
| VS Code compound | un runner che avvia in parallelo le launch referenziate |
| VS Code task | `shell` e `process` usano `command` e `args`; `npm` usa `npm run <script>`. `dependsOn` entra nel comando |

L’interprete Python si risolve dal nome SDK in `jdk.table.xml`. Le variabili della run e il file indicato da `ENV_FILES` (o da `envFile` in VS Code) entrano nell’ambiente del runner. I task prima dell’avvio di IntelliJ non vengono eseguiti. Un `preLaunchTask` di VS Code, se esiste in `tasks.json`, viene messo davanti al comando con `&&`. Si espandono solo `${workspaceFolder}`, `${workspaceRoot}`, `${workspaceFolderBasename}` e `${userHome}`.

Una configurazione non riconosciuta compare con il comando vuoto e una nota. Si può completare a mano: un comando modificato non viene sovrascritto da **Sincronizza**.

## Uso

L’icona sta nella barra dei menu, non nel Dock.

1. Aggiungi la cartella del progetto. Per un microservizio usa la sua cartella, non la root del repository: i file `.run` stanno lì.
2. Scegli le run da importare.
3. Avvia, ferma o riavvia il runner. I log si aprono dal pannello.
4. **Sincronizza** rilegge le run di IntelliJ e di Visual Studio Code. **Libera porta** chiude chi occupa la porta controllata dal runner.

## Sviluppo

Serve macOS 13 e Swift 6.

```sh
swift test
swift run DevRunner
```

`swift run` mostra anche il Dock. Il bundle distribuito ha `LSUIElement` e resta solo nella barra dei menu.

## App da installare

```sh
Scripts/package-app.sh
```

Lo script compila in release per Apple Silicon e Intel, unisce i due binari e crea `dist/DevRunner.app` e `dist/DevRunner.dmg`. Il DMG non è firmato. Contiene l’app e un collegamento ad Applicazioni: si trascina l’app lì. Su un altro Mac, dopo il download, apri **Impostazioni di Sistema → Privacy e sicurezza** e consenti l’apertura.

`dist/` non entra in git. Per una copia firmata da passare a mano, `Scripts/package-signed.sh` scrive in `dist-signed/`, cartella esclusa da git.

Serve macOS 13, sia su Apple Silicon sia su Intel. Lo script va lanciato da un Mac Apple Silicon con Xcode, perché da lì produce entrambe le architetture.

## Icone

Sono due file distinti.

`Sources/DevRunner/Resources/MenuBarIcon.png` è il simbolo nella barra dei menu. Conta solo la trasparenza: i pixel opachi diventano la sagoma e il colore viene ignorato, così segue il tema chiaro o scuro. Lo sfondo deve essere trasparente.

`Sources/DevRunner/Resources/AppIcon.png` è l’icona a colori dell’app, quella del file in Finder e del Dock. Il pacchetto la converte in `AppIcon.icns`. L’app in esecuzione resta nella barra dei menu; l’icona a colori compare nel Dock quando apri una finestra, e sul file `DevRunner.app`.

Dopo una modifica a uno dei due PNG serve un nuovo `Scripts/package-app.sh`, oppure `swift run` durante lo sviluppo.
