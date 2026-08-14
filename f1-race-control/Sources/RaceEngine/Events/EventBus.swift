import Foundation

/// Die Verteilstelle für Renn-Ereignisse.
///
/// Wichtig ist die **Reihenfolge**: Ereignisse werden nicht sofort zugestellt, sondern
/// erst gesammelt und am Ende des Simulationsschritts der Reihe nach ausgeliefert (FIFO).
/// Empfänger werden in der Reihenfolge bedient, in der sie sich angemeldet haben.
/// Nur so kommt bei gleichem Seed zweimal genau dasselbe Rennen heraus.
public final class EventBus {
    public typealias Handler = (RaceEvent) -> Void

    private var handlers: [Handler] = []
    private var pending: [RaceEvent] = []
    private var delivering = false

    /// Vollständiges Protokoll aller Ereignisse in Reihenfolge.
    public private(set) var log: [RaceEvent] = []

    public init() {}

    /// Empfänger anmelden. Die Reihenfolge der Anmeldung ist auch die Zustellreihenfolge.
    public func subscribe(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    /// Ereignis einreihen. Zugestellt wird es erst bei `flush()`.
    public func publish(_ event: RaceEvent) {
        pending.append(event)
    }

    /// Alle offenen Ereignisse zustellen.
    ///
    /// Empfänger dürfen dabei selbst neue Ereignisse auslösen (ein Crash führt zu VSC,
    /// VSC führt zu einer Race-Control-Meldung). Die landen hinten in der Schlange und
    /// werden in derselben Runde mit abgearbeitet.
    public func flush() {
        guard !delivering else { return }   // keine Rekursion
        delivering = true
        defer { delivering = false }

        var guardCounter = 0
        while !pending.isEmpty {
            guardCounter += 1
            if guardCounter > 10_000 {
                // Reißleine: irgendein Empfänger erzeugt endlos neue Ereignisse.
                pending.removeAll()
                break
            }
            let event = pending.removeFirst()
            log.append(event)
            for handler in handlers {
                handler(event)
            }
        }
    }

    /// Nur die Kurzformen — praktisch, um zwei Rennläufe zu vergleichen.
    public var logSignature: [String] {
        return log.map { $0.shortDescription }
    }

    /// Protokoll leeren (z.B. beim Neustart nach roter Flagge).
    public func reset() {
        log.removeAll()
        pending.removeAll()
    }
}
