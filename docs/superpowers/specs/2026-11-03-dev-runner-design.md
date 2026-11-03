# Dev Runner — specifica di design

Data: 2026-11-03. App nativa macOS per avviare i server di sviluppo locali dalla menu bar, senza aprire IntelliJ. Il design è approvato: questo documento lo fissa in modo implementabile, senza alternative aperte.

## 1. Prodotto e vincoli

Dev Runner è un'app menu bar (`MenuBarExtra`). Il bundle prodotto da `Scripts/package-app.sh` ha `LSUIElement = true` e quindi non mostra icona nel Dock. `swift run` può mostrare il Dock: è accettato, perché `LSUIElement` vive solo nel plist del bundle.

Vincoli:

- macOS 13 o successivo. Swift Package Manager. Nessun package di terze parti. Solo Foundation, SwiftUI, AppKit e Darwin.
- `swift build` e `swift test` devono passare.
- Testi dell'interfaccia in italiano. Tema scuro.
- Obiettivo di memoria a riposo sotto i 25 MB: è un obiettivo di prodotto, non un test di CI. Non aggiungere cache, framework o store ridondanti.
- I test non devono inviare segnali a processi dell'utente. Il controllo porta nei test usa un doppio che non chiama `kill` sul sistema.

## 2. Architettura

Due strati.

### 2.1 Supervisore

Il supervisore non conosce Spring, npm o Tomcat. Conosce progetti e runner. Un runner è un comando, una cartella di lavoro, un ambiente, una porta opzionale e un flag di debug.

Ogni avvio reale usa `posix_spawn` (Darwin), mai `Foundation.Process`, e mai `setpgid` dopo la creazione del processo.

- Eseguibile: `/bin/zsh`.
- Argomenti di produzione: `-l`, `-c`, `<comando>`. La shell di login tiene Homebrew, SDKMAN, nvm, jenv e ServBay sul `PATH`.
- Flag `POSIX_SPAWN_SETPGROUP` e `posix_spawnattr_setpgroup(..., 0)` prima dell'exec, così il pgid del figlio è il suo pid.
- La cartella di lavoro è impostata con una file action di spawn (`posix_spawn_file_actions_addchdir` su macOS 26+, `posix_spawn_file_actions_addchdir_np` sulle versioni precedenti fino a macOS 13).
- stdout e stderr del figlio sono lo stesso pipe, letto dal genitore.
- Arresto: `kill(-pgid, SIGTERM)`. Se dopo il periodo di grazia qualche processo del gruppo è ancora vivo (`kill(-pgid, 0) == 0`), `kill(-pgid, SIGKILL)`.
- Grazia di produzione: 4 secondi. Il valore è iniettabile (`terminationGrace`) così i test usano frazioni di secondo. I test di gruppo non usano `-l`: passano `-f -c` allo stesso spawner, per non eseguire il profilo dell'utente.
- Alla chiusura dell'app (`applicationWillTerminate`) ogni runner attivo riceve la stessa sequenza, in modo sincrono, così il processo non esce lasciando il gruppo vivo. Il bottone «Termina Tutti» invia la stessa sequenza senza bloccare il popover: lo stato torna fermo quando il processo esce.
- Un'uscita provocata da Stop o da Termina Tutti è stato fermo (grigio), anche se il codice di uscita è quello di un segnale. Un'uscita diversa da zero non richiesta è crash (rosso).

I log arrivano dal pipe, spezzati in righe, dentro un ring buffer da 1000 righe per runner. La vista si aggiorna sul main actor al massimo ogni 200 ms circa. Il buffer stesso si aggiorna subito: il throttle riguarda solo la pubblicazione verso SwiftUI.

### 2.2 Adattatori IntelliJ

Funzioni pure: XML in ingresso, `RunnerConfig` in uscita. Si leggono:

- `.idea/runConfigurations/*.xml`
- le `configuration` figlie dirette di `<component name="RunManager">` in `.idea/workspace.xml`

