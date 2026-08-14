import Foundation

/// Die Race Engine — das Herzstück.
///
/// Sie lässt das Rennen in festen Zeitschritten ablaufen und ist die einzige Stelle,
/// die den Rennzustand verändert. Warum feste Zeitschritte und nicht Runde für Runde?
/// Weil die Track Map die Autos flüssig bewegen muss, Unfälle mitten in der Runde
/// passieren und ein VSC sofort wirken soll — nicht erst beim nächsten Überfahren der Linie.
///
/// Ein Schritt in Stichworten:
/// ```
/// Wetter → Flaggen → Autos bewegen → Reihenfolge & Abstände
///   → Safety-Car-Pulk → Überholen → Rundenwechsel (Reifen, Box, Zwischenfälle)
///   → Rennende? → Ereignisse zustellen
/// ```
public final class RaceEngine {

    // MARK: - Öffentlicher Zustand

    public let configuration: RaceConfiguration
    public let events = EventBus()
    public let raceControl: RaceControl

    public private(set) var raceTime: Double = 0
    public private(set) var isFinished = false
    /// Die Begründung der letzten Anordnung der Rennleitung.
    public private(set) var directorJustification: String?

    // MARK: - Innenleben

    private let safetyCar = SafetyCarSystem()
    private var weather: WeatherModel
    private var random: RandomSource
    private var cars: [CarSim] = []
    private var standings: [CarSim] = []
    private var started = false
    private var leaderFinished = false
    private var fastestLap: FastestLap?

    /// Größter Zeitschritt, der noch sauber rechnet. Größere werden zerlegt.
    private let maximumStep: Double = 0.5

    public init(configuration: RaceConfiguration) {
        self.configuration = configuration
        self.raceControl = RaceControl(drivers: configuration.drivers)
        self.random = RandomSource(masterSeed: configuration.seed)
        self.weather = WeatherModel(
            circuit: configuration.circuit,
            startingWeather: configuration.startingWeather,
            variability: configuration.weatherVariability
        )

        buildGrid()

        // Die Rennleitung hört von Anfang an mit.
        events.subscribe { [weak self] event in
            self?.raceControl.handle(event)
        }
    }

    /// Startaufstellung aufbauen.
    private func buildGrid() {
        let startCompound = TyreCompound.best(forWetness: weather.conditions.trackWetness)
        var teamByID: [String: Team] = [:]
        for team in configuration.teams { teamByID[team.id] = team }

        for (index, driverID) in configuration.startingGrid.enumerated() {
            guard let driver = configuration.driver(id: driverID),
                  let team = teamByID[driver.teamID] else { continue }
            let car = CarSim(
                driver: driver,
                team: team,
                gridPosition: index + 1,
                index: index,
                startingTyres: TyreSet.fresh(startCompound)
            )
            // Die Startaufstellung ist gestaffelt: P1 steht vorn, alle anderen dahinter.
            // Ein Startplatz sind rund acht Meter, hier als Rundenanteil ausgedrückt.
            car.lapProgress = 0
            car.currentLapEstimate = configuration.circuit.baseLapTime
            // Jedes Team plant seinen Stopp etwas anders.
            car.pitWindowOffset = random.with(.pitStops, actor: index) { rng in
                rng.int(in: 0...6)
            }
            cars.append(car)
        }
        standings = cars
    }

    // MARK: - Simulation

    /// Das Rennen um `deltaTime` Sekunden weiterlaufen lassen.
    public func advance(_ deltaTime: Double) {
        guard !isFinished, deltaTime > 0 else { return }

        // Große Schritte zerlegen, damit die Rechnung genau bleibt.
        var remaining = deltaTime
        while remaining > 0 && !isFinished {
            let step = min(remaining, maximumStep)
            tick(step)
            remaining -= step
        }
    }

    /// Das Rennen komplett durchrechnen (ohne Anzeige).
    public func runToCompletion(step: Double = 0.25, safetyLimit: Int = 4_000_000) {
        var iterations = 0
        while !isFinished && iterations < safetyLimit {
            advance(step)
            iterations += 1
        }
    }

