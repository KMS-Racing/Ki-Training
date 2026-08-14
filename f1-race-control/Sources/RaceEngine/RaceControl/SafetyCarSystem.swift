import Foundation

/// Verwaltet Gelb, VSC, Safety Car und Rote Flagge — inklusive Countdown zur Freigabe.
///
/// Das VSC ist hier **echte Logik** und nicht nur ein Schriftzug:
/// ```
/// Unfall
///   ↓
/// VSC DEPLOYED      Tempo runter (Delta), Überholen gesperrt, Box bleibt offen
///   ↓
/// VSC ENDING        5 → 4 → 3 → 2 → 1
///   ↓
/// GREEN FLAG        Rennen frei
/// ```
public final class SafetyCarSystem {
    public private(set) var status: TrackStatus = .green
    /// Der laufende Countdown, falls die Freigabe bevorsteht.
    public private(set) var countdown: Int?

    /// Wie lange das Bergen noch dauert.
    private var clearanceRemaining: Double = 0
    /// Wie lange die aktuelle Neutralisierung schon läuft.
    private var timeNeutralised: Double = 0
    /// Restzeit des Countdowns.
    private var countdownRemaining: Double = 0
    /// Welche Zahl zuletzt angesagt wurde (damit 5,4,3,2,1 je einmal kommt).
    private var lastAnnounced: Int = 0
    /// Dauer der Ausroll-Phase, bis alle das Delta erreicht haben.
    private var deployRemaining: Double = 0

    /// Ein VSC läuft mindestens so lange — sonst wäre es sinnlos.
    private let minimumVSCDuration: Double = 60
    /// Ein Safety Car braucht länger, das Feld muss sich erst sammeln.
    private let minimumSafetyCarDuration: Double = 150
    private let countdownLength: Double = 5

    public init() {}

    /// Läuft gerade eine Neutralisierung?
    public var isNeutralised: Bool {
        return status.isNeutralised
    }

    /// Ist die Strecke nach einer roten Flagge wieder frei?
    ///
    /// Im Einzelspieler-Rennen gibt niemand von Hand frei — die Engine macht das
    /// dann selbst. Im Mehrspieler-Modus entscheidet später der Race Director.
    public var isReadyToResume: Bool {
        return status == .redFlag && clearanceRemaining <= 0
    }

    /// Anordnung der Rennleitung umsetzen.
    ///
    /// - Returns: Die Ereignisse, die dadurch entstehen.
    public func apply(verdict: DirectorVerdict, lap: Int) -> [RaceEvent] {
        switch verdict.decision {
        case .noAction:
            return []

        case .localYellow:
            guard case .green = status else { return [] }
            status = .yellow(sector: 1)
            clearanceRemaining = verdict.clearanceSeconds
            return [.yellowFlag(sector: 1, lap: lap)]

        case .virtualSafetyCar:
            status = .virtualSafetyCar(phase: .deploying)
            startNeutralisation(clearance: verdict.clearanceSeconds)
            return [.virtualSafetyCarDeployed(lap: lap, reason: verdict.justification)]

        case .safetyCar:
            status = .safetyCar(phase: .deploying)
            startNeutralisation(clearance: verdict.clearanceSeconds)
            return [.safetyCarDeployed(lap: lap, reason: verdict.justification)]

        case .redFlag:
            status = .redFlag
            clearanceRemaining = verdict.clearanceSeconds
            countdown = nil
            return [.redFlag(lap: lap, reason: verdict.justification)]
        }
    }

    private func startNeutralisation(clearance: Double) {
        clearanceRemaining = clearance
        timeNeutralised = 0
        countdown = nil
        countdownRemaining = 0
        lastAnnounced = 0
        deployRemaining = 6   // Ausrollphase
    }

    /// Einen Simulationsschritt weiter.
    ///
    /// - Returns: Ereignisse (Countdown-Ansagen, grüne Flagge).
    public func update(deltaTime: Double, lap: Int) -> [RaceEvent] {
        var events: [RaceEvent] = []

        switch status {
        case .green, .finished:
            return []

        case .redFlag:
            // Bleibt, bis jemand das Rennen freigibt (`resumeFromRedFlag`).
            clearanceRemaining = max(0, clearanceRemaining - deltaTime)
            return []

        case .yellow:
            clearanceRemaining -= deltaTime
            if clearanceRemaining <= 0 {
                status = .green
                events.append(.greenFlag(lap: lap))
            }

        case .virtualSafetyCar(let phase):
            events += advanceNeutralisation(
                phase: phase,
                deltaTime: deltaTime,
                lap: lap,
                minimumDuration: minimumVSCDuration,
                makeStatus: { TrackStatus.virtualSafetyCar(phase: $0) },
                endingEvent: .virtualSafetyCarEnding(lap: lap)
            )

        case .safetyCar(let phase):
            events += advanceNeutralisation(
                phase: phase,
                deltaTime: deltaTime,
                lap: lap,
                minimumDuration: minimumSafetyCarDuration,
                makeStatus: { TrackStatus.safetyCar(phase: $0) },
                endingEvent: .safetyCarEnding(lap: lap)
            )
        }

        return events
    }

    /// Der gemeinsame Ablauf von VSC und Safety Car — nur die Namen unterscheiden sich.
    private func advanceNeutralisation(
        phase: NeutralisationPhase,
        deltaTime: Double,
        lap: Int,
        minimumDuration: Double,
        makeStatus: (NeutralisationPhase) -> TrackStatus,
        endingEvent: RaceEvent
    ) -> [RaceEvent] {
        var events: [RaceEvent] = []
        timeNeutralised += deltaTime
        clearanceRemaining = max(0, clearanceRemaining - deltaTime)

        switch phase {
        case .deploying:
            deployRemaining -= deltaTime
            if deployRemaining <= 0 {
                status = makeStatus(.active)
            }

        case .active:
            // Erst wenn geborgen ist UND die Mindestdauer um ist, geht es weiter.
            if clearanceRemaining <= 0 && timeNeutralised >= minimumDuration {
                status = makeStatus(.ending)
                countdownRemaining = countdownLength
                lastAnnounced = 6
                events.append(endingEvent)
            }

        case .ending:
            countdownRemaining -= deltaTime
            let shown = max(0, Int(countdownRemaining.rounded(.up)))
            countdown = shown > 0 ? shown : nil
            if shown < lastAnnounced {
                lastAnnounced = shown
            }
            if countdownRemaining <= 0 {
                status = .green
                countdown = nil
                events.append(.greenFlag(lap: lap))
            }
        }

        return events
    }

    /// Rennen nach roter Flagge wieder freigeben.
    public func resumeFromRedFlag(lap: Int) -> [RaceEvent] {
        guard status == .redFlag else { return [] }
        status = .safetyCar(phase: .deploying)
        startNeutralisation(clearance: 30)
        return [.raceResumed(lap: lap), .safetyCarDeployed(lap: lap, reason: "Rolling restart after red flag.")]
    }

    /// Rennen beenden (Zielflagge).
    public func finish() {
        status = .finished
        countdown = nil
    }

    /// Direkt setzen — für Tests und die manuelle Rennleitung im Multiplayer.
    public func forceStatus(_ newStatus: TrackStatus, clearance: Double = 60) {
        status = newStatus
        if newStatus.isNeutralised {
            startNeutralisation(clearance: clearance)
        } else if newStatus == .redFlag {
            // Auch die rote Flagge braucht eine Bergungszeit — sonst gäbe die Engine
            // sofort wieder frei und das Rennen stünde nie still.
            clearanceRemaining = clearance
            countdown = nil
        }
    }
}