Parser: `XMLDocument` e XPath. Non si usa `//configuration` da solo, perché `workspace.xml` contiene altri nodi `configuration` (per esempio i watch del debugger) che non sono runner.

Ordine di lettura: i file in `.idea/runConfigurations/` in ordine lessicografico del nome, poi `workspace.xml` nell'ordine del documento. Se la stessa coppia nome+tipo compare due volte, vince la prima.

`$PROJECT_DIR$` e `$USER_HOME$` sono sostituiti ovunque compaiano in comandi, cartelle, env e percorsi (radice del progetto e home passata allo scan).

Il primo adattatore che riconosce il `type` vince. Ordine: tomcat, npm, python, maven, altrimenti `unmapped`.

Un file XML illeggibile viene saltato (`skippedFiles` riceve il nome del file). Gli altri file si importano comunque. Una cartella `.idea` assente produce zero runner e zero file saltati.

`vmOptions` e `programArguments` non sono campi del modello. Se l'XML ha `VM_PARAMETERS` non vuoto, il testo entra nell'env (`CATALINA_OPTS` per Tomcat, `JAVA_TOOL_OPTIONS` per Maven). Se ha `PROGRAM_PARAMETERS` non vuoto, il testo è appeso al comando. Si preferisce il `ConfigurationWrapper` con `RunnerId="Run"`; se lì è vuoto, si usa il primo valore non vuoto.

## 3. Modello dati

`Project`

- `id: UUID`
- `name: String`
- `rootPath: String`
- `runners: [RunnerConfig]`

`RunnerConfig`

- `id: UUID`
- `name: String`
- `command: String`
- `workingDirectory: String`
- `env: [String: String]`
- `debugEnabled: Bool` (default `false`)
- `debugPort: Int` (default `5005` se assente in JSON e in XML)
- `portToCheck: Int?`
- `commandEdited: Bool` (default `false`)
- `idea: IdeaOrigin?`
- `debugInjection: DebugInjection` (default `none`)
- `importNote: String?` — motivo in italiano quando il comando è vuoto o incompleto. È il campo mostrato in UI insieme a «Comando da completare».
- `tomcatContextPath: String?`
- `tomcatDocBase: String?`

Gli ultimi tre campi servono a preparare Tomcat e a spiegare un import incompleto. Non sostituiscono il comando.

`IdeaOrigin`

- `configurationName: String`
- `configurationType: String`
- `adapter: tomcat | npm | python | maven | unmapped`

`DebugInjection`

- `none`
- `javaToolOptions`
- `catalinaOpts`

Lo stato di esecuzione non è persistito.

`RunnerPhase`: `stopped`, `starting`, `running`, `crashed`.

`RunnerRuntime`: `phase`, `pid: Int32?`. Il pid è valorizzato solo in `starting` e `running`.

JSON in `~/.config/dev-runner/config.json`:

```json
{
  "projects": []
}
```

Chiavi in camelCase, UUID come stringhe, env come oggetto. `debugPort` mancante in lettura vale 5005. Bool mancanti valgono `false`. `debugInjection` mancante vale `none`.

## 4. Persistenza

`ConfigStore` riceve l'URL del file. Il default è `~/.config/dev-runner/config.json`.

- La cartella si crea al salvataggio se manca.
- Scrittura atomica: file temporaneo nella stessa cartella, poi `replaceItemAt` / move. Niente troncamento sul file finale.
- File assente: memoria vuota, file non ancora creato. Non è un file corrotto.
- File non decodificabile: memoria vuota, flag di corruzione, e `save` non scrive. Il contenuto su disco resta identico anche se qualcuno chiama `save`.
- «Apri config.json»: se il file manca, si scrivono esattamente i byte `{"projects":[]}`. Se il file c'è, anche corrotto, si apre così com'è, senza riscriverlo. Apertura con `NSWorkspace.shared.open`.

Lo stato di run, i log e i pid non finiscono nel JSON. Ogni modifica a progetti o runner (aggiunta, import, modifica, toggle debug, resync) salva. Un cambiamento di solo stato di processo non salva.