    /// Ein einzelner Simulationsschritt.
    private func tick(_ dt: Double) {
        if !started {
            started = true
            events.publish(.raceStarted)
        }

        // Bei roter Flagge steht das Rennen: die Uhr läuft, die Autos nicht.
        if safetyCar.status == .redFlag {
            raceTime += dt
            deliver(safetyCar.update(deltaTime: dt, lap: currentLap))
            // Ist die Strecke geräumt, geht es hinter dem Safety Car weiter.
            // Ohne das würde ein abgebrochenes Rennen ewig stehen bleiben.
            if configuration.autoResumeRedFlag, safetyCar.isReadyToResume {
                deliver(safetyCar.resumeFromRedFlag(lap: currentLap))
            }
            events.flush()
            return
        }

        raceTime += dt

        updateWeather(dt)
        deliver(safetyCar.update(deltaTime: dt, lap: currentLap))

        for car in cars where car.isActive {
            step(car: car, dt: dt)
        }

        updateStandings()
        updateBunching()
        processOvertakes()
        checkRaceEnd()

        events.flush()
    }

    private func updateWeather(_ dt: Double) {
        let previous = weather.conditions.state
        let changed = random.with(.weather) { rng in
            weather.update(deltaTime: dt, random: &rng)
        }
        if let newState = changed {
            events.publish(.weatherChanged(from: previous, to: newState, lap: currentLap))
        }
    }

    // MARK: - Ein Auto bewegen

    private func step(car: CarSim, dt: Double) {
        // In der Boxengasse bewegt sich das Auto nicht auf der Strecke weiter.
        if car.status == .inPitLane {
            car.pitRemaining -= dt
            car.elapsedThisLap += dt
            if car.pitRemaining <= 0 {
                car.tyres = TyreSet.fresh(car.pitCompound)
                car.status = .running
            }
            return
        }

        let instant = instantaneousLapTime(car)
        car.currentLapEstimate = instant

        let progressDelta = dt / instant
        let oldProgress = car.lapProgress
        let newProgress = oldProgress + progressDelta

        recordSectorCrossings(car: car, from: oldProgress, to: newProgress, dt: dt)

        if newProgress >= 1.0 {
            // Zeit bis zur Ziellinie — der Rest gehört schon zur nächsten Runde.
            let timeToLine = (1.0 - oldProgress) / progressDelta * dt
            car.elapsedThisLap += timeToLine
            completeLap(car: car, crossingTime: raceTime - dt + timeToLine)

            let leftover = dt - timeToLine
            car.elapsedThisLap = leftover
            car.lapProgress = car.isActive ? leftover / max(instant, 1.0) : 0
        } else {
            car.lapProgress = newProgress
            car.elapsedThisLap += dt
        }
    }

    /// Wie schnell dieses Auto in genau diesem Moment unterwegs ist.
    ///
    /// Die Streuung wird nur einmal pro Runde gewürfelt (`lapNoise`), der Rest jeden
    /// Schritt neu — so wirkt ein VSC sofort, ohne dass die Zufallsfolge durcheinandergerät.
    private func instantaneousLapTime(_ car: CarSim) -> Double {
        // Unter VSC und Safety Car gilt für **alle** dasselbe Delta.
        //
        // Das ist der eigentliche Sinn einer Neutralisierung: Niemand darf aufholen.
        // Würde hier weiter die individuelle Rundenzeit benutzt (nur langsamer), käme
        // ein schnelles Auto einem langsamen trotzdem näher und könnte es sogar
        // überholen — obwohl Überholen gesperrt ist. Die Reihenfolge muss stehen.
        if safetyCar.status.isNeutralised {
            let delta = configuration.circuit.baseLapTime * safetyCar.status.lapTimeMultiplier
            return delta * car.bunchFactor
        }

        let input = makeInput(car)
        let deterministic = LapTimeModel.deterministicLapTime(input)
        let withNoise = max(deterministic * 0.96, deterministic + car.lapNoise)
        return withNoise * car.bunchFactor
    }

