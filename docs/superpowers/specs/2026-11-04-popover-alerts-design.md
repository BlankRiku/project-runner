# Popover alerts e conferma eliminazione

## Obiettivo

Segnalare in popover i fallimenti di avvio (soprattutto porta occupata) e sostituire `NSAlert` delle eliminazioni con una scheda in-app, così il MenuBarExtra resta aperto.

## Comportamento

### Banner toast

- Stili: `success` (verde) e `error` (rosso).
- Successo: auto-dismiss ~2 s (come oggi).
- Errore: auto-dismiss ~4.5 s, o chiusura immediata se arriva un altro messaggio.
- Mostrato in avvio fallito: comando vuoto, porta occupata, prep Tomcat, spawn. Testo con nome runner.
- Crash a runtime dopo un avvio riuscito: solo stato «Errore» sulla riga, senza banner.

### Conferma eliminazione

- Scheda nella stessa fascia del banner: titolo, dettaglio, Annulla / Elimina.
- Non auto-dismiss; una sola conferma alla volta; ha priorità sul toast.
- Elimina progetto e elimina runner. Niente `NSAlert`.

## API

- `Session.start` restituisce `String?` con il motivo di fallimento immediato (nil se avviato o ignorato perché già live).
- `PopoverNotices` gestisce kind success/error.
- `PopoverConfirm` (o equivalente) per la scheda di conferma; `RemovalPrompt` rimosso.