## 5. Adattatori

### 5.1 npm

Riconosce `type` che contiene `js.build_tools.npm`, oppure `factoryName` uguale a `npm` ignorando il maiuscolo.

- `command` dell'XML uguale a `run` e uno `<script value="...">`: comando `npm run <script>`.
- Altrimenti, se c'è un command XML: `npm <command>`.
- Script con spazi o caratteri di shell: quotato con apici singoli.
- Cartella di lavoro: cartella del `package-json` se presente, altrimenti la radice del progetto.
- Env dagli elementi `envs/env`.
- `debugInjection = none`. `importNote` vuota. `commandEdited = false`.

### 5.2 python

Riconosce `type` che contiene `Python`.

- Se esiste un'opzione comando di shell non vuota (`SCRIPT_TEXT` o `COMMAND`), quella è il comando, dopo l'espansione delle macro.
- Altrimenti interprete + script. Interprete: `SDK_HOME` se non è vuoto, altrimenti `python3`.
- `MODULE_MODE` vero: `<interprete> -m <script>`.
- Altrimenti: `<interprete> <script>`.
- `PARAMETERS` non vuoto è appeso.
- Percorsi quotati se necessario.
- Cartella: `WORKING_DIRECTORY` o radice del progetto.
- `debugInjection = none`.

### 5.3 maven / java

Riconosce `type` che contiene `Maven`, oppure un tipo Spring (`SpringBoot`) che ha almeno un goal Maven.

- Goal letti da `option[@name='goals']/list/option/@value` e da `goals/option/@value`.
- Se esiste il file `mvnw` nella radice del progetto, il comando è `./mvnw <goal...>`. Altrimenti `mvn <goal...>`.
- Un goal `spring-boot:run` è un goal come gli altri: non si ricostruisce il classpath di IntelliJ.
- `debugInjection = javaToolOptions`.
- `VM_PARAMETERS` vanno in `JAVA_TOOL_OPTIONS`.

Un tipo `Application`, o uno Spring Boot, che ha solo una main class e nessun goal, non è Maven. Diventa `unmapped` con comando vuoto e nota:

- Application: `Application con sola main class: il classpath di IntelliJ non è un comando di shell.`
- Spring senza goal: `Application Spring senza goal Maven portatile.`

Un tipo Maven senza goal è `unmapped` con nota `Tipo di configurazione non mappato.`

### 5.4 tomcat

Riconosce `type` che contiene `Tomcat`.

Il processo è Catalina, non il deployer di IntelliJ («Artifact ... Waiting for server connection» non si replica).

Comando salvato e visibile, quando home e JRE richiesti si risolvono:

```text
exec "$CATALINA_HOME"/bin/catalina.sh run
```

Senza `PROGRAM_PARAMETERS` la stringa termina con `bin/catalina.sh run`. Se `PROGRAM_PARAMETERS` non è vuoto, quel testo si appende dopo `run`.

Env salvato:

- `CATALINA_HOME`: percorso risolto.
- `CATALINA_BASE`: `<configRoot>/catalina/<runner-id>`. In produzione `configRoot` è `~/.config/dev-runner`. Lo scan non crea la cartella: la crea la preparazione, subito prima dello spawn.
- `JAVA_HOME`: se l'XML chiede un JRE alternativo.
- più gli env espliciti dell'XML e `CATALINA_OPTS` se ci sono `VM_PARAMETERS`.

`debugInjection = catalinaOpts`. `portToCheck` è la porta HTTP: opzione `HTTP_PORT` se è un intero, altrimenti 8080. `debugPort` è `RunnerSettings/option[@name='DEBUG_PORT']` se è un intero, altrimenti 5005.

Contesto e artifact:

- Nome artifact: primo `deployment/artifact/@name`. Esempio CePosto: `ceposto-java-server:war exploded`.
- Context path: opzione `CONTEXT_PATH`, default `/`.
- `tomcatContextPath` conserva il path originale (`/CePosto`).
- docBase: `output-path` dell'artifact con lo stesso nome in `.idea/artifacts/*.xml`, macro espanse. Se manca, `<radice>/target/<artifactId>`, dove `artifactId` è il testo prima dei due punti. Senza due punti si usa il nome intero, troncato agli spazi. Per CePosto senza artifact XML il docBase è `<radice>/target/ceposto-java-server`.

Risoluzione di `CATALINA_HOME`, per nome `APPLICATION_SERVER_NAME`:

1. Nei file passati allo scan, nell'ordine.
2. In `applicationServers.xml`: dentro `ServerSettingsImpl`, l'option `NAME` deve essere uguale al nome server; si legge l'option `HOME`.
3. In `javaeeAppServers.xml` (formato JetBrains attuale, stesso significato): elemento `ServerDK` con attributo `NAME`, option `CATALINA_HOME` sotto `DATA`.
4. Si espandono `$USER_HOME$` e `$PROJECT_DIR$`. Il primo valore non vuoto vince.

Non esiste un percorso di Tomcat cablato nel codice. Il fixture di test mette in `applicationServers.xml` la home `/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41` e il test verifica comando e `CATALINA_HOME`. In produzione, se i file non sono passati (`nil`), si cercano sotto `~/Library/Application Support/JetBrains/*/options/` i file `applicationServers.xml`, `javaeeAppServers.xml` e `jdk.table.xml`, ordinati per data di modifica decrescente. Un array vuoto significa «non usare nessun file», ed è ciò che usano i test del caso «server assente».

Risoluzione JRE:

- `ALTERNATIVE_JRE_ENABLED` diverso da `true`: nessun `JAVA_HOME` obbligatorio.
- `ALTERNATIVE_JRE_PATH` che contiene `/` oppure inizia con `$`: è un percorso, si espandono le macro, non si consulta `jdk.table.xml`.
- Altrimenti è un nome (`corretto-1.8`). In `jdk.table.xml` si cerca `jdk/name/@value` e si legge `homePath/@value`, poi si espandono le macro.

Se `CATALINA_HOME` non si risolve, o se un JRE è richiesto e non si risolve, il comando salvato è vuoto. Note, anche entrambe:

- `Server Tomcat non trovato in applicationServers.xml.`
- `JRE «<nome>» non trovato in jdk.table.xml.`

`importNote` è la concatenazione con uno spazio. L'esistenza della cartella sul disco non è richiesta in import: interessa il percorso letto dall'XML. Il controllo sul disco avviene in preparazione, all'avvio.

### 5.5 unmapped

Qualsiasi altro tipo. Comando vuoto, `debugInjection = none`, cartella di lavoro da `WORKING_DIRECTORY` o radice, env se presenti, nota `Tipo di configurazione non mappato.` salvo le note più specifiche del punto 5.3.

## 6. Resync

Il controllo UI si chiama «Sincronizza da .idea» ed è sul blocco del progetto. Rilancia lo scan sulla `rootPath` del progetto e applica `IdeaImporter.resync`.

Chiave: `idea.configurationName` + `idea.configurationType`. I runner senza `idea` restano dov'erano.

Per ogni runner esistente con origine, se l'import ha la stessa chiave:

- `commandEdited == true`: si aggiornano solo `name`, `env` e `portToCheck`. `command` non cambia. Restano invariati anche `id`, `commandEdited`, `workingDirectory`, `debugEnabled`, `debugPort`, `debugInjection`, `idea`, `importNote`, `tomcatContextPath`, `tomcatDocBase`.
- `commandEdited == false`: il runner importato sostituisce i campi importati, ma si conservano `id`, `debugEnabled` e `commandEdited` (`false`).

In entrambi i casi, se l'env risultante contiene `CATALINA_BASE`, quel valore è ricalcolato come `<configRoot>/catalina/<id del runner esistente>`, così la base non cambia a ogni sync.

I runner di IDEA non più presenti nel file restano nel progetto. I runner importati senza corrispondenza si accodano nell'ordine di scan.