    private func makeInput(_ car: CarSim) -> LapTimeModel.Input {
        return LapTimeModel.Input(
            driver: car.driver,
            team: car.team,
            circuit: configuration.circuit,
            tyres: car.tyres,
            weather: weather.conditions,
            trackStatus: safetyCar.status,
            lapsRemaining: max(0, configuration.laps - car.lapsCompleted),
            inDirtyAir: car.inDirtyAir,
            aiStrength: configuration.aiStrength
        )
    }

    /// Zwischenzeiten mitschreiben.
    ///
    /// Die Sektorzeiten werden so gerechnet, dass ihre Summe **exakt** die Rundenzeit
    /// ergibt — sonst passt die Anzeige nicht zu den Zahlen daneben.
    private func recordSectorCrossings(car: CarSim, from: Double, to: Double, dt: Double) {
        let splits = configuration.circuit.sectorSplits
        guard to > from else { return }
        for split in splits where from < split && split <= to {
            let fraction = (split - from) / (to - from)
            car.sectorMarks.append(car.elapsedThisLap + fraction * dt)
        }
    }

    // MARK: - Rundenwechsel

    private func completeLap(car: CarSim, crossingTime: Double) {
        car.lapsCompleted += 1
        car.crossingTimes.append(crossingTime)

        let lapTime = car.elapsedThisLap
        car.lastLapTime = lapTime
        car.lastSectors = finalizeSectors(car: car, lapTime: lapTime)
        car.sectorMarks.removeAll()

        events.publish(.lapCompleted(driverID: car.driver.id, lap: car.lapsCompleted, lapTime: lapTime))

        // Nur saubere Runden unter grüner Flagge zählen für die Bestzeit.
        let clean = !car.lapCompromised && safetyCar.status == .green
        if clean {
            if car.bestLapTime == nil || lapTime < car.bestLapTime! {
                car.bestLapTime = lapTime
            }
            if fastestLap == nil || lapTime < fastestLap!.time {
                for other in cars { other.hasFastestLap = false }
                car.hasFastestLap = true
                fastestLap = FastestLap(driverID: car.driver.id, lap: car.lapsCompleted, time: lapTime)
                events.publish(.fastestLap(driverID: car.driver.id, lap: car.lapsCompleted, lapTime: lapTime))
            }
        }
        car.lapCompromised = safetyCar.status != .green

        // Reifen um eine Runde altern lassen.
        TyreModel.advanceLap(
            tyres: &car.tyres,
            driver: car.driver,
            circuit: configuration.circuit,
            weather: weather.conditions,
            pushLevel: car.inDirtyAir ? 1.15 : 1.0
        )

        // Neue Tagesform für die kommende Runde.
        car.lapNoise = random.with(.lapTime, actor: car.index) { rng in
            rng.gaussian(mean: 0, standardDeviation: LapTimeModel.variation(makeInput(car)))
        }

        // Ziel erreicht?
        if car.lapsCompleted >= configuration.laps || leaderFinished {
            finishCar(car)
            return
        }

        rollIncidents(for: car)
        guard car.isActive else { return }

        considerPitStop(for: car)
    }

    /// Sektorzeiten so aufteilen, dass sie sich exakt zur Rundenzeit addieren.
    private func finalizeSectors(car: CarSim, lapTime: Double) -> [Double] {
        let marks = car.sectorMarks
        guard marks.count >= 2 else { return [] }
        let s1 = marks[0]
        let s2 = marks[1] - marks[0]
        let s3 = lapTime - marks[1]
        guard s1 > 0, s2 > 0, s3 > 0 else { return [] }
        return [s1, s2, s3]
    }

    private func finishCar(_ car: CarSim) {
        car.status = .finished
        car.lapProgress = 0
        if !leaderFinished {
            leaderFinished = true
            safetyCar.finish()
            events.publish(.raceFinished)
        }
    }

    // MARK: - Boxenstopp

    private func considerPitStop(for car: CarSim) {
        let decision = random.with(.pitStops, actor: car.index) { rng in
            PitStrategy.evaluate(
                driver: car.driver,
                tyres: car.tyres,
                circuit: configuration.circuit,
                weather: weather.conditions,
                trackStatus: safetyCar.status,
                lapsCompleted: car.lapsCompleted,
                totalLaps: configuration.laps,
                pitStopsMade: car.pitStops,
                windowOffset: car.pitWindowOffset,
                random: &rng
            )
        }
        guard decision.shouldPit else { return }

        let stationary = random.with(.pitStops, actor: car.index) { rng in
            PitStrategy.stationaryTime(team: car.team, random: &rng)
        }

        // Eine offene Zeitstrafe wird beim Stopp abgesessen.
        let servedPenalty = min(car.penaltySeconds, 10)
        car.penaltySeconds -= servedPenalty

        let total = configuration.circuit.pitLaneLoss + stationary + servedPenalty
        car.status = .inPitLane
        car.pitRemaining = total
        car.pitCompound = decision.compound
        car.pitStops += 1
        car.lapCompromised = true

        events.publish(.pitStop(
            driverID: car.driver.id,
            lap: car.lapsCompleted,
            compound: decision.compound,
            duration: total
        ))
    }

    // MARK: - Zwischenfälle

    private func rollIncidents(for car: CarSim) {
        let sector = random.with(.incidents, actor: car.index) { rng in rng.int(in: 1...3) }

        // Technischer Defekt.
        let failureChance = IncidentModel.failureProbability(team: car.team, lapsCompleted: car.lapsCompleted)
        let failed = random.with(.reliability, actor: car.index) { rng in rng.chance(failureChance) }
        if failed {
            let (incident, reason) = random.with(.incidents, actor: car.index) { rng in
                IncidentModel.makeMechanicalFailure(
                    driver: car.driver, lap: car.lapsCompleted, sector: sector, random: &rng
                )
            }
            events.publish(.incident(incident))
            retire(car: car, reason: reason)
            applyDirectorVerdict(for: incident)
            return
        }

        // Fahrfehler.
        let errorChance = IncidentModel.errorProbability(
            driver: car.driver,
            tyres: car.tyres,
            weatherIncidentFactor: weather.incidentFactor,
            trackStatus: safetyCar.status,
            isBattling: car.inDirtyAir,
            aiStrength: configuration.aiStrength
        )
        let erred = random.with(.incidents, actor: car.index) { rng in rng.chance(errorChance) }
        guard erred else { return }

        let incident = random.with(.incidents, actor: car.index) { rng in
            IncidentModel.makeDrivingIncident(
                driver: car.driver,
                lap: car.lapsCompleted,
                sector: sector,
                wetness: weather.conditions.trackWetness,
                random: &rng
            )
        }
        events.publish(.incident(incident))

        if incident.carStopped {
            retire(car: car, reason: incident.kind.displayName)
        } else {
            // Ausrutscher kosten Zeit, beenden das Rennen aber nicht.
            let loss = incident.severity == .medium ? 4.5 : 1.8
            car.lapProgress = max(0, car.lapProgress - loss / max(car.currentLapEstimate, 1))
            car.lapCompromised = true
        }

        applyDirectorVerdict(for: incident)
    }

    private func retire(car: CarSim, reason: String) {
        car.status = .retired
        car.retirementReason = reason
        car.lapProgress = 0
        events.publish(.retirement(driverID: car.driver.id, lap: car.lapsCompleted, reason: reason))
    }

    /// Den Race Director entscheiden lassen und die Anordnung umsetzen.
    private func applyDirectorVerdict(for incident: Incident) {
        let runners = cars.filter { $0.isActive }.count
        let verdict = RaceDirector.evaluate(
            incident: incident,
            currentStatus: safetyCar.status,
            wetness: weather.conditions.trackWetness,
            lapsRemaining: max(0, configuration.laps - currentLap),
            runningCars: runners
        )
        guard verdict.decision != .noAction else { return }
        directorJustification = verdict.justification
        deliver(safetyCar.apply(verdict: verdict, lap: currentLap))

        // Unter Neutralisierung ist keine Runde mehr sauber.
        for car in cars { car.lapCompromised = true }
    }

    // MARK: - Reihenfolge und Abstände