## 7. Preparazione Tomcat e comando eseguito

Subito prima dello spawn, e solo se `idea.adapter == tomcat`, Swift prepara `CATALINA_BASE`. Non è una stringa nascosta nello shell oltre al prefisso Maven descritto sotto.

Passi:

1. `CATALINA_HOME` vuoto: errore `CATALINA_HOME non trovato.`
2. `JAVA_HOME` presente e non vuoto ma non è una cartella: errore `JRE non trovato sul disco.`
3. `tomcatDocBase` vuoto: errore `Percorso artifact mancante.`
4. `CATALINA_BASE` vuoto: errore `CATALINA_BASE mancante.`
5. Si creano, se mancano, `CATALINA_BASE` e le cartelle `logs`, `temp`, `webapps`, `work`.
6. Se `CATALINA_BASE/conf` non esiste, si copia `CATALINA_HOME/conf`. Se la sorgente manca: errore `Configurazione Tomcat incompleta: manca conf.` Se `conf` esiste già, non si ricopia (i log e un `server.xml` già preparato restano).
7. Si scrive sempre, in Swift, `conf/Catalina/localhost/<contesto>.xml`.

Nome file di contesto: si toglie lo slash iniziale; se il resto è vuoto il file è `ROOT.xml`; gli slash rimasti diventano `#`; si aggiunge `.xml`. `/CePosto` diventa `CePosto.xml`.