    private func updateStandings() {
        standings = cars.sorted(by: RaceEngine.orderCars)

        for (index, car) in standings.enumerated() {
            car.position = index + 1
        }

        guard let leader = standings.first else { return }

        for car in standings {
            if car === leader {
                car.gapToLeader = 0
                car.interval = 0
                car.lapsDown = 0
                continue
            }

            let difference = leader.raceProgress - car.raceProgress
            car.lapsDown = max(0, Int(difference.rounded(.down)))

            if car.status == .retired {
                car.gapToLeader = 0
                car.interval = 0
                continue
            }

            // Abstand wie in der echten Zeitnahme: Wann war der Führende hier?
            if let leaderTimeHere = leader.time(atProgress: car.raceProgress) {
                car.gapToLeader = max(0, referenceTime(for: car) - leaderTimeHere)
            } else {
                car.gapToLeader = max(0, difference * car.currentLapEstimate)
            }
        }

        // Intervall = Differenz der Rückstände zum Vordermann.
        for index in standings.indices where index > 0 {
            let car = standings[index]
            let ahead = standings[index - 1]
            car.interval = max(0, car.gapToLeader - ahead.gapToLeader)
        }

        // Dirty Air: Wer dicht dran ist, verliert Abtrieb.
        for index in standings.indices {
            let car = standings[index]
            car.inDirtyAir = index > 0
                && car.interval <= 1.0
                && car.lapsDown == standings[index - 1].lapsDown
                && car.isActive
        }
    }

    /// Welche Zeit für den Abstand herangezogen wird.
    /// Für Autos im Ziel friert der Abstand bei ihrer Zielzeit ein.
    private func referenceTime(for car: CarSim) -> Double {
        if car.status == .finished, let finish = car.crossingTimes.last {
            return finish
        }
        return raceTime
    }

    /// Die Reihenfolge im Klassement.
    private static func orderCars(_ lhs: CarSim, _ rhs: CarSim) -> Bool {
        // Ausgefallene immer nach hinten.
        if (lhs.status == .retired) != (rhs.status == .retired) {
            return rhs.status == .retired
        }
        if lhs.status == .retired && rhs.status == .retired {
            if lhs.lapsCompleted != rhs.lapsCompleted {
                return lhs.lapsCompleted > rhs.lapsCompleted
            }
            return lhs.driver.id < rhs.driver.id
        }
        // Im Ziel: die frühere Zielzeit gewinnt.
        if lhs.status == .finished && rhs.status == .finished {
            let lhsTime = lhs.crossingTimes.last ?? .greatestFiniteMagnitude
            let rhsTime = rhs.crossingTimes.last ?? .greatestFiniteMagnitude
            if lhsTime != rhsTime { return lhsTime < rhsTime }
            return lhs.driver.id < rhs.driver.id
        }
        if lhs.raceProgress != rhs.raceProgress {
            return lhs.raceProgress > rhs.raceProgress
        }
        return lhs.driver.id < rhs.driver.id
    }

    /// Unter Safety Car schiebt sich das Feld zusammen.
    ///
    /// Statt die Autos zu versetzen (das würde Runden und Sektoren durcheinanderbringen),
    /// bekommt jedes Auto nur ein anderes Tempo: zu weit hinten = etwas schneller,
    /// zu dicht dran = etwas langsamer. Der Pulk entsteht dann von selbst.
    private func updateBunching() {
        guard case .safetyCar = safetyCar.status else {
            for car in cars { car.bunchFactor = 1.0 }
            return
        }
        let targetInterval = 1.2
        for (index, car) in standings.enumerated() {
            guard car.isActive else { car.bunchFactor = 1.0; continue }
            if index == 0 {
                car.bunchFactor = 1.0
            } else {
                let deviation = car.interval - targetInterval
                car.bunchFactor = min(max(1.0 - deviation * 0.25, 0.72), 1.30)
            }
        }
    }

    // MARK: - Überholen

    private func processOvertakes() {
        guard safetyCar.status.allowsOvertaking else { return }

        // Von hinten nach vorn, damit ein Auto nicht zweimal im selben Schritt vorbeigeht.
        for index in stride(from: standings.count - 1, through: 1, by: -1) {
            let attacker = standings[index]
            let defender = standings[index - 1]

            guard attacker.status == .running, defender.status == .running else { continue }
            // Überrunden ist kein Überholen — dabei ändert sich keine Position.
            guard attacker.lapsDown == defender.lapsDown else { continue }
            guard attacker.lapsCompleted == defender.lapsCompleted else { continue }
            guard attacker.interval <= OvertakeModel.attackRange else { continue }
            // Höchstens ein Angriff pro Runde.
            guard attacker.lastAttackLap != attacker.lapsCompleted else { continue }

            attacker.lastAttackLap = attacker.lapsCompleted

            let duel = OvertakeModel.Duel(
                attacker: attacker.driver,
                defender: defender.driver,
                attackerTyres: attacker.tyres,
                defenderTyres: defender.tyres,
                paceAdvantage: defender.currentLapEstimate - attacker.currentLapEstimate,
                gap: attacker.interval,
                circuit: configuration.circuit,
                drsAvailable: attacker.interval <= OvertakeModel.drsRange
                    && attacker.lapsCompleted >= 2
                    && weather.conditions.trackWetness < 0.3
            )

            let probability = OvertakeModel.passProbability(duel)
            let succeeded = random.with(.overtaking, actor: attacker.index) { rng in rng.chance(probability) }

            if succeeded {
                swapPositions(attacker: attacker, defender: defender)
                events.publish(.overtake(
                    driverID: attacker.driver.id,
                    overtakenID: defender.driver.id,
                    lap: attacker.lapsCompleted + 1,
                    newPosition: defender.position
                ))
            } else {
                let contactChance = OvertakeModel.contactProbability(duel)
                let contact = random.with(.overtaking, actor: attacker.index) { rng in rng.chance(contactChance) }
                if contact {
                    handleContact(attacker: attacker, defender: defender)
                }
            }
        }
    }

    private func swapPositions(attacker: CarSim, defender: CarSim) {
        let middle = (attacker.lapProgress + defender.lapProgress) / 2
        attacker.lapProgress = min(0.998, middle + 0.0015)
        defender.lapProgress = max(0.0, middle - 0.0015)
        swap(&attacker.position, &defender.position)
    }

    private func handleContact(attacker: CarSim, defender: CarSim) {
        let sector = configuration.circuit.sector(at: attacker.lapProgress)
        let incident = random.with(.incidents, actor: attacker.index) { rng in
            IncidentModel.makeCollision(
                attacker: attacker.driver,
                defender: defender.driver,
                lap: attacker.lapsCompleted + 1,
                sector: sector,
                random: &rng
            )
        }
        events.publish(.incident(incident))

        if incident.carStopped {
            // Der Angreifer ist raus. Ob es den Verteidigten auch erwischt, ist offen —
            // oft rettet der sich mit kaputtem Flügel noch an die Box.
            retire(car: attacker, reason: "COLLISION")
            let defenderOut = random.with(.incidents, actor: defender.index) { rng in rng.chance(0.45) }
            if defenderOut {
                retire(car: defender, reason: "COLLISION DAMAGE")
            } else {
                defender.lapProgress = max(0, defender.lapProgress - 12.0 / max(defender.currentLapEstimate, 1))
                defender.lapCompromised = true
            }
        } else {
            for car in [attacker, defender] {
                car.lapProgress = max(0, car.lapProgress - 3.0 / max(car.currentLapEstimate, 1))
                car.lapCompromised = true
            }
        }

        // Fünf Sekunden gibt es nur, wenn der Angreifer es verbockt hat —
        // ein reiner Rennunfall bleibt straffrei.
        let atFault = random.with(.raceControl, actor: attacker.index) { rng in
            rng.chance(OvertakeModel.attackerAtFaultProbability(duelForFault(attacker: attacker, defender: defender)))
        }
        if atFault {
            attacker.penaltySeconds += 5
            events.publish(.penalty(
                driverID: attacker.driver.id,
                lap: attacker.lapsCompleted + 1,
                seconds: 5,
                reason: "CAUSING A COLLISION"
            ))
        }

        applyDirectorVerdict(for: incident)
    }