Contenuto:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Context docBase="<percorso assoluto escapato>" />
```

Il `docBase` è il percorso memorizzato, anche se la cartella non esiste ancora (Maven può crearla prima di Catalina).

Comando effettivamente passato a zsh:

- `commandEdited == true`: si esegue `command` così com'è salvato. Nessun prefisso.
- `commandEdited == false` e la cartella `tomcatDocBase` esiste: si esegue il comando salvato, cioè `exec "$CATALINA_HOME"/bin/catalina.sh run`.
- `commandEdited == false` e la cartella non esiste: si esegue `mvn -DskipTests -q war:exploded && exec "$CATALINA_HOME"/bin/catalina.sh run`.

Il comando salvato non riceve il prefisso Maven. Il prefisso esiste solo sull'invocazione. La preparazione di `CATALINA_BASE` avviene anche se `commandEdited` è true, purché l'avvio superi i controlli del punto 8 e l'adattatore sia tomcat.

Un errore di preparazione non fa spawn. Fase `crashed`. La frase di errore è aggiunta al ring log.

## 8. Avvio, porta, stato

`start` di un runner:

1. Se la fase è `starting` o `running`, l'avvio è ignorato. Nessun secondo spawn.
2. Se `command` è vuoto o solo spazi: niente spawn, fase `crashed`, nel log `importNote` se presente, altrimenti `Comando da completare.`
3. Se `portToCheck` è occupata: niente spawn, la fase non diventa `crashed` (resta quella precedente, di solito `stopped`), nel log `Porta <n> occupata.` Non si uccide nessuno.
4. Se è Tomcat, preparazione del punto 7. Errore: stop al punto sopra, fase `crashed`.
5. Si applica l'iniezione di debug sull'env di questo avvio, senza salvarla nel JSON.
6. Fase `starting`, poi spawn. Spawn riuscito: fase `running` e pid. Spawn fallito: fase `crashed`, motivo nel log, niente pid.

Iniezione di debug, solo se `debugEnabled` è true e `debugInjection` non è `none`:

```text
-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:<debugPort>
```

- `javaToolOptions` → variabile `JAVA_TOOL_OPTIONS`
- `catalinaOpts` → variabile `CATALINA_OPTS`

Se la variabile esiste già, si aggiunge uno spazio e il token, a meno che il token ci sia già. npm e python restano `none`: il toggle può essere acceso, ma non aggiunge JDWP.

Porta occupata e «Libera porta»:

- Il comando è `/usr/sbin/lsof` con argomenti `-ti` e `tcp:<porta>`, cioè la riga `lsof -ti tcp:PORT`.
- «Libera porta» prende quei pid e manda `SIGKILL` a ciascuno. Non è automatico all'avvio.
- I test costruiscono gli argomenti e parsano l'output (`"10\n20\n"` → `[10, 20]`) tramite un doppio. Il doppio non segnala pid reali.

Restart: se il runner è fermo o crashed, equivale a start. Se è starting o running, si ferma e al termine dell'uscita si riavvia, anche se il codice di uscita non è zero.

Colori del pallino:

- fermo: grigio (uscita 0, stop richiesto, o mai avviato)
- avvio: giallo
- in esecuzione: verde, con pid e porta
- crash: rosso (uscita diversa da zero non richiesta, spawn fallito, preparazione fallita, comando vuoto)

## 9. Log

`RingLog` tiene al massimo 1000 stringhe. Oltre, cadono le più vecchie. Una riga è il testo fra newline; l'ultimo pezzo senza newline resta in sospeso fino al newline successivo o alla fine del processo.

La ricerca della vista filtra solo la copia mostrata. Non modifica il buffer. La copia negli appunti copia le righe visibili (filtrate, se il campo non è vuoto). Clear svuota il buffer di quel runner.

Confronto di ricerca: `localizedCaseInsensitiveContains`.

## 10. Interfaccia

Un solo `MenuBarExtra`, `.menuBarExtraStyle(.window)`, `.preferredColorScheme(.dark)`, larghezza 400 punti. Sfondo scuro esplicito, non il tema chiaro di sistema. Icona di menu bar: SF Symbol `server.rack`. Se il numero di runner in fase `running` è maggiore di zero, accanto all'icona c'è quel numero. Lo stesso numero è nella pill «N attivo» dell'header (N è il conteggio, la parola resta «attivo»).

Le etichette Start, Stop, Restart, Logs, Edit, Debug, Clear e Copy restano in inglese, come nel layout approvato. Tutto il resto dell'interfaccia è in italiano.

Lista, dall'alto:

- Header: icona `server.rack`, titolo «Dev Runner», pill «N attivo».
- Se non ci sono progetti: «Nessun progetto».
- Per ogni progetto: nome, percorso troncato al centro, bottoni «Finder», «Terminale», «Sincronizza da .idea».
- Per ogni runner: pallino, nome, pid se running o starting (`pid 1234`), porta se `portToCheck` c'è (`:8080`). Se il comando è vuoto: «Comando da completare» e, sotto, `importNote`. Toggle «Debug» e, solo se `debugInjection` non è `none`, il testo `:<debugPort>`. Bottoni «Start» oppure «Stop» (Stop se starting o running), «Restart», «Logs», «Edit». Se c'è `portToCheck`, anche «Libera porta».

Footer:

- «+ Aggiungi Progetto»
- «Termina Tutti»
- «Apri config.json»
- «Esci» (`NSApplication.shared.terminate`)

Finder: `NSWorkspace` apre `rootPath`. Terminale: `/usr/bin/open -a Terminal <rootPath>`.

I log sostituiscono la lista nello stesso popover:

- «Indietro», nome del runner, pallino, porta se presente.
- Campo «Cerca», bottoni «Clear» e «Copy».
- Vista monospaziata scura, ancorata in fondo all'ultima riga visibile.

Sheet «Aggiungi Progetto»:

- Campi «Nome» e «Cartella», bottone «Sfoglia» (`NSOpenPanel`, solo cartelle).
- Se il nome è vuoto si usa il nome della cartella al momento della conferma.
- Dopo la scelta della cartella, sezione «Trovate in .idea» con una checkbox per runner. Tutte selezionate all'inizio. Comando vuoto: etichetta «Comando da completare» più la nota. Se non c'è nulla: «Nessuna configurazione in .idea».
- «Annulla» chiude senza scrivere.
- «Runner manuale» crea il progetto con un runner senza `idea`, comando vuoto, `debugInjection = none`, `debugPort = 5005`, cartella di lavoro uguale alla radice. Richiede la cartella.
- «Importa selezionate» crea il progetto con i runner spuntati. È disabilitato se non c'è la cartella o se non c'è nulla di spuntato.

Sheet «Modifica runner»:

- «Nome», «Comando» monospaziato, «Cartella di lavoro», «Porta da controllare» (vuoto = `nil`), «Porta debug», toggle «Debug», lista env con «Aggiungi» e «Rimuovi» per riga.
- «Annulla» e «Salva».
- Salva è disabilitato se il nome, troncato, è vuoto.
- Se la stringa comando è diversa da quella aperta nel sheet, `commandEdited` diventa `true`. Non torna `false` da sola.
- Se il comando salvato, troncato, non è vuoto, `importNote` diventa `nil`.

Fuori scope, e quindi assenti: Preferenze, menu ingranaggio, etichetta di versione, finta menu bar di sistema, tab Config/Env/Logs, didascalia `-Xdebug`, badge di tipo extra.

## 11. Pacchetto

```text
Package.swift
Sources/DevRunnerCore/
Sources/DevRunner/
Tests/DevRunnerCoreTests/
Scripts/package-app.sh
```

`DevRunnerCore` è una library. `DevRunner` è l'eseguibile e contiene solo l'app SwiftUI. I test importano la library, non l'eseguibile.

`Scripts/package-app.sh` esegue `swift build -c release`, crea `dist/DevRunner.app` con l'eseguibile in `Contents/MacOS/DevRunner` e un `Info.plist` con `LSUIElement` vero, `LSMinimumSystemVersion` 13.0, nome visibile «Dev Runner». Non firma il bundle.

File ammessi oltre al codice: `.gitignore` (ignora `.build/`, `dist/`, `.swiftpm/`, `.DS_Store`) e i due documenti in `docs/superpowers/`. Nessun altro Markdown.

## 12. Test obbligatori

- Scanner su fixture a forma di CePosto: `workspace.xml` con configurazione nome `Tomcat 9.0.41`, tipo che contiene `TomcatRunConfigurationFactory`, artifact `ceposto-java-server:war exploded`, context `/CePosto`, JRE `corretto-1.8`; più una configurazione npm e una Python; più la sostituzione di `$PROJECT_DIR$`.
- Tomcat: `applicationServers.xml` con home `/Users/icsone/Documents/Progetti/apache-tomcat-9.0.41` e un `jdk.table.xml` che risolve `corretto-1.8` producono un comando che termina con `bin/catalina.sh run` e `CATALINA_HOME` uguale a quella cartella. Il file di contesto previsto è `CePosto.xml`. Server assente (lista file server vuota, non la scoperta sulla macchina): comando vuoto.
- npm produce `npm run <script>`. Tipo sconosciuto: `unmapped` e comando vuoto.
- Resync con `commandEdited == true` non sostituisce il comando, e aggiorna nome, env e porta.
- `ConfigStore`: round-trip; file corrotto lasciato intatto anche dopo `save`.
- Ring buffer: 1000 righe, la più vecchia esce.
- Gruppo di processi, tramite lo stesso spawner con `/bin/zsh -f -c` (non `-l`): un comando che mette `sleep` in background, `SIGTERM` sul gruppo, il figlio muore; un secondo processo che ignora `SIGTERM` muore dopo `SIGKILL`. Timeout brevi. Si verifica anche `getpgid(pid) == pid`.
- Porta: si verifica l'argv di lsof e il parser. Nessun `kill` verso pid estranei.

## 13. Errori già decisi

- JSON atomico. File corrotto mai sovrascritto.
- Un XML rotto si salta; il resto si importa.
- Tipo sconosciuto: comando vuoto e nota.
- `commandEdited` sopravvive al resync e protegge il comando.
- Il ring scarta le righe oltre 1000, partendo dalle più vecchie.
- La ricerca non modifica il buffer.
- Comando vuoto o preparazione fallita: nessuno spawn, stato rosso, motivo nel log.
- Porta occupata: nessuno spawn e nessuno kill automatico.