    /// Minimal-Duell nur für die Schuldfrage.
    private func duelForFault(attacker: CarSim, defender: CarSim) -> OvertakeModel.Duel {
        return OvertakeModel.Duel(
            attacker: attacker.driver,
            defender: defender.driver,
            attackerTyres: attacker.tyres,
            defenderTyres: defender.tyres,
            paceAdvantage: 0,
            gap: 0,
            circuit: configuration.circuit,
            drsAvailable: false
        )
    }

    // MARK: - Rennende

    private func checkRaceEnd() {
        guard !isFinished else { return }
        let stillGoing = cars.contains { $0.isActive }
        if !stillGoing {
            isFinished = true
            safetyCar.finish()
            if !leaderFinished {
                leaderFinished = true
                events.publish(.raceFinished)
            }
        }
    }

    // MARK: - Nach außen

    /// Die aktuelle Runde des Führenden, 1-basiert wie auf der Anzeigetafel.
    public var currentLap: Int {
        let leader = standings.first ?? cars.first
        let completed = leader?.lapsCompleted ?? 0
        return min(configuration.laps, completed + 1)
    }

    /// Der komplette Rennstand — das, was die Anzeige bekommt.
    public func snapshot() -> RaceSnapshot {
        return RaceSnapshot(
            circuit: configuration.circuit,
            sessionType: configuration.sessionType,
            lap: currentLap,
            totalLaps: configuration.laps,
            raceTime: raceTime,
            trackStatus: safetyCar.status,
            neutralisationCountdown: safetyCar.countdown,
            directorJustification: directorJustification,
            weather: weather.conditions,
            standings: standings.map { $0.makeState() },
            messages: raceControl.latest(40),
            fastestLap: fastestLap,
            isFinished: isFinished
        )
    }

    /// Das Endergebnis — erst nach der Zielflagge sinnvoll.
    public func result() -> RaceResult? {
        guard isFinished else { return nil }
        return RaceResult.build(
            cars: standings,
            configuration: configuration,
            fastestLap: fastestLap,
            raceTime: raceTime
        )
    }

    // MARK: - Manuelle Rennleitung (Multiplayer / Tests)

    /// Zustand von außen setzen — dafür gibt es im Multiplayer später die Race-Control-Konsole.
    public func forceTrackStatus(_ status: TrackStatus, clearance: Double = 60) {
        safetyCar.forceStatus(status, clearance: clearance)
    }

    /// Rennen nach roter Flagge fortsetzen.
    public func resumeFromRedFlag() {
        deliver(safetyCar.resumeFromRedFlag(lap: currentLap))
        events.flush()
    }

    /// Einen Zwischenfall von außen auslösen — nutzt die Tests und die Race-Control-Konsole.
    public func injectIncident(_ incident: Incident) {
        events.publish(.incident(incident))
        if incident.carStopped, let car = cars.first(where: { $0.driver.id == incident.driverIDs.first }) {
            retire(car: car, reason: incident.kind.displayName)
        }
        applyDirectorVerdict(for: incident)
        events.flush()
    }

    /// Zeitstrafe verhängen.
    public func applyPenalty(driverID: String, seconds: Double, reason: String) {
        guard let car = cars.first(where: { $0.driver.id == driverID }) else { return }
        car.penaltySeconds += seconds
        events.publish(.penalty(driverID: driverID, lap: currentLap, seconds: seconds, reason: reason))
        events.flush()
    }

    /// Einen Fahrer aus dem Rennen nehmen.
    public func forceRetirement(driverID: String, reason: String) {
        guard let car = cars.first(where: { $0.driver.id == driverID }), car.isActive else { return }
        retire(car: car, reason: reason)
        updateStandings()
        checkRaceEnd()
        events.flush()
    }

    /// Wetter von außen umstellen.
    public func forceWeather(_ state: WeatherState) {
        let previous = weather.conditions.state
        weather = WeatherModel(
            circuit: configuration.circuit,
            startingWeather: state,
            variability: configuration.weatherVariability
        )
        events.publish(.weatherChanged(from: previous, to: state, lap: currentLap))
        events.flush()
    }

    private func deliver(_ newEvents: [RaceEvent]) {
        for event in newEvents {
            events.publish(event)
        }
    }
}
