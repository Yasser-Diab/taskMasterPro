(() => {
  const LANGUAGE_STORAGE_KEY = "dayvector:site-language";
  const THEME_STORAGE_KEY = "dayvector:site-theme";
  const LANGUAGE_ORDER = ["en", "de", "ar", "pl"];
  const SUPPORTED_LANGUAGES = new Set(LANGUAGE_ORDER);

  const german = {
    "DayVector turns direction into daily progress with task planning, roadmaps, focus timers, activity insights and evidence-based coaching on Windows and Android.":
      "DayVector macht aus deiner Richtung täglichen Fortschritt – mit Aufgabenplanung, Roadmaps, Fokustimern, Aktivitätseinblicken und nachvollziehbarem Coaching für Windows und Android.",
    "DayVector — Turn direction into daily progress":
      "DayVector – Aus Richtung wird täglicher Fortschritt",
    "Plan meaningful goals, focus on the next task and improve with evidence-based coaching across Windows and Android.":
      "Plane wichtige Ziele, konzentriere dich auf die nächste Aufgabe und verbessere dich mit nachvollziehbarem Coaching auf Windows und Android.",
    "Personal planning, focused execution and evidence-based coaching on Windows and Android.":
      "Persönliche Planung, fokussierte Umsetzung und nachvollziehbares Coaching auf Windows und Android.",
    "DayVector — Planning, Focus Timers, Roadmaps and Coaching":
      "DayVector – Planung, Fokustimer, Roadmaps und Coaching",
    "DayVector turns goals into roadmaps, recurring tasks and daily actions, measures real effort and provides explainable coaching across Windows and Android.":
      "DayVector macht aus Zielen Roadmaps, wiederkehrende Aufgaben und tägliche Schritte, misst den tatsächlichen Aufwand und bietet nachvollziehbares Coaching unter Windows und Android.",
    "DayVector: Plan, Focus and Improve":
      "DayVector: Planen, fokussieren und besser werden",
    "Create roadmaps, execute focused tasks, track real activity and improve through evidence-based coaching.":
      "Erstelle Roadmaps, arbeite fokussiert, erfasse echte Aktivität und verbessere dich mit nachvollziehbarem Coaching.",
    "DayVector: Planning, Focus and Personal Coaching":
      "DayVector: Planung, Fokus und persönliches Coaching",
    "Skip to main content": "Zum Hauptinhalt springen",
    "Skip to timer": "Zum Timer springen",
    "DayVector home": "DayVector-Startseite",
    "Open navigation": "Navigation öffnen",
    "Close navigation": "Navigation schließen",
    "Main navigation": "Hauptnavigation",
    "Pomodoro page navigation": "Navigation der Pomodoro-Seite",
    Features: "Funktionen",
    "How It Works": "So funktioniert es",
    Roadmaps: "Roadmaps",
    Widget: "Widget",
    Health: "Gesundheit",
    Coaching: "Coaching",
    Pomodoro: "Pomodoro",
    Privacy: "Datenschutz",
    Contact: "Kontakt",
    Download: "Herunterladen",
    "Download App": "App herunterladen",
    "Download app": "App herunterladen",
    "Turn direction into daily progress":
      "Aus Richtung wird täglicher Fortschritt",
    "Plan your goals": "Plane deine Ziele",
    "Execute your tasks": "Setze deine Aufgaben um",
    "Improve every day": "Werde jeden Tag besser",
    "DayVector combines task management, structured roadmaps, time tracking and personalized coaching to help you organize your responsibilities, improve your habits and make better use of your time":
      "DayVector verbindet Aufgaben, strukturierte Roadmaps, Zeiterfassung und persönliches Coaching. So organisierst du deine Verpflichtungen, stärkst deine Gewohnheiten und nutzt deine Zeit sinnvoller.",
    "It connects planned work with real activity, credits useful effort to the task it supports and turns verified patterns into clear recommendations":
      "Die App verbindet geplante Arbeit mit deiner tatsächlichen Aktivität, ordnet nützlichen Aufwand der richtigen Aufgabe zu und macht aus erkannten Mustern klare Empfehlungen.",
    "Download for Windows": "Für Windows herunterladen",
    "Download for Android": "Für Android herunterladen",
    "Explore how it works": "Entdecke, wie es funktioniert",
    "Supported platforms and capabilities":
      "Unterstützte Plattformen und Funktionen",
    "DayVector dashboard showing task suggestions, today's schedule, workload and overdue work":
      "DayVector-Dashboard mit Aufgabenvorschlägen, heutigem Plan, Arbeitslast und überfälligen Aufgaben",
    Windows: "Windows",
    "Android phones": "Android-Smartphones",
    "Android tablets": "Android-Tablets",
    "Offline capable": "Offline nutzbar",
    "Cross-device synchronization": "Synchronisierung zwischen Geräten",
    Today: "Heute",
    "6 tasks complete": "6 Aufgaben erledigt",
    Focus: "Fokus",
    "2h 41m active": "2 Std. 41 Min. aktiv",
    Roadmap: "Roadmap",
    "68% complete": "68 % erledigt",
    "One connected system": "Ein System, das alles verbindet",
    "One application for planning, execution, progress and improvement":
      "Eine App zum Planen, Umsetzen und Weiterentwickeln",
    "DayVector connects what you plan with what you actually do. It measures real effort, recognizes useful work, identifies delays and helps you improve your future schedule":
      "DayVector verbindet deine Pläne mit dem, was du wirklich tust. Die App misst den tatsächlichen Aufwand, erkennt nützliche Arbeit, zeigt Verzögerungen und hilft dir, künftige Tage besser zu planen.",
    "Feature status legend": "Legende zum Funktionsstatus",
    Available: "Verfügbar",
    Beta: "Beta",
    Planned: "Geplant",
    "Built for meaningful progress": "Für Fortschritt, der wirklich zählt",
    "Everything you need to turn plans into progress":
      "Alles, was aus Plänen echten Fortschritt macht",
    "Long-term direction, daily responsibilities, real execution data and personalized guidance come together inside one calm workspace":
      "Langfristige Ziele, tägliche Aufgaben, echte Arbeitsdaten und persönliche Hinweise kommen in einem ruhigen Arbeitsbereich zusammen.",
    "Turn large goals into clear phases": "Teile große Ziele in klare Etappen",
    "Create roadmaps with phases, milestones, checkpoints, recurring work, practice targets and completion requirements":
      "Erstelle Roadmaps mit Etappen, Meilensteinen, Prüfpunkten, wiederkehrenden Aufgaben, Übungszielen und klaren Abschlusskriterien.",
    "Choose the right next action": "Wähle den richtigen nächsten Schritt",
    "Bring priority, deadlines, available time, dependencies and roadmap importance into one practical recommendation":
      "Priorität, Fristen, verfügbare Zeit, Abhängigkeiten und Roadmap-Bedeutung fließen in eine praktische Empfehlung ein.",
    "Understand how your time is used":
      "Verstehe, wofür deine Zeit wirklich draufgeht",
    "Track focused work, continuous sessions, pauses, idle periods, interruptions and the difference between planned and actual effort":
      "Erfasse fokussierte Arbeit, längere Sitzungen, Pausen, inaktive Zeiten, Unterbrechungen und den Unterschied zwischen geplantem und tatsächlichem Aufwand.",
    "Useful work is never lost": "Nützliche Arbeit geht nicht verloren",
    "Review activity from breaks or other sessions and credit approved effort to the task and roadmap it truly supported":
      "Prüfe Aktivitäten aus Pausen oder anderen Sitzungen und ordne bestätigten Aufwand der Aufgabe und Roadmap zu, die er wirklich unterstützt hat.",
    "Roadmaps adapt to real performance":
      "Roadmaps passen sich deiner echten Leistung an",
    "Forecasts respond to actual effort, postponed work, missed sessions, confirmed progress and available capacity":
      "Prognosen reagieren auf tatsächlichen Aufwand, verschobene Arbeit, verpasste Sitzungen, bestätigten Fortschritt und freie Kapazität.",
    "Get a helpful next step": "Erhalte einen hilfreichen nächsten Schritt",
    "Coaching uses today’s schedule, paused work, roadmap priorities and your preferences to offer a respectful next action":
      "Das Coaching nutzt deinen heutigen Plan, pausierte Arbeit, Roadmap-Prioritäten und deine Wünsche, um einen passenden nächsten Schritt vorzuschlagen.",
    "A practical loop": "Ein einfacher Ablauf",
    "From a long-term goal to today’s next action":
      "Vom langfristigen Ziel zum nächsten Schritt heute",
    "Define your goal": "Lege dein Ziel fest",
    "Create a personal, professional, learning, health or habit goal":
      "Erstelle ein persönliches, berufliches, Lern-, Gesundheits- oder Gewohnheitsziel.",
    "Reach German B1": "Deutsch B1 erreichen",
    "Build the roadmap": "Baue deine Roadmap",
    "Divide the goal into phases, milestones, checkpoints and practical recurring tasks":
      "Teile das Ziel in Etappen, Meilensteine, Prüfpunkte und praktische wiederkehrende Aufgaben.",
    "Execute the work": "Setze die Arbeit um",
    "Match each responsibility with focused sessions, continuous timers, checklists, reading or manual completion":
      "Nutze für jede Aufgabe die passende Methode: Fokussitzung, fortlaufender Timer, Checkliste, Lesen oder manueller Abschluss.",
    "Learn and improve": "Lerne und verbessere dich",
    "Compare the plan with actual performance and use evidence to shape the next one":
      "Vergleiche deinen Plan mit der tatsächlichen Leistung und nutze die Ergebnisse für die nächste Planung.",
    "Roadmap workspace": "Roadmap-Arbeitsbereich",
    "DayVector roadmap displaying phases, checkpoints and progress forecasts":
      "DayVector-Roadmap mit Etappen, Prüfpunkten und Fortschrittsprognosen",
    "Build a realistic path toward every goal":
      "Baue einen realistischen Weg zu jedem Ziel",
    "Roadmaps turn long-term direction into measurable phases and responsibilities. Every item remains editable and every percentage has an explanation":
      "Roadmaps machen aus einer langfristigen Richtung messbare Etappen und Aufgaben. Jeder Eintrag bleibt bearbeitbar und jeder Prozentwert wird erklärt.",
    "Editable phases": "Bearbeitbare Etappen",
    "Target dates": "Zieldaten",
    "Recurring tasks": "Wiederkehrende Aufgaben",
    Milestones: "Meilensteine",
    Checkpoints: "Prüfpunkte",
    "Required effort": "Benötigter Aufwand",
    "Forecast completion": "Voraussichtlicher Abschluss",
    "Risk warnings": "Risikohinweise",
    "Forecast example": "Beispielprognose",
    "The expected phase completion moved by four days because three tasks required more time and two sessions were postponed":
      "Der erwartete Abschluss der Etappe verschob sich um vier Tage, weil drei Aufgaben mehr Zeit brauchten und zwei Sitzungen verschoben wurden.",
    Confidence: "Sicherheit",
    Medium: "Mittel",
    Evidence: "Grundlage",
    "11 comparable sessions": "11 vergleichbare Sitzungen",
    "Flexible execution": "Flexibel arbeiten",
    "Different responsibilities need different methods":
      "Unterschiedliche Aufgaben brauchen unterschiedliche Methoden",
    "DayVector is designed to match the work rather than forcing every activity into the same timer":
      "DayVector passt sich der Arbeit an, statt jede Aktivität in denselben Timer zu zwängen.",
    "Pomodoro Focus": "Pomodoro-Fokus",
    "Focus cycles, breaks, pauses and interruptions":
      "Fokuszyklen, Erholungspausen und Unterbrechungen",
    "Try the free browser timer": "Kostenlosen Browser-Timer ausprobieren",
    "Continuous Timer": "Fortlaufender Timer",
    "Long work blocks, active time and overtime":
      "Lange Arbeitsblöcke, aktive Zeit und Mehrarbeit",
    Checklist: "Checkliste",
    "Required items, priorities and completion rules":
      "Pflichtpunkte, Prioritäten und Abschlussregeln",
    Reading: "Lesen",
    "Books, PDFs, duration, saved position and notes":
      "Bücher, PDFs, Lesedauer, gespeicherte Position und Notizen",
    Habit: "Gewohnheit",
    "Streaks, completion rate, recovery and timing":
      "Serien, Abschlussquote, Erholung und Zeitplanung",
    Event: "Termin",
    "Arrival, duration, lateness and follow-up work":
      "Ankunft, Dauer, Verspätung und Nacharbeit",
    Hybrid: "Kombiniert",
    "Combine timers, checklists, checkpoints and resources":
      "Verbinde Timer, Checklisten, Prüfpunkte und Materialien.",
    "Focus from your home screen": "Fokus direkt auf dem Startbildschirm",
    "Your running session stays visible and controllable":
      "Deine laufende Sitzung bleibt sichtbar und steuerbar",
    "The responsive Android widget reflects the current DayVector session. See the remaining time at a glance, pause without opening the app, move to a break or finish when the work is complete.":
      "Das responsive Android-Widget zeigt deine aktuelle DayVector-Sitzung. Du siehst die Restzeit sofort, kannst ohne Öffnen der App pausieren, in eine Pause wechseln oder die Arbeit beenden.",
    "Live focus and break countdowns": "Live-Countdowns für Fokus und Pausen",
    "Pause, break and finish controls":
      "Steuerung für Pause, Erholung und Abschluss",
    "Compact, medium and expanded sizes":
      "Kompakte, mittlere und große Darstellung",
    "Canonical state shared with the app":
      "Ein gemeinsamer, verlässlicher Status mit der App",
    "Try the browser Pomodoro": "Browser-Pomodoro ausprobieren",
    "Get the Android widget": "Android-Widget herunterladen",
    "Live DayVector Android widget demonstration":
      "Live-Demo des DayVector-Widgets für Android",
    "Interactive widget preview controls":
      "Interaktive Steuerung der Widget-Vorschau",
    "FOCUS SESSION": "FOKUSSITZUNG",
    "Focus session": "Fokussitzung",
    "RECOVERY BREAK": "ERHOLUNGSPAUSE",
    "Recovery break": "Erholungspause",
    "Deep work session": "Konzentrierte Arbeit",
    "Time to recharge": "Zeit zum Auftanken",
    Pause: "Pausieren",
    Resume: "Fortsetzen",
    Break: "Pause",
    Finish: "Beenden",
    "A real live preview with working countdown and controls":
      "Echte Live-Vorschau mit funktionierendem Countdown und Steuerung",
    "Cross-task attribution": "Arbeit richtig zuordnen",
    "Useful activity belongs to the task it actually supports":
      "Nützliche Aktivität gehört zu der Aufgabe, die sie wirklich unterstützt",
    "Time does not always follow the schedule. The contribution engine retains raw activity, requests approval when needed and avoids counting the same physical minute twice":
      "Zeit folgt nicht immer dem Plan. Die Zuordnung bewahrt die ursprüngliche Aktivität, fragt bei Bedarf nach deiner Bestätigung und zählt dieselbe Minute nie doppelt.",
    "Current session": "Aktuelle Sitzung",
    "Programming task": "Programmieraufgabe",
    "Five-minute Pomodoro break": "Fünf Minuten Pomodoro-Pause",
    "Detected activity": "Erkannte Aktivität",
    "German learning app": "Deutsch-Lernapp",
    "4 minutes 12 seconds": "4 Minuten 12 Sekunden",
    "Approved result": "Bestätigtes Ergebnis",
    "German daily practice": "Tägliche Deutschübung",
    "German B1 roadmap updated": "Roadmap Deutsch B1 aktualisiert",
    "Physical timeline": "Tatsächliche Zeitspanne",
    "Approved practice": "Bestätigte Übung",
    "Duplicated time": "Doppelt gezählte Zeit",
    "Unknown and idle-looking activity stays available for review":
      "Unklare oder inaktiv wirkende Zeit bleibt zur Prüfung sichtbar",
    "Were you reading, working away from the computer, helping another task or simply taking a break? Your answer can improve future suggestions":
      "Hast du gelesen, ohne Computer gearbeitet, eine andere Aufgabe unterstützt oder einfach Pause gemacht? Deine Antwort verbessert künftige Vorschläge.",
    "Activity insights": "Aktivitäten verstehen",
    "Understand which tools help you perform":
      "Erkenne, welche Werkzeuge dir wirklich helfen",
    "Compare the applications and websites expected for a task with the tools that were actually used, then correct classifications at any time":
      "Vergleiche die für eine Aufgabe erwarteten Apps und Websites mit den tatsächlich genutzten Werkzeugen. Einordnungen kannst du jederzeit korrigieren.",
    "Visual Studio Code supported most of this development session":
      "Visual Studio Code hat den größten Teil dieser Entwicklungssitzung unterstützt.",
    "The browser was used mainly for documentation research":
      "Der Browser wurde hauptsächlich für die Recherche in Dokumentationen genutzt.",
    "One recurring application still needs a task assignment":
      "Eine wiederkehrend genutzte App muss noch einer Aufgabe zugeordnet werden.",
    "Application report": "App-Bericht",
    "Build synchronization engine": "Synchronisierung entwickeln",
    "Primary application": "Hauptanwendung",
    Productive: "Produktiv",
    "Web browser": "Webbrowser",
    "28 minutes": "28 Minuten",
    Research: "Recherche",
    Email: "E-Mail",
    "11 minutes": "11 Minuten",
    Communication: "Kommunikation",
    "Video platform": "Videoplattform",
    "14 minutes": "14 Minuten",
    "Needs review": "Prüfung nötig",
    "Personal coaching": "Persönliches Coaching",
    "Coaching based on your actual behavior":
      "Coaching auf Basis deines tatsächlichen Verhaltens",
    "Friendly suggestions use today’s schedule, active or paused work, roadmap priorities and your coaching preferences. You remain in control":
      "Freundliche Vorschläge berücksichtigen deinen heutigen Plan, aktive oder pausierte Arbeit, Roadmap-Prioritäten und deine Coaching-Wünsche. Du behältst die Kontrolle.",
    "Start delays": "Später Start",
    Workload: "Arbeitslast",
    "Roadmap risk": "Roadmap-Risiko",
    "Break quality": "Pausenqualität",
    Distraction: "Ablenkung",
    "Micro-sessions": "Kurze Sitzungen",
    "Coaching insight": "Coaching-Hinweis",
    "Start with less friction": "Starte leichter",
    "High confidence": "Hohe Sicherheit",
    "Your Work tasks usually begin": "Deine Arbeitsaufgaben beginnen meistens",
    "17 minutes late": "17 Minuten zu spät",
    "This recommendation is based on your previous 12 Work sessions":
      "Diese Empfehlung basiert auf deinen letzten 12 Arbeitssitzungen.",
    "Suggested action": "Vorgeschlagener Schritt",
    "Move the preparation reminder 10 minutes earlier":
      "Verschiebe die Vorbereitungserinnerung um 10 Minuten nach vorn.",
    "Apply suggestion": "Vorschlag anwenden",
    Helpful: "Hilfreich",
    "Not helpful": "Nicht hilfreich",
    "Wrong time": "Falscher Zeitpunkt",
    "Current focus": "Aktueller Fokus",
    "Start on Windows. Continue on Android":
      "Unter Windows starten und auf Android weitermachen",
    "Start, pause or resume the same task from Windows or Android. Tasks, roadmaps, settings and approved work stay consistent when devices are online":
      "Starte, pausiere oder setze dieselbe Aufgabe unter Windows oder Android fort. Aufgaben, Roadmaps, Einstellungen und bestätigte Arbeit bleiben auf verbundenen Geräten einheitlich.",
    "Start on Windows": "Unter Windows starten",
    "View on Android": "Auf Android ansehen",
    "Continue on Windows": "Unter Windows fortsetzen",
    "Immediate local button response": "Sofortige lokale Reaktion auf Eingaben",
    "Local timer calculation": "Lokale Timer-Berechnung",
    "Duplicate-command protection": "Schutz vor doppelten Befehlen",
    "One shared active task and session state":
      "Ein gemeinsamer Status für aktive Aufgabe und Sitzung",
    "Offline operation": "Offline weiterarbeiten",
    "Your work does not stop when the internet does":
      "Deine Arbeit stoppt nicht, nur weil das Internet ausfällt",
    "Create tasks, update roadmaps and keep working without a connection. Saved changes synchronize safely when your device reconnects":
      "Erstelle Aufgaben, aktualisiere Roadmaps und arbeite ohne Verbindung weiter. Gespeicherte Änderungen werden sicher synchronisiert, sobald dein Gerät wieder online ist.",
    Offline: "Offline",
    "3 changes waiting safely": "3 Änderungen sicher vorgemerkt",
    Connected: "Verbunden",
    "All changes synchronized": "Alle Änderungen synchronisiert",
    "Privacy and control": "Datenschutz und Kontrolle",
    "Detailed insights under your control":
      "Detaillierte Einblicke, die du kontrollierst",
    "You choose which activity DayVector may record and whether selected data remains local or is synchronized":
      "Du entscheidest, welche Aktivitäten DayVector erfassen darf und ob ausgewählte Daten lokal bleiben oder synchronisiert werden.",
    "DayVector does not upload browser cookies, website login tokens, clipboard contents, form contents or unencrypted passwords":
      "DayVector lädt keine Browser-Cookies, Anmeldedaten von Websites, Inhalte der Zwischenablage, Formularinhalte oder unverschlüsselte Passwörter hoch.",
    "View Privacy Policy": "Datenschutzerklärung ansehen",
    "View Terms of Use": "Nutzungsbedingungen ansehen",
    "Activity privacy": "Aktivitätsdatenschutz",
    "Your choices": "Deine Auswahl",
    "Track applications": "Apps erfassen",
    "Track window titles": "Fenstertitel erfassen",
    "Track domains only": "Nur Domains erfassen",
    "Track full URLs": "Vollständige URLs erfassen",
    "Keep selected history local": "Ausgewählten Verlauf lokal behalten",
    "Pause tracking": "Erfassung pausieren",
    "Delete activity history": "Aktivitätsverlauf löschen",
    Review: "Prüfen",
    "The operational view": "Dein Überblick",
    "Everything important, visible in one place":
      "Alles Wichtige auf einen Blick",
    "DayVector dashboard showing task suggestions, schedule, workload and overdue responsibilities":
      "DayVector-Dashboard mit Aufgabenvorschlägen, Zeitplan, Arbeitslast und überfälligen Aufgaben",
    "Today’s responsibilities, active work, roadmap progress, unresolved activity and coaching direction in one focused dashboard":
      "Heutige Aufgaben, laufende Arbeit, Roadmap-Fortschritt, ungeklärte Aktivität und Coaching-Hinweise erscheinen in einem übersichtlichen Dashboard.",
    "Task suggestions": "Aufgabenvorschläge",
    "Today's workload": "Heutige Arbeitslast",
    Schedule: "Zeitplan",
    "Clear current task state": "Klarer Status der aktuellen Aufgabe",
    "Next suggested responsibility": "Nächste vorgeschlagene Aufgabe",
    "Today’s schedule and workload": "Heutiger Zeitplan und Arbeitsumfang",
    "Overdue work and items needing attention":
      "Überfällige Aufgaben und Punkte, die Aufmerksamkeit brauchen",
    "Dynamic coaching and synchronization status":
      "Dynamisches Coaching und Synchronisierungsstatus",
    "Dynamic coaching": "Dynamisches Coaching",
    "DayVector coaching carousel with several evidence-based suggestions":
      "DayVector-Coaching mit mehreren nachvollziehbaren Vorschlägen",
    "Several suggestions, always in your control":
      "Mehrere Vorschläge, die du jederzeit steuerst",
    "Activity insights": "Aktivitätsübersicht",
    "DayVector Activity view grouping useful application time without losing individual periods":
      "DayVector-Aktivitätsansicht, die nützliche App-Zeit gruppiert und einzelne Zeiträume bewahrt",
    "Clear, editable classifications": "Klare, bearbeitbare Zuordnungen",
    "Direct contact": "Direkter Kontakt",
    "Questions, feedback or support?": "Fragen, Feedback oder Unterstützung?",
    "Contact the creator of DayVector for help with the app, privacy questions, feedback, bug reports, feature suggestions or general enquiries":
      "Wende dich für Hilfe zur App, Datenschutzfragen, Feedback, Fehlermeldungen, Funktionswünsche oder allgemeine Fragen direkt an den Entwickler von DayVector.",
    "Created and maintained by": "Entwickelt und gepflegt von",
    "Contact Y. A. Diab": "Y. A. Diab kontaktieren",
    "Email Y. A. Diab about DayVector":
      "E-Mail an Y. A. Diab zu DayVector senden",
    "Application support": "Hilfe zur App",
    "Privacy questions": "Datenschutzfragen",
    "Bug reports": "Fehlermeldungen",
    "Feature suggestions": "Funktionswünsche",
    "Build a better system for your time":
      "Baue ein besseres System für deine Zeit",
    "Download DayVector and begin turning long-term goals into practical, measurable daily progress":
      "Lade DayVector herunter und verwandle langfristige Ziele in praktische, messbare Fortschritte im Alltag.",
    "Recommended for your device": "Für dein Gerät empfohlen",
    "DayVector for Windows": "DayVector für Windows",
    "Designed for Windows 10 and Windows 11": "Für Windows 10 und Windows 11",
    Version: "Version",
    Installer: "Installationsdatei",
    "64-bit EXE": "64-Bit-EXE",
    Size: "Größe",
    "Shown on GitHub": "Wird auf GitHub angezeigt",
    "Checking release…": "Version wird geprüft…",
    "Release notes": "Versionshinweise",
    "Installation help": "Installationshilfe",
    "DayVector for Android": "DayVector für Android",
    "Designed for Android phones and tablets":
      "Für Android-Smartphones und -Tablets",
    Package: "Paket",
    "Signed APK": "Signierte APK",
    "A personal planning, execution and performance-coaching system for Windows and Android":
      "Ein persönliches System zum Planen, Umsetzen und Verbessern für Windows und Android.",
    Product: "Produkt",
    "Android Widget": "Android-Widget",
    "Free Pomodoro": "Kostenloses Pomodoro",
    Legal: "Rechtliches",
    "Privacy Policy": "Datenschutzerklärung",
    "Terms of Use": "Nutzungsbedingungen",
    "Installation Help": "Installationshilfe",
    "Support and feedback": "Support und Feedback",
    "Windows and Android": "Windows und Android",
    "DayVector Release Notes": "Versionshinweise zu DayVector",
    "Release date available with the notes":
      "Das Veröffentlichungsdatum erscheint mit den Hinweisen.",
    "Close release notes": "Versionshinweise schließen",
    "Loading release notes…": "Versionshinweise werden geladen…",
    "Latest published release": "Neueste veröffentlichte Version",
    "Release notes are temporarily unavailable":
      "Die Versionshinweise sind vorübergehend nicht verfügbar.",
    "Try loading the notes again shortly.": "Versuche es in Kürze noch einmal.",
    "Try again": "Erneut versuchen",
    Close: "Schließen",
    "Release date unavailable": "Veröffentlichungsdatum nicht verfügbar",
    "Size unavailable": "Größe nicht verfügbar",
    "Coming soon!": "Demnächst verfügbar",
    "Available with the release": "Mit der Version verfügbar",
    "Checking…": "Wird geprüft…",

    "Privacy Policy for DayVector":
      "Datenschutzerklärung für DayVector",
    "Privacy choices and data-handling information for DayVector.":
      "Informationen zu Datenschutzoptionen und zur Datenverarbeitung in DayVector.",
    "← Back to privacy overview": "← Zurück zur Datenschutzübersicht",
    "Privacy policy": "Datenschutzerklärung",
    "Your activity stays under your control":
      "Deine Aktivität bleibt unter deiner Kontrolle",
    "Effective 25 July 2026": "Gültig ab 25. Juli 2026",
    "DayVector is a planning, execution and performance-coaching application created and maintained by Y. A. Diab. This policy explains the categories of information the application may process and the choices available to you.":
      "DayVector ist eine von Y. A. Diab entwickelte und gepflegte App zum Planen, Umsetzen und Verbessern. Diese Erklärung beschreibt, welche Arten von Informationen die App verarbeiten kann und welche Auswahlmöglichkeiten du hast.",
    "Information you provide": "Informationen, die du angibst",
    "This may include account details, profile preferences, tasks, roadmaps, notes, reminders, resources and feedback. Authentication is provided through Supabase. Google sign-in, when selected, is processed by Google and Supabase.":
      "Dazu können Kontodaten, Profileinstellungen, Aufgaben, Roadmaps, Notizen, Erinnerungen, Materialien und Feedback gehören. Die Anmeldung erfolgt über Supabase. Wenn du die Google-Anmeldung auswählst, wird sie von Google und Supabase verarbeitet.",
    "Optional activity information": "Optionale Aktivitätsinformationen",
    "With your permission, DayVector may process application usage, window titles, website domains or URLs, document activity, idle state and manually recorded off-device work. Controls in the application determine which categories are enabled and whether supported activity remains local or is synchronized.":
      "Mit deiner Erlaubnis kann DayVector die App-Nutzung, Fenstertitel, Website-Domains oder URLs, Dokumentaktivität, Inaktivitätszeiten und manuell erfasste Arbeit außerhalb des Geräts verarbeiten. In der App legst du fest, welche Kategorien aktiv sind und ob unterstützte Aktivitäten lokal bleiben oder synchronisiert werden.",
    "Information DayVector does not upload":
      "Informationen, die DayVector nicht hochlädt",
    "The application is designed not to upload browser cookies, website login tokens, clipboard contents, form contents, banking-session information, email-session tokens or unencrypted passwords.":
      "Die App ist so ausgelegt, dass sie keine Browser-Cookies, Anmeldetoken von Websites, Inhalte der Zwischenablage, Formularinhalte, Informationen aus Banking-Sitzungen, E-Mail-Sitzungstoken oder unverschlüsselte Passwörter hochlädt.",
    "Why information is used": "Wofür Informationen genutzt werden",
    "Information is used to operate requested features, synchronize connected devices, calculate progress and reports, detect unresolved activity, improve schedules, deliver notifications and generate explainable coaching. Optional data is not treated as medical diagnosis.":
      "Informationen werden genutzt, um gewünschte Funktionen bereitzustellen, verbundene Geräte zu synchronisieren, Fortschritt und Berichte zu berechnen, ungeklärte Aktivitäten zu erkennen, Zeitpläne zu verbessern, Benachrichtigungen zu senden und nachvollziehbares Coaching zu erstellen. Optionale Daten werden nicht als medizinische Diagnose behandelt.",
    "Storage and service providers": "Speicherung und Dienstanbieter",
    "DayVector stores working data locally on your device. When synchronization is enabled, account data may be processed by Supabase infrastructure. Platform services may also process data needed for sign-in, notifications, software downloads and operating-system integrations.":
      "DayVector speichert Arbeitsdaten lokal auf deinem Gerät. Wenn die Synchronisierung aktiviert ist, können Kontodaten über die Infrastruktur von Supabase verarbeitet werden. Plattformdienste können außerdem Daten verarbeiten, die für Anmeldung, Benachrichtigungen, Software-Downloads und Betriebssystemintegrationen nötig sind.",
    "Your controls": "Deine Einstellungen",
    "Depending on the feature status and platform, you can pause tracking, exclude applications or websites, correct classifications, remove history, keep selected information local, revoke device access, export account data and request account deletion.":
      "Je nach Funktionsstand und Plattform kannst du die Erfassung pausieren, Apps oder Websites ausschließen, Einordnungen korrigieren, Verläufe entfernen, ausgewählte Informationen lokal behalten, Gerätezugriff widerrufen, Kontodaten exportieren und die Löschung des Kontos anfordern.",
    "Security and sensitive features": "Sicherheit und sensible Funktionen",
    "DayVector uses platform and service security controls appropriate to each feature. Planned security-sensitive features are not represented as available until their implementation and review are complete.":
      "DayVector nutzt für jede Funktion passende Sicherheitsmechanismen der Plattform und der verwendeten Dienste. Geplante sicherheitsrelevante Funktionen werden erst als verfügbar dargestellt, wenn Implementierung und Prüfung abgeschlossen sind.",
    "Changes to this policy": "Änderungen an dieser Erklärung",
    "This policy may be updated as DayVector evolves. The effective date above will change when material revisions are published.":
      "Diese Erklärung kann mit der Weiterentwicklung von DayVector aktualisiert werden. Das oben genannte Datum ändert sich, wenn wesentliche Überarbeitungen veröffentlicht werden.",
    "For privacy questions, email": "Bei Datenschutzfragen schreibe an",

    "Terms of Service for DayVector":
      "Nutzungsbedingungen für DayVector",
    "Terms governing use of the DayVector application.":
      "Bedingungen für die Nutzung der DayVector-App.",
    "← Back to DayVector": "← Zurück zu DayVector",
    "Terms of service": "Nutzungsbedingungen",
    "Clear terms for using DayVector":
      "Klare Bedingungen für die Nutzung von DayVector",
    "These terms apply to your use of DayVector, an application created and maintained by Y. A. Diab. By creating an account or using the application, you agree to use it lawfully and in accordance with these terms.":
      "Diese Bedingungen gelten für deine Nutzung von DayVector, einer von Y. A. Diab entwickelten und gepflegten App. Wenn du ein Konto erstellst oder die App nutzt, erklärst du dich damit einverstanden, sie rechtmäßig und nach diesen Bedingungen zu verwenden.",
    "Purpose of the application": "Zweck der App",
    "DayVector provides tools for planning, task execution, time and activity review, roadmaps, reports and performance coaching. Features marked Beta or Planned may change, remain incomplete or be unavailable on some platforms.":
      "DayVector bietet Werkzeuge für Planung, Aufgabenumsetzung, Zeit- und Aktivitätsprüfung, Roadmaps, Berichte und Leistungscoaching. Als Beta oder Geplant gekennzeichnete Funktionen können sich ändern, unvollständig bleiben oder auf einzelnen Plattformen nicht verfügbar sein.",
    "Your account and content": "Dein Konto und deine Inhalte",
    "You are responsible for safeguarding your sign-in methods, maintaining accurate account information and keeping appropriate backups of important content. You retain responsibility for the tasks, notes, resources and other content you add.":
      "Du bist dafür verantwortlich, deine Anmeldemethoden zu schützen, korrekte Kontoinformationen zu pflegen und wichtige Inhalte angemessen zu sichern. Für Aufgaben, Notizen, Materialien und andere von dir hinzugefügte Inhalte bleibst du verantwortlich.",
    "Acceptable use": "Zulässige Nutzung",
    "Do not use DayVector to violate law, infringe the rights of others, attempt unauthorized access, distribute malicious software or interfere with the application and its supporting services.":
      "Nutze DayVector nicht für Gesetzesverstöße, Verletzungen der Rechte anderer, unbefugte Zugriffsversuche, die Verbreitung schädlicher Software oder Störungen der App und ihrer unterstützenden Dienste.",
    "Updates and availability": "Updates und Verfügbarkeit",
    "Software updates may add, change or remove features. You choose whether to install an offered desktop or Android package, and the operating system may require additional confirmation. Availability can be affected by device, network and third-party service conditions.":
      "Software-Updates können Funktionen hinzufügen, ändern oder entfernen. Du entscheidest, ob du ein angebotenes Desktop- oder Android-Paket installierst. Das Betriebssystem kann zusätzliche Bestätigungen verlangen. Die Verfügbarkeit kann vom Gerät, Netzwerk und von Drittanbieterdiensten abhängen.",
    "Productivity and coaching information":
      "Informationen zu Produktivität und Coaching",
    "DayVector provides planning, productivity and performance information. It does not provide medical, psychological, legal, financial or professional diagnosis or treatment.":
      "DayVector stellt Informationen zu Planung, Produktivität und Leistung bereit. Die App bietet keine medizinische, psychologische, rechtliche, finanzielle oder sonstige professionelle Diagnose oder Behandlung.",
    "No guaranteed outcome": "Kein garantiertes Ergebnis",
    "Forecasts and recommendations depend on available information and may be incomplete or inaccurate. You remain in control of decisions, classifications, schedules and progress.":
      "Prognosen und Empfehlungen hängen von den verfügbaren Informationen ab und können unvollständig oder ungenau sein. Du behältst die Kontrolle über Entscheidungen, Einordnungen, Zeitpläne und Fortschritt.",
    "Ending use": "Nutzung beenden",
    "You may stop using the application and, when available in the account controls, request deletion of synchronized account information. Some records may be retained temporarily where required for security, integrity or legal reasons.":
      "Du kannst die Nutzung der App beenden und, sofern in den Kontoeinstellungen verfügbar, die Löschung synchronisierter Kontoinformationen anfordern. Einige Datensätze können vorübergehend aufbewahrt werden, wenn dies aus Sicherheits-, Integritäts- oder rechtlichen Gründen nötig ist.",
    "For support or questions about these terms, contact Y. A. Diab at":
      "Bei Supportfragen oder Fragen zu diesen Bedingungen erreichst du Y. A. Diab unter",

    "Installation Help for DayVector":
      "Installationshilfe für DayVector",
    "Install DayVector on Windows, Android phones and Android tablets.":
      "Installiere DayVector unter Windows sowie auf Android-Smartphones und -Tablets.",
    "← Back to downloads": "← Zurück zu den Downloads",
    "Installation help": "Installationshilfe",
    "Get DayVector running": "DayVector installieren und starten",
    "Applies to the version shown on the download card":
      "Gilt für die auf der Download-Karte angezeigte Version",
    "Windows 10 and Windows 11": "Windows 10 und Windows 11",
    "Download the Windows installer from the official GitHub release.":
      "Lade die Windows-Installationsdatei aus der offiziellen GitHub-Version herunter.",
    "Open the downloaded DayVector Windows installer.":
      "Öffne die heruntergeladene Windows-Installationsdatei von DayVector.",
    "Review any Windows security prompt, then continue the installer.":
      "Prüfe einen möglichen Windows-Sicherheitshinweis und fahre dann mit der Installation fort.",
    "Launch DayVector from the Start menu or desktop shortcut.":
      "Starte DayVector über das Startmenü oder die Desktop-Verknüpfung.",
    "Android phones and tablets": "Android-Smartphones und -Tablets",
    "Download the signed DayVector Android package.":
      "Lade das signierte Android-Paket von DayVector herunter.",
    "Open the downloaded APK from your browser or Files application.":
      "Öffne die heruntergeladene APK im Browser oder in der Dateien-App.",
    "If Android asks, allow installation from that source for this install.":
      "Wenn Android danach fragt, erlaube für diese Installation die Nutzung dieser Quelle.",
    "Review the package details and confirm installation.":
      "Prüfe die Paketdetails und bestätige die Installation.",
    "DayVector never starts an installation without your action. Windows may show a reputation warning for a new, unsigned release, and Android requires confirmation before installing an APK outside an app store.":
      "DayVector startet niemals ohne deine Aktion eine Installation. Windows kann bei einer neuen, unsignierten Version einen Reputationshinweis anzeigen. Android verlangt eine Bestätigung, bevor eine APK außerhalb eines App-Stores installiert wird.",
    "Check your download": "Download prüfen",
    "Every official release includes a verification file beside each installer. You can use it to confirm that the download has not changed before opening it.":
      "Zu jeder offiziellen Version gehört eine Prüfdatei. Damit kannst du vor dem Öffnen bestätigen, dass der Download unverändert ist.",
    "Need help?": "Brauchst du Hilfe?",
    "Email Y. A. Diab at": "Schreibe Y. A. Diab an",

    "A free, adjustable Pomodoro timer from DayVector that remembers the current session and settings locally in your browser.":
      "Ein kostenloser, anpassbarer Pomodoro-Timer von DayVector, der Sitzung und Einstellungen lokal in deinem Browser speichert.",
    "Free Pomodoro Timer from DayVector":
      "Kostenloser Pomodoro-Timer von DayVector",
    "Run an adjustable focus timer that resumes where you left off, with an accessible guide to the Pomodoro Technique.":
      "Nutze einen anpassbaren Fokustimer, der dort weitermacht, wo du aufgehört hast, samt verständlicher Einführung in die Pomodoro-Technik.",
    Timer: "Timer",
    "How to use it": "So nutzt du ihn",
    "Android widget": "Android-Widget",
    "Free, private and ready without an account":
      "Kostenlos, privat und ohne Konto startklar",
    "Make the next": "Mach aus den nächsten",
    "25 minutes": "25 Minuten",
    "count.": "echten Fortschritt.",
    "Pick one meaningful task, focus for a bounded interval and take a real break. This timer remembers your session in this browser, even when you close the tab.":
      "Wähle eine sinnvolle Aufgabe, konzentriere dich für einen klaren Zeitraum und mach danach eine echte Pause. Der Timer merkt sich deine Sitzung in diesem Browser, auch wenn du den Tab schließt.",
    "Timer capabilities": "Funktionen des Timers",
    "Remembers your timer on this device":
      "Merkt sich deinen Timer auf diesem Gerät",
    "Adjustable intervals": "Anpassbare Zeiträume",
    "Responsive everywhere": "Auf jedem Gerät passend",
    "What is the Pomodoro Technique?": "Was ist die Pomodoro-Technik?",
    "History, practical guidance and research context":
      "Geschichte, praktische Tipps und Forschung",
    "Your focus space": "Dein Fokusbereich",
    "Browser Pomodoro": "Browser-Pomodoro",
    "Saved only in this browser": "Nur in diesem Browser gespeichert",
    "Saved locally": "Lokal gespeichert",
    "Local saving unavailable": "Lokales Speichern ist nicht verfügbar",
    "What are you moving forward?": "Woran möchtest du weiterarbeiten?",
    "e.g. Review chapter 4": "z. B. Kapitel 4 wiederholen",
    "Choose timer phase": "Timer-Phase auswählen",
    "Short break": "Kurze Pause",
    "Long break": "Lange Pause",
    "Pomodoro controls": "Pomodoro-Steuerung",
    Reset: "Zurücksetzen",
    "Start focus": "Fokus starten",
    "Start break": "Pause starten",
    Skip: "Überspringen",
    "Ready when you are. Your progress stays on this device.":
      "Du kannst starten. Dein Fortschritt bleibt auf diesem Gerät.",
    "Focus is running. Keep this interval for one clear task.":
      "Der Fokus läuft. Nutze diesen Zeitraum für eine klare Aufgabe.",
    "Break is running. Step away from the task if you can.":
      "Die Pause läuft. Löse dich nach Möglichkeit kurz von der Aufgabe.",
    "Break complete. Your next focus is ready.":
      "Die Pause ist vorbei. Dein nächster Fokus ist bereit.",
    "Focus complete. Take a deliberate break.":
      "Fokus abgeschlossen. Mach jetzt bewusst Pause.",
    "Adjust timer": "Timer anpassen",
    "Focus minutes": "Fokusminuten",
    "Focuses per round": "Fokusphasen pro Runde",
    "Start breaks automatically": "Pausen automatisch starten",
    "Start the next focus automatically": "Nächsten Fokus automatisch starten",
    "Play a gentle completion tone": "Sanften Ton am Ende abspielen",
    "Restore recommended times": "Empfohlene Zeiten wiederherstellen",
    "Your timer stays on this device and is ready when you return. Nothing is sent to DayVector.":
      "Dein Timer bleibt auf diesem Gerät und ist bei deiner Rückkehr bereit. Nichts wird an DayVector gesendet.",
    "A gentle starting ritual": "Ein ruhiger Einstieg",
    "Use the interval to protect attention, not to race the clock":
      "Nutze den Zeitraum, um deine Aufmerksamkeit zu schützen",
    "The familiar 25-minute timer is a useful entry point. The complete technique also includes planning, handling interruptions, recording effort and learning from each cycle.":
      "Der bekannte 25-Minuten-Timer ist ein guter Einstieg. Zur vollständigen Technik gehören auch Planung, der Umgang mit Unterbrechungen, das Erfassen des Aufwands und das Lernen aus jedem Zyklus.",
    "Choose one clear outcome": "Wähle ein klares Ergebnis",
    "Write a task small enough to move during one focused interval.":
      "Formuliere eine Aufgabe, die in einem Fokuszeitraum spürbar vorankommen kann.",
    "Start and protect the interval": "Starte und schütze den Zeitraum",
    "Put avoidable distractions aside; note interruptions instead of chasing them.":
      "Lege vermeidbare Ablenkungen beiseite und notiere Unterbrechungen, statt ihnen zu folgen.",
    "Stop when the timer ends": "Hör auf, wenn der Timer endet",
    "Take the break seriously. Stand, breathe, drink water or let your attention reset.":
      "Nimm die Pause ernst. Steh auf, atme durch, trink Wasser oder lass deine Aufmerksamkeit zur Ruhe kommen.",
    "Review, then begin again": "Kurz prüfen und neu beginnen",
    "After several focuses, take a longer break and adjust the durations to fit your work.":
      "Mach nach mehreren Fokusphasen eine längere Pause und passe die Zeiten an deine Arbeit an.",
    "Go deeper into learning": "Noch besser lernen",
    "A useful companion:": "Eine hilfreiche Ergänzung:",
    "Barbara Oakley’s book explains practical approaches to learning difficult material, overcoming procrastination and moving between focused and more diffuse modes of thinking. Its strategies apply beyond mathematics and science.":
      "Barbara Oakleys Buch zeigt praktische Wege, schwierige Inhalte zu lernen, Aufschieben zu überwinden und zwischen fokussiertem und offenem Denken zu wechseln. Die Strategien helfen weit über Mathematik und Naturwissenschaften hinaus.",
    "Read about the book": "Mehr über das Buch erfahren",
    "Product website": "Produktwebsite",
    Terms: "Bedingungen",
    "A practical introduction": "Eine verständliche Einführung",
    "The idea behind the Pomodoro Technique":
      "Die Idee hinter der Pomodoro-Technik",
    "Close Pomodoro information": "Pomodoro-Informationen schließen",
    "Who created it?": "Wer hat sie entwickelt?",
    "Francesco Cirillo created the technique while he was a university student in the late 1980s, using a tomato-shaped kitchen timer. The name comes from the Italian word for tomato. Cirillo emphasizes that the timer is only one part of a broader system for planning, managing interruptions, estimating effort and improving how you work.":
      "Francesco Cirillo entwickelte die Technik Ende der 1980er-Jahre als Student mit einem tomatenförmigen Küchentimer. Der Name stammt vom italienischen Wort für Tomate. Cirillo betont, dass der Timer nur ein Teil eines umfassenderen Systems für Planung, Unterbrechungen, Aufwandsschätzung und bessere Arbeitsabläufe ist.",
    "How can a timer help?": "Wie kann ein Timer helfen?",
    "A bounded interval can lower the barrier to starting, make interruptions visible and create a deliberate stopping point. Research by Atsunori Ariga and Alejandro Lleras found that brief, rare breaks helped prevent a decline in performance during a sustained-attention task. That does not make one duration perfect for everyone. Adjust the timer to the work and to your needs.":
      "Ein klar begrenzter Zeitraum kann den Einstieg erleichtern, Unterbrechungen sichtbar machen und einen bewussten Endpunkt schaffen. Eine Studie von Atsunori Ariga und Alejandro Lleras zeigte, dass kurze, seltene Pausen einem Leistungsabfall bei anhaltender Aufmerksamkeit entgegenwirkten. Trotzdem passt nicht dieselbe Dauer zu allen. Stelle den Timer passend zu deiner Arbeit und deinen Bedürfnissen ein.",
    "A simple first cycle": "Ein einfacher erster Zyklus",
    "Choose one task and define what “moved forward” will mean.":
      "Wähle eine Aufgabe und lege fest, was Fortschritt dabei bedeutet.",
    "Focus for 25 minutes, recording interruptions instead of following them.":
      "Arbeite 25 Minuten fokussiert und notiere Unterbrechungen, statt ihnen zu folgen.",
    "Stop and take a short break when the interval ends.":
      "Hör am Ende des Zeitraums auf und mach eine kurze Pause.",
    "After four focus intervals, take a longer break and review the pattern.":
      "Mach nach vier Fokusphasen eine längere Pause und schau dir das Muster an.",
    "The timer is a tool, not a score. Even the creator cautions against reducing the full technique to collecting as many 25-minute intervals as possible.":
      "Der Timer ist ein Werkzeug und keine Punktzahl. Auch der Entwickler der Technik warnt davor, sie auf das Sammeln möglichst vieler 25-Minuten-Phasen zu reduzieren.",
    "Sources and further reading": "Quellen und weitere Informationen",
    "Francesco Cirillo: creator’s account and philosophy":
      "Francesco Cirillo: seine Darstellung und Philosophie",
    "Official Pomodoro Technique overview":
      "Offizielle Übersicht zur Pomodoro-Technik",
    "Ariga & Lleras (2011),": "Ariga und Lleras (2011),",
    ": brief mental breaks and vigilance":
      ": kurze mentale Pausen und Aufmerksamkeit",
    "Barbara Oakley:": "Barbara Oakley:",
    "Pomodoro® is a registered trademark of Francesco Cirillo. This independent educational timer is not affiliated with or endorsed by Francesco Cirillo.":
      "Pomodoro® ist eine eingetragene Marke von Francesco Cirillo. Dieser unabhängige Lern-Timer steht in keiner Verbindung zu Francesco Cirillo und wird nicht von ihm unterstützt.",
    "Start a focus interval": "Fokusphase starten",
    "The same live session as the app":
      "Die gleiche Live-Sitzung wie in der App",
    "Health context without clutter":
      "Gesundheit im Blick, ganz ohne Unordnung",
    "See movement and recovery beside your work":
      "Bewegung und Erholung im Zusammenhang mit deiner Arbeit",
    "With your permission, DayVector reads the health summaries you choose to share and presents them in a calm daily view. It helps you notice when movement, rest and focused work are supporting each other.":
      "Mit deiner Erlaubnis liest DayVector die Gesundheitsübersichten, die du teilen möchtest, und zeigt sie in einer ruhigen Tagesansicht. So erkennst du leichter, wie Bewegung, Erholung und konzentrierte Arbeit zusammenspielen.",
    "A clear view of today": "Ein klarer Blick auf heute",
    "Steps, distance, active energy and workouts at a glance":
      "Schritte, Strecke, Aktivkalorien und Training auf einen Blick",
    "Your week in motion": "Deine Woche in Bewegung",
    "Readable values and a simple seven-day movement chart":
      "Gut lesbare Werte und ein einfacher Bewegungsverlauf über sieben Tage",
    "Health sources together": "Alle Gesundheitsquellen an einem Ort",
    "Connected watches and health applications in one tidy place":
      "Verbundene Uhren und Gesundheits-Apps übersichtlich zusammengefasst",
    "Useful on Windows too": "Auch unter Windows hilfreich",
    "Daily summaries stay readable across your signed-in devices":
      "Tagesübersichten bleiben auf deinen angemeldeten Geräten gut lesbar",
    "Swipe down to refresh": "Zum Aktualisieren nach unten wischen",
    "Read-only access": "Nur Lesezugriff",
    "Captured from the Android app": "Direkt aus der Android-App aufgenommen",
    "DayVector Health dashboard showing today's steps, distance, active energy and a seven-day movement chart":
      "DayVector-Gesundheitsübersicht mit heutigen Schritten, Strecke, Aktivkalorien und einem Bewegungsverlauf über sieben Tage",
    "Time does not always follow the schedule. DayVector keeps each activity period available for review and makes sure the same minute is never counted twice":
      "Der Tag läuft nicht immer nach Plan. DayVector hält jeden Aktivitätszeitraum zur Prüfung bereit und sorgt dafür, dass dieselbe Minute nie doppelt gezählt wird.",
    "Project task": "Projektaufgabe",
    "Prepare product launch": "Produkteinführung vorbereiten",
  };

  const arabic = {
    "DayVector turns direction into daily progress with task planning, roadmaps, focus timers, activity insights and evidence-based coaching on Windows and Android.":
      "يحوّل DayVector اتجاهك إلى تقدّم يومي من خلال تخطيط المهام وخرائط الطريق ومؤقتات التركيز ورؤى النشاط والإرشاد المبني على أدلة على Windows وAndroid.",
    "DayVector — Turn direction into daily progress":
      "DayVector — حوّل اتجاهك إلى تقدّم يومي",
    "Plan meaningful goals, focus on the next task and improve with evidence-based coaching across Windows and Android.":
      "خطط لأهداف ذات معنى، وركّز على المهمة التالية، وتطوّر بإرشاد مبني على أدلة على Windows وAndroid.",
    "Personal planning, focused execution and evidence-based coaching on Windows and Android.":
      "تخطيط شخصي وتنفيذ مركّز وإرشاد مبني على أدلة على Windows وAndroid.",
    "DayVector — Planning, Focus Timers, Roadmaps and Coaching":
      "DayVector — التخطيط ومؤقتات التركيز وخرائط الطريق والإرشاد",
    "DayVector turns goals into roadmaps, recurring tasks and daily actions, measures real effort and provides explainable coaching across Windows and Android.":
      "يحوّل DayVector الأهداف إلى خرائط طريق ومهام متكررة وخطوات يومية، ويقيس الجهد الفعلي ويقدم إرشاداً واضحاً على Windows وAndroid.",
    "DayVector: Plan, Focus and Improve":
      "DayVector: التخطيط والتركيز والتحسين",
    "Create roadmaps, execute focused tasks, track real activity and improve through evidence-based coaching.":
      "أنشئ خرائط طريق، وقم بتنفيذ المهام المركزة، وتتبع النشاط الحقيقي، وقم بالتحسين من خلال التدريب المبني على الأدلة.",
    "DayVector: Planning, Focus and Personal Coaching":
      "DayVector: التخطيط والتركيز والتدريب الشخصي",
    "Skip to main content": "انتقل إلى المحتوى الرئيسي",
    "Skip to timer": "انتقل إلى الموقت",
    "DayVector home": "DayVector الصفحة الرئيسية",
    "Open navigation": "افتح التنقل",
    "Close navigation": "إغلاق التنقل",
    "Main navigation": "الملاحة الرئيسية",
    "Pomodoro page navigation": "الملاحة صفحة بومودورو",
    Features: "سمات",
    "How It Works": "كيف يعمل",
    Roadmaps: "خرائط الطريق",
    Widget: "أداة الشاشة الرئيسية",
    Coaching: "التدريب",
    Pomodoro: "بومودورو",
    Privacy: "خصوصية",
    Contact: "اتصال",
    Download: "تحميل",
    "Download App": "تحميل التطبيق",
    "Download app": "تنزيل التطبيق",
    "Turn direction into daily progress":
      "حوّل اتجاهك إلى تقدّم يومي",
    "Plan your goals": "خطط لأهدافك",
    "Execute your tasks": "أنجز مهامك",
    "Improve every day": "تقدّم كل يوم",
    "DayVector combines task management, structured roadmaps, time tracking and personalized coaching to help you organize your responsibilities, improve your habits and make better use of your time":
      "يجمع DayVector بين إدارة المهام وخرائط الطريق المنظمة وتتبع الوقت والتدريب الشخصي لمساعدتك على تنظيم مسؤولياتك وتحسين عاداتك والاستفادة بشكل أفضل من وقتك.",
    "It connects planned work with real activity, credits useful effort to the task it supports and turns verified patterns into clear recommendations":
      "فهو يربط العمل المخطط له بالنشاط الحقيقي، وينسب الجهد المفيد إلى المهمة التي يدعمها، ويحول الأنماط التي تم التحقق منها إلى توصيات واضحة",
    "Download for Windows": "تحميل لنظام التشغيل ويندوز",
    "Download for Android": "تنزيل لأجهزة أندرويد",
    "Explore how it works": "اكتشف كيف يعمل",
    "Supported platforms and capabilities": "المنصات والقدرات المدعومة",
    "DayVector dashboard showing task suggestions, today's schedule, workload and overdue work":
      "لوحة DayVector تعرض اقتراحات المهام وجدول اليوم وعبء العمل والمهام المتأخرة",
    Windows: "ويندوز",
    "Android phones": "هواتف أندرويد",
    "Android tablets": "أقراص أندرويد",
    "Offline capable": "غير متصل قادر",
    "Cross-device synchronization": "المزامنة عبر الأجهزة",
    Today: "اليوم",
    "6 tasks complete": "6 مهام كاملة",
    Focus: "ركز",
    "2h 41m active": "2 ساعة 41 دقيقة نشط",
    Roadmap: "خريطة الطريق",
    "68% complete": "68% كاملة",
    "One connected system": "نظام واحد متصل",
    "One application for planning, execution, progress and improvement":
      "تطبيق واحد للتخطيط والتنفيذ والتقدم والتحسين",
    "DayVector connects what you plan with what you actually do. It measures real effort, recognizes useful work, identifies delays and helps you improve your future schedule":
      "يربط DayVector ما تخطط له بما تفعله بالفعل. فهو يقيس الجهد الحقيقي، ويتعرف على العمل المفيد، ويحدد التأخيرات، ويساعدك على تحسين جدولك المستقبلي",
    "Feature status legend": "أسطورة حالة الميزة",
    Available: "متاح",
    Beta: "بيتا",
    Planned: "المخطط لها",
    "Built for meaningful progress": "بنيت لتحقيق تقدم ملموس",
    "Everything you need to turn plans into progress":
      "كل ما تحتاجه لتحويل الخطط إلى تقدم",
    "Long-term direction, daily responsibilities, real execution data and personalized guidance come together inside one calm workspace":
      "يجتمع التوجيه طويل المدى والمسؤوليات اليومية وبيانات التنفيذ الحقيقية والتوجيه الشخصي معًا في مساحة عمل واحدة هادئة",
    "Turn large goals into clear phases":
      "تحويل الأهداف الكبيرة إلى مراحل واضحة",
    "Create roadmaps with phases, milestones, checkpoints, recurring work, practice targets and completion requirements":
      "قم بإنشاء خرائط طريق تحتوي على المراحل والمعالم ونقاط التفتيش والعمل المتكرر وأهداف الممارسة ومتطلبات الإنجاز",
    "Choose the right next action": "اختر الإجراء التالي الصحيح",
    "Bring priority, deadlines, available time, dependencies and roadmap importance into one practical recommendation":
      "اجمع الأولوية والمواعيد النهائية والوقت المتاح والتبعيات وأهمية خريطة الطريق في توصية عملية واحدة",
    "Understand how your time is used": "افهم كيف يتم استخدام وقتك",
    "Track focused work, continuous sessions, pauses, idle periods, interruptions and the difference between planned and actual effort":
      "تتبع العمل المركز والجلسات المستمرة وفترات التوقف المؤقت وفترات الخمول والانقطاعات والفرق بين الجهد المخطط والفعلي",
    "Useful work is never lost": "العمل المفيد لا يضيع أبدا",
    "Review activity from breaks or other sessions and credit approved effort to the task and roadmap it truly supported":
      "قم بمراجعة النشاط من فترات الراحة أو الجلسات الأخرى ونسب الجهد المعتمد إلى المهمة وخريطة الطريق التي يدعمها بالفعل",
    "Roadmaps adapt to real performance":
      "تتكيف خرائط الطريق مع الأداء الحقيقي",
    "Forecasts respond to actual effort, postponed work, missed sessions, confirmed progress and available capacity":
      "تستجيب التوقعات للجهد الفعلي والعمل المؤجل والجلسات الفائتة والتقدم المؤكد والقدرة المتاحة",
    "Get a helpful next step": "احصل على خطوة تالية مفيدة",
    "Coaching uses today’s schedule, paused work, roadmap priorities and your preferences to offer a respectful next action":
      "يستخدم التدريب جدول اليوم والعمل المتوقف مؤقتًا وأولويات خريطة الطريق وتفضيلاتك لتقديم الإجراء التالي المحترم",
    "A practical loop": "حلقة عملية",
    "From a long-term goal to today’s next action":
      "من هدف طويل المدى إلى الإجراء التالي اليوم",
    "Define your goal": "حدد هدفك",
    "Create a personal, professional, learning, health or habit goal":
      "قم بإنشاء هدف شخصي أو مهني أو تعليمي أو صحي أو عادة",
    "Reach German B1": "الوصول إلى المستوى الألماني B1",
    "Build the roadmap": "بناء خارطة الطريق",
    "Divide the goal into phases, milestones, checkpoints and practical recurring tasks":
      "قسم الهدف إلى مراحل ومعالم ونقاط تفتيش ومهام عملية متكررة",
    "Execute the work": "تنفيذ العمل",
    "Match each responsibility with focused sessions, continuous timers, checklists, reading or manual completion":
      "قم بمطابقة كل مسؤولية مع الجلسات المركزة أو الموقتات المستمرة أو قوائم المراجعة أو القراءة أو الإكمال اليدوي",
    "Learn and improve": "تعلم وتحسين",
    "Compare the plan with actual performance and use evidence to shape the next one":
      "قارن الخطة بالأداء الفعلي واستخدم الأدلة لتشكيل الخطة التالية",
    "Roadmap workspace": "مساحة عمل خارطة الطريق",
    "DayVector roadmap displaying phases, checkpoints and progress forecasts":
      "تعرض خريطة طريق DayVector المراحل ونقاط التفتيش وتوقعات التقدم",
    "Build a realistic path toward every goal": "بناء مسار واقعي نحو كل هدف",
    "Roadmaps turn long-term direction into measurable phases and responsibilities. Every item remains editable and every percentage has an explanation":
      "وتحول خرائط الطريق الاتجاه طويل المدى إلى مراحل ومسؤوليات قابلة للقياس. يظل كل عنصر قابلاً للتحرير وكل نسبة مئوية لها تفسير",
    "Editable phases": "مراحل قابلة للتحرير",
    "Target dates": "التواريخ المستهدفة",
    "Recurring tasks": "المهام المتكررة",
    Milestones: "المعالم",
    Checkpoints: "نقاط التفتيش",
    "Required effort": "الجهد المطلوب",
    "Forecast completion": "اكتمال التنبؤ",
    "Risk warnings": "تحذيرات المخاطر",
    "Forecast example": "مثال التوقعات",
    "The expected phase completion moved by four days because three tasks required more time and two sessions were postponed":
      "تم تأجيل اكتمال المرحلة المتوقعة بمقدار أربعة أيام لأن ثلاث مهام تطلبت وقتًا أطول وتم تأجيل جلستين",
    Confidence: "ثقة",
    Medium: "واسطة",
    Evidence: "شهادة",
    "11 comparable sessions": "11 جلسة قابلة للمقارنة",
    "Flexible execution": "تنفيذ مرن",
    "Different responsibilities need different methods":
      "المسؤوليات المختلفة تحتاج إلى أساليب مختلفة",
    "DayVector is designed to match the work rather than forcing every activity into the same timer":
      "تم تصميم DayVector ليتناسب مع العمل بدلاً من فرض كل نشاط في نفس المؤقت",
    "Pomodoro Focus": "تركيز بومودورو",
    "Focus cycles, breaks, pauses and interruptions":
      "دورات التركيز والفواصل والتوقفات والانقطاعات",
    "Try the free browser timer": "جرب مؤقت المتصفح المجاني",
    "Continuous Timer": "الموقت المستمر",
    "Long work blocks, active time and overtime":
      "كتل العمل الطويلة والوقت النشط والعمل الإضافي",
    Checklist: "قائمة التحقق",
    "Required items, priorities and completion rules":
      "العناصر المطلوبة والأولويات وقواعد الإنجاز",
    Reading: "قراءة",
    "Books, PDFs, duration, saved position and notes":
      "الكتب وملفات PDF والمدة والموضع المحفوظ والملاحظات",
    Habit: "عادة",
    "Streaks, completion rate, recovery and timing":
      "الخطوط ومعدل الإنجاز والانتعاش والتوقيت",
    Event: "حدث",
    "Arrival, duration, lateness and follow-up work":
      "الوصول والمدة والتأخير ومتابعة العمل",
    Hybrid: "هجين",
    "Combine timers, checklists, checkpoints and resources":
      "الجمع بين الموقتات وقوائم المراجعة ونقاط التفتيش والموارد",
    "Focus from your home screen": "التركيز من شاشتك الرئيسية",
    "Your running session stays visible and controllable":
      "تظل جلسة التشغيل الخاصة بك مرئية ويمكن التحكم فيها",
    "The responsive Android widget reflects the current DayVector session. See the remaining time at a glance, pause without opening the app, move to a break or finish when the work is complete.":
      "تعكس أداة Android سريعة الاستجابة جلسة DayVector الحالية. يمكنك الاطلاع على الوقت المتبقي في لمحة سريعة، أو التوقف مؤقتًا دون فتح التطبيق، أو الانتقال إلى فترة راحة أو الانتهاء عند اكتمال العمل.",
    "Live focus and break countdowns": "التركيز المباشر وكسر العد التنازلي",
    "Pause, break and finish controls": "ضوابط الإيقاف المؤقت والكسر والانتهاء",
    "Compact, medium and expanded sizes": "أحجام مدمجة ومتوسطة وموسعة",
    "Canonical state shared with the app":
      "تمت مشاركة الحالة الأساسية مع التطبيق",
    "Try the browser Pomodoro": "جرب متصفح بومودورو",
    "Get the Android widget": "احصل على أداة Android",
    "Live DayVector Android widget demonstration":
      "العرض المباشر لأداة DayVector Android",
    "Interactive widget preview controls":
      "عناصر التحكم في معاينة أداة الشاشة الرئيسية",
    "FOCUS SESSION": "جلسة التركيز",
    "Focus session": "جلسة التركيز",
    "RECOVERY BREAK": "استراحة للتعافي",
    "Recovery break": "انقطاع الانتعاش",
    "Deep work session": "جلسة عمل عميقة",
    "Time to recharge": "الوقت لإعادة الشحن",
    Pause: "يوقف",
    Resume: "سيرة ذاتية",
    Break: "استراحة",
    Finish: "ينهي",
    "A real live preview with working countdown and controls":
      "معاينة حية حقيقية مع العد التنازلي وعناصر التحكم",
    "Cross-task attribution": "الإسناد عبر المهام",
    "Useful activity belongs to the task it actually supports":
      "النشاط المفيد ينتمي إلى المهمة التي يدعمها بالفعل",
    "Time does not always follow the schedule. The contribution engine retains raw activity, requests approval when needed and avoids counting the same physical minute twice":
      "الوقت لا يتبع الجدول الزمني دائمًا. يحتفظ محرك المساهمة بالنشاط الأولي، ويطلب الموافقة عند الحاجة ويتجنب حساب نفس الدقيقة الفعلية مرتين",
    "Current session": "الجلسة الحالية",
    "Programming task": "مهمة البرمجة",
    "Five-minute Pomodoro break": "استراحة بومودورو لمدة خمس دقائق",
    "Detected activity": "النشاط الذي تم اكتشافه",
    "German learning app": "تطبيق تعلم اللغة الألمانية",
    "4 minutes 12 seconds": "4 دقائق و12 ثانية",
    "Approved result": "النتيجة المعتمدة",
    "German daily practice": "الممارسة اليومية الألمانية",
    "German B1 roadmap updated": "تم تحديث خريطة الطريق الألمانية B1",
    "Physical timeline": "الجدول الزمني المادي",
    "Approved practice": "الممارسة المعتمدة",
    "Duplicated time": "الوقت مكرر",
    "Unknown and idle-looking activity stays available for review":
      "يظل النشاط غير المعروف والخمول متاحًا للمراجعة",
    "Were you reading, working away from the computer, helping another task or simply taking a break? Your answer can improve future suggestions":
      "هل كنت تقرأ، أو تعمل بعيدًا عن الكمبيوتر، أو تساعد في مهمة أخرى، أو ببساطة تأخذ قسطًا من الراحة؟ إجابتك يمكن أن تحسن الاقتراحات المستقبلية",
    "Activity insights": "رؤى النشاط",
    "Understand which tools help you perform":
      "فهم الأدوات التي تساعدك على الأداء",
    "Compare the applications and websites expected for a task with the tools that were actually used, then correct classifications at any time":
      "مقارنة التطبيقات والمواقع المتوقعة لمهمة ما بالأدوات المستخدمة فعلياً، ثم تصحيح التصنيفات في أي وقت",
    "Visual Studio Code supported most of this development session":
      "دعم Visual Studio Code معظم جلسة التطوير هذه",
    "The browser was used mainly for documentation research":
      "تم استخدام المتصفح بشكل أساسي لأبحاث التوثيق",
    "One recurring application still needs a task assignment":
      "لا يزال أحد التطبيقات المتكررة يحتاج إلى تعيين مهمة",
    "Application report": "تقرير التطبيق",
    "Build synchronization engine": "بناء محرك التزامن",
    "Primary application": "التطبيق الأساسي",
    Productive: "منتجة",
    "Web browser": "متصفح الويب",
    "28 minutes": "28 دقيقة",
    Research: "بحث",
    Email: "بريد إلكتروني",
    "11 minutes": "11 دقيقة",
    Communication: "تواصل",
    "Video platform": "منصة الفيديو",
    "14 minutes": "14 دقيقة",
    "Needs review": "يحتاج إلى مراجعة",
    "Personal coaching": "التدريب الشخصي",
    "Coaching based on your actual behavior": "التدريب على أساس سلوكك الفعلي",
    "Friendly suggestions use today’s schedule, active or paused work, roadmap priorities and your coaching preferences. You remain in control":
      "تستخدم الاقتراحات الودية جدول اليوم والعمل النشط أو المتوقف مؤقتًا وأولويات خريطة الطريق وتفضيلات التدريب الخاصة بك. ستظل مسيطرًا",
    "Start delays": "بدء التأخير",
    Workload: "عبء العمل",
    "Roadmap risk": "مخاطر خارطة الطريق",
    "Break quality": "كسر الجودة",
    Distraction: "إلهاء",
    "Micro-sessions": "الجلسات الدقيقة",
    "Coaching insight": "البصيرة التدريب",
    "Start with less friction": "ابدأ بإحتكاك أقل",
    "High confidence": "ثقة عالية",
    "Your Work tasks usually begin": "تبدأ مهام عملك عادة",
    "17 minutes late": "متأخرا 17 دقيقة",
    "This recommendation is based on your previous 12 Work sessions":
      "تستند هذه التوصية إلى جلسات العمل الـ 12 السابقة",
    "Suggested action": "الإجراء المقترح",
    "Move the preparation reminder 10 minutes earlier":
      "قم بتحريك تذكير التحضير قبل 10 دقائق",
    "Apply suggestion": "تطبيق الاقتراح",
    Helpful: "متعاون",
    "Not helpful": "غير مفيد",
    "Wrong time": "وقت خاطئ",
    "Current focus": "التركيز الحالي",
    "Start on Windows. Continue on Android":
      "ابدأ على نظام التشغيل Windows. المتابعة على Android",
    "Start, pause or resume the same task from Windows or Android. Tasks, roadmaps, settings and approved work stay consistent when devices are online":
      "ابدأ نفس المهمة أو أوقفها مؤقتًا أو استأنفها من Windows أو Android. تظل المهام وخرائط الطريق والإعدادات والعمل المعتمد متسقة عندما تكون الأجهزة متصلة بالإنترنت",
    "Start on Windows": "ابدأ على نظام التشغيل Windows",
    "View on Android": "عرض على أندرويد",
    "Continue on Windows": "المتابعة على نظام التشغيل Windows",
    "Immediate local button response": "استجابة زر محلية فورية",
    "Local timer calculation": "حساب الموقت المحلي",
    "Duplicate-command protection": "حماية الأوامر المكررة",
    "One shared active task and session state":
      "مهمة نشطة مشتركة وحالة جلسة واحدة",
    "Offline operation": "عملية دون اتصال",
    "Your work does not stop when the internet does":
      "عملك لا يتوقف عندما يتوقف الإنترنت",
    "Create tasks, update roadmaps and keep working without a connection. Saved changes synchronize safely when your device reconnects":
      "قم بإنشاء المهام وتحديث خرائط الطريق ومواصلة العمل دون اتصال. تتم مزامنة التغييرات المحفوظة بأمان عند إعادة توصيل جهازك",
    Offline: "غير متصل",
    "3 changes waiting safely": "3 تغييرات تنتظر بأمان",
    Connected: "متصل",
    "All changes synchronized": "تمت مزامنة كافة التغييرات",
    "Privacy and control": "الخصوصية والتحكم",
    "Detailed insights under your control": "رؤى تفصيلية تحت سيطرتك",
    "You choose which activity DayVector may record and whether selected data remains local or is synchronized":
      "يمكنك اختيار النشاط الذي قد يسجله DayVector وما إذا كانت البيانات المحددة تظل محلية أو متزامنة",
    "DayVector does not upload browser cookies, website login tokens, clipboard contents, form contents or unencrypted passwords":
      "لا يقوم DayVector بتحميل ملفات تعريف الارتباط للمتصفح أو الرموز المميزة لتسجيل الدخول إلى موقع الويب أو محتويات الحافظة أو محتويات النموذج أو كلمات المرور غير المشفرة",
    "View Privacy Policy": "عرض سياسة الخصوصية",
    "View Terms of Use": "عرض شروط الاستخدام",
    "Activity privacy": "خصوصية النشاط",
    "Your choices": "اختياراتك",
    "Track applications": "تتبع التطبيقات",
    "Track window titles": "تتبع عناوين النوافذ",
    "Track domains only": "تتبع المجالات فقط",
    "Track full URLs": "تتبع عناوين URL الكاملة",
    "Keep selected history local": "احتفظ بالتاريخ المحدد محليًا",
    "Pause tracking": "وقفة التتبع",
    "Delete activity history": "حذف سجل النشاط",
    Review: "مراجعة",
    "The operational view": "النظرة التشغيلية",
    "Everything important, visible in one place":
      "كل شيء مهم، مرئي في مكان واحد",
    "DayVector dashboard showing task suggestions, schedule, workload and overdue responsibilities":
      "لوحة DayVector تعرض اقتراحات المهام والجدول وعبء العمل والمسؤوليات المتأخرة",
    "Today’s responsibilities, active work, roadmap progress, unresolved activity and coaching direction in one focused dashboard":
      "مسؤوليات اليوم، والعمل النشط، والتقدم في خريطة الطريق، والأنشطة التي لم يتم حلها، وتوجيهات التدريب في لوحة تحكم واحدة مركزة",
    "Task suggestions": "اقتراحات المهام",
    "Today's workload": "عبء عمل اليوم",
    Schedule: "الجدول",
    "Clear current task state": "حالة المهمة الحالية بوضوح",
    "Next suggested responsibility": "المهمة التالية المقترحة",
    "Today’s schedule and workload": "جدول اليوم وحجم العمل",
    "Overdue work and items needing attention":
      "المهام المتأخرة وما يحتاج إلى انتباهك",
    "Dynamic coaching and synchronization status":
      "إرشاد متجدد وحالة المزامنة",
    "Dynamic coaching": "إرشاد متجدد",
    "DayVector coaching carousel with several evidence-based suggestions":
      "بطاقات إرشاد متحركة في DayVector تعرض عدة اقتراحات مبنية على نشاطك",
    "Several suggestions, always in your control":
      "عدة اقتراحات مع بقاء القرار بيدك",
    "Activity insights": "رؤى النشاط",
    "DayVector Activity view grouping useful application time without losing individual periods":
      "صفحة نشاط DayVector تجمع وقت التطبيقات المفيد مع الحفاظ على كل فترة منفصلة",
    "Clear, editable classifications": "تصنيفات واضحة وقابلة للتعديل",
    "Direct contact": "الاتصال المباشر",
    "Questions, feedback or support?": "أسئلة أو تعليقات أو دعم؟",
    "Contact the creator of DayVector for help with the app, privacy questions, feedback, bug reports, feature suggestions or general enquiries":
      "اتصل بمنشئ DayVector للحصول على مساعدة بشأن التطبيق أو أسئلة الخصوصية أو التعليقات أو تقارير الأخطاء أو اقتراحات الميزات أو الاستفسارات العامة",
    "Created and maintained by": "تم إنشاؤها وصيانتها بواسطة",
    "Contact Y. A. Diab": "للتواصل مع ياسر دياب",
    "Email Y. A. Diab about DayVector":
      "أرسل بريدًا إلكترونيًا إلى ياسر دياب بخصوص DayVector",
    "Application support": "دعم التطبيق",
    "Privacy questions": "أسئلة الخصوصية",
    "Bug reports": "تقارير الأخطاء",
    "Feature suggestions": "اقتراحات الميزات",
    "Build a better system for your time": "بناء نظام أفضل لوقتك",
    "Download DayVector and begin turning long-term goals into practical, measurable daily progress":
      "قم بتنزيل DayVector وابدأ في تحويل الأهداف طويلة المدى إلى تقدم يومي عملي وقابل للقياس",
    "Recommended for your device": "الموصى بها لجهازك",
    "DayVector for Windows": "برنامج DayVector لنظام التشغيل Windows",
    "Designed for Windows 10 and Windows 11":
      "مصمم لنظامي التشغيل Windows 10 وWindows 11",
    Version: "إصدار",
    Installer: "المثبت",
    "64-bit EXE": "64 بت إي إكس إي",
    Size: "مقاس",
    "Shown on GitHub": "يظهر على جيثب",
    "Checking release…": "جارٍ التحقق من الإصدار…",
    "Release notes": "ملاحظات الإصدار",
    "Installation help": "مساعدة التثبيت",
    "DayVector for Android": "برنامج DayVector للاندرويد",
    "Designed for Android phones and tablets": "مصممة للهواتف أندرويد وأقراص",
    Package: "طَرد",
    "Signed APK": "APK الموقعة",
    "A personal planning, execution and performance-coaching system for Windows and Android":
      "نظام التخطيط الشخصي والتنفيذ والتدريب على الأداء لنظامي التشغيل Windows وAndroid",
    Product: "منتج",
    "Android Widget": "أداة الشاشة الرئيسية لأندرويد",
    "Free Pomodoro": "بومودورو مجاني",
    Legal: "قانوني",
    "Privacy Policy": "سياسة الخصوصية",
    "Terms of Use": "شروط الاستخدام",
    "Installation Help": "مساعدة التثبيت",
    "Support and feedback": "الدعم وردود الفعل",
    "Windows and Android": "ويندوز وأندرويد",
    "DayVector Release Notes": "ملاحظات إصدار DayVector",
    "Release date available with the notes": "تاريخ الإصدار متاح مع الملاحظات",
    "Close release notes": "إغلاق ملاحظات الإصدار",
    "Loading release notes…": "جارٍ تحميل ملاحظات الإصدار…",
    "Latest published release": "أحدث الاصدار المنشور",
    "Release notes are temporarily unavailable":
      "ملاحظات الإصدار غير متاحة مؤقتًا",
    "Try loading the notes again shortly.":
      "حاول تحميل الملاحظات مرة أخرى قريبًا.",
    "Try again": "حاول ثانية",
    Close: "يغلق",
    "Release date unavailable": "تاريخ الإصدار غير متوفر",
    "Size unavailable": "الحجم غير متوفر",
    "Coming soon!": "قريباً!",
    "Available with the release": "متوفر مع الإصدار",
    "Checking…": "جارٍ التحقق…",
    "Privacy Policy for DayVector":
      "سياسة الخصوصية لبرنامج DayVector",
    "Privacy choices and data-handling information for DayVector.":
      "خيارات الخصوصية ومعلومات التعامل مع البيانات لبرنامج DayVector.",
    "← Back to privacy overview": "← العودة إلى نظرة عامة على الخصوصية",
    "Privacy policy": "سياسة الخصوصية",
    "Your activity stays under your control": "يبقى نشاطك تحت سيطرتك",
    "Effective 25 July 2026": "اعتبارًا من 25 يوليو 2026",
    "DayVector is a planning, execution and performance-coaching application created and maintained by Y. A. Diab. This policy explains the categories of information the application may process and the choices available to you.":
      "DayVector هو تطبيق للتخطيط والتنفيذ والتدريب على الأداء تم إنشاؤه وصيانته بواسطة Y. A. Diab. تشرح هذه السياسة فئات المعلومات التي قد يعالجها التطبيق والخيارات المتاحة لك.",
    "Information you provide": "المعلومات التي تقدمها",
    "This may include account details, profile preferences, tasks, roadmaps, notes, reminders, resources and feedback. Authentication is provided through Supabase. Google sign-in, when selected, is processed by Google and Supabase.":
      "قد يتضمن ذلك تفاصيل الحساب وتفضيلات الملف الشخصي والمهام وخرائط الطريق والملاحظات والتذكيرات والموارد والتعليقات. يتم توفير المصادقة من خلال Supabase. تتم معالجة تسجيل الدخول إلى Google، عند تحديده، بواسطة Google وSupabase.",
    "Optional activity information": "معلومات النشاط الاختيارية",
    "With your permission, DayVector may process application usage, window titles, website domains or URLs, document activity, idle state and manually recorded off-device work. Controls in the application determine which categories are enabled and whether supported activity remains local or is synchronized.":
      "بعد الحصول على إذن منك، قد يقوم DayVector بمعالجة استخدام التطبيق، وعناوين النوافذ، ونطاقات موقع الويب أو عناوين URL، ونشاط المستند، وحالة الخمول، والعمل المسجل يدويًا خارج الجهاز. تحدد عناصر التحكم في التطبيق الفئات التي تم تمكينها وما إذا كان النشاط المدعوم يظل محليًا أو متزامنًا.",
    "Information DayVector does not upload":
      "لا يتم تحميل المعلومات DayVector",
    "The application is designed not to upload browser cookies, website login tokens, clipboard contents, form contents, banking-session information, email-session tokens or unencrypted passwords.":
      "تم تصميم التطبيق بحيث لا يقوم بتحميل ملفات تعريف الارتباط للمتصفح، أو الرموز المميزة لتسجيل الدخول إلى موقع الويب، أو محتويات الحافظة، أو محتويات النماذج، أو معلومات الجلسة المصرفية، أو الرموز المميزة لجلسة البريد الإلكتروني، أو كلمات المرور غير المشفرة.",
    "Why information is used": "لماذا يتم استخدام المعلومات",
    "Information is used to operate requested features, synchronize connected devices, calculate progress and reports, detect unresolved activity, improve schedules, deliver notifications and generate explainable coaching. Optional data is not treated as medical diagnosis.":
      "يتم استخدام المعلومات لتشغيل الميزات المطلوبة ومزامنة الأجهزة المتصلة وحساب التقدم والتقارير واكتشاف الأنشطة التي لم يتم حلها وتحسين الجداول الزمنية وتقديم الإشعارات وإنشاء تدريب قابل للتفسير. لا يتم التعامل مع البيانات الاختيارية على أنها تشخيص طبي.",
    "Storage and service providers": "مزودي التخزين والخدمات",
    "DayVector stores working data locally on your device. When synchronization is enabled, account data may be processed by Supabase infrastructure. Platform services may also process data needed for sign-in, notifications, software downloads and operating-system integrations.":
      "يقوم DayVector بتخزين بيانات العمل محليًا على جهازك. عند تمكين المزامنة، قد تتم معالجة بيانات الحساب بواسطة البنية التحتية Supabase. قد تقوم خدمات النظام الأساسي أيضًا بمعالجة البيانات اللازمة لتسجيل الدخول والإشعارات وتنزيلات البرامج وتكامل نظام التشغيل.",
    "Your controls": "الضوابط الخاصة بك",
    "Depending on the feature status and platform, you can pause tracking, exclude applications or websites, correct classifications, remove history, keep selected information local, revoke device access, export account data and request account deletion.":
      "اعتمادًا على حالة الميزة والنظام الأساسي، يمكنك إيقاف التتبع مؤقتًا واستبعاد التطبيقات أو مواقع الويب وتصحيح التصنيفات وإزالة السجل والاحتفاظ بالمعلومات المحددة محليًا وإلغاء الوصول إلى الجهاز وتصدير بيانات الحساب وطلب حذف الحساب.",
    "Security and sensitive features": "الأمان والميزات الحساسة",
    "DayVector uses platform and service security controls appropriate to each feature. Planned security-sensitive features are not represented as available until their implementation and review are complete.":
      "يستخدم DayVector ضوابط أمان النظام الأساسي والخدمة المناسبة لكل ميزة. لا يتم تمثيل الميزات الحساسة للأمان المخطط لها على أنها متاحة حتى يتم الانتهاء من تنفيذها ومراجعتها.",
    "Changes to this policy": "التغييرات في هذه السياسة",
    "This policy may be updated as DayVector evolves. The effective date above will change when material revisions are published.":
      "قد يتم تحديث هذه السياسة مع تطور DayVector. سيتغير تاريخ السريان أعلاه عندما يتم نشر مراجعات المواد.",
    "For privacy questions, email": "لأسئلة الخصوصية، البريد الإلكتروني",
    "Terms of Service for DayVector": "شروط الخدمة لبرنامج DayVector",
    "Terms governing use of the DayVector application.":
      "الشروط التي تحكم استخدام تطبيق DayVector.",
    "← Back to DayVector": "← الرجوع إلى DayVector",
    "Terms of service": "شروط الخدمة",
    "Clear terms for using DayVector":
      "شروط واضحة لاستخدام DayVector",
    "These terms apply to your use of DayVector, an application created and maintained by Y. A. Diab. By creating an account or using the application, you agree to use it lawfully and in accordance with these terms.":
      "تنطبق هذه الشروط على استخدامك لتطبيق DayVector، وهو تطبيق تم إنشاؤه وصيانته بواسطة يوسف أ. دياب. من خلال إنشاء حساب أو استخدام التطبيق، فإنك توافق على استخدامه بشكل قانوني ووفقًا لهذه الشروط.",
    "Purpose of the application": "الغرض من التطبيق",
    "DayVector provides tools for planning, task execution, time and activity review, roadmaps, reports and performance coaching. Features marked Beta or Planned may change, remain incomplete or be unavailable on some platforms.":
      "يوفر DayVector أدوات للتخطيط وتنفيذ المهام ومراجعة الوقت والنشاط وخرائط الطريق والتقارير والتدريب على الأداء. قد تتغير الميزات المميزة بعلامة Beta أو المخطط لها، أو تظل غير مكتملة أو غير متوفرة على بعض الأنظمة الأساسية.",
    "Your account and content": "حسابك والمحتوى الخاص بك",
    "You are responsible for safeguarding your sign-in methods, maintaining accurate account information and keeping appropriate backups of important content. You retain responsibility for the tasks, notes, resources and other content you add.":
      "أنت مسؤول عن حماية طرق تسجيل الدخول الخاصة بك، والحفاظ على معلومات الحساب الدقيقة والاحتفاظ بنسخ احتياطية مناسبة من المحتوى المهم. أنت تحتفظ بالمسؤولية عن المهام والملاحظات والموارد والمحتويات الأخرى التي تضيفها.",
    "Acceptable use": "الاستخدام المقبول",
    "Do not use DayVector to violate law, infringe the rights of others, attempt unauthorized access, distribute malicious software or interfere with the application and its supporting services.":
      "لا تستخدم DayVector لانتهاك القانون أو انتهاك حقوق الآخرين أو محاولة الوصول غير المصرح به أو توزيع البرامج الضارة أو التدخل في التطبيق والخدمات الداعمة له.",
    "Updates and availability": "التحديثات والتوافر",
    "Software updates may add, change or remove features. You choose whether to install an offered desktop or Android package, and the operating system may require additional confirmation. Availability can be affected by device, network and third-party service conditions.":
      "قد تضيف تحديثات البرامج ميزات أو تغيرها أو تزيلها. أنت تختار ما إذا كنت تريد تثبيت حزمة سطح المكتب أو Android المعروضة، وقد يتطلب نظام التشغيل تأكيدًا إضافيًا. يمكن أن يتأثر التوفر بظروف الجهاز والشبكة وخدمة الطرف الثالث.",
    "Productivity and coaching information": "معلومات الإنتاجية والتدريب",
    "DayVector provides planning, productivity and performance information. It does not provide medical, psychological, legal, financial or professional diagnosis or treatment.":
      "يوفر DayVector معلومات التخطيط والإنتاجية والأداء. ولا يقدم تشخيصًا أو علاجًا طبيًا أو نفسيًا أو قانونيًا أو ماليًا أو مهنيًا.",
    "No guaranteed outcome": "لا توجد نتيجة مضمونة",
    "Forecasts and recommendations depend on available information and may be incomplete or inaccurate. You remain in control of decisions, classifications, schedules and progress.":
      "تعتمد التوقعات والتوصيات على المعلومات المتاحة وقد تكون غير كاملة أو غير دقيقة. ستظل متحكمًا في القرارات والتصنيفات والجداول الزمنية والتقدم.",
    "Ending use": "إنهاء الاستخدام",
    "You may stop using the application and, when available in the account controls, request deletion of synchronized account information. Some records may be retained temporarily where required for security, integrity or legal reasons.":
      "يمكنك التوقف عن استخدام التطبيق، وعندما يكون ذلك متاحًا في عناصر التحكم في الحساب، يمكنك طلب حذف معلومات الحساب المتزامنة. قد يتم الاحتفاظ ببعض السجلات مؤقتًا عندما يكون ذلك مطلوبًا لأسباب تتعلق بالأمن أو النزاهة أو لأسباب قانونية.",
    "For support or questions about these terms, contact Y. A. Diab at":
      "للحصول على الدعم أو الأسئلة حول هذه الشروط، اتصل بـ Y. A. Diab على",
    "Installation Help for DayVector":
      "تعليمات التثبيت لبرنامج DayVector",
    "Install DayVector on Windows, Android phones and Android tablets.":
      "قم بتثبيت DayVector على أجهزة Windows وهواتف Android والأجهزة اللوحية التي تعمل بنظام Android.",
    "← Back to downloads": "← العودة إلى التنزيلات",
    "Get DayVector running": "قم بتشغيل DayVector",
    "Applies to the version shown on the download card":
      "ينطبق على الإصدار الموضح على بطاقة التنزيل",
    "Windows 10 and Windows 11": "ويندوز 10 وويندوز 11",
    "Download the Windows installer from the official GitHub release.":
      "قم بتنزيل مثبت Windows من إصدار GitHub الرسمي.",
    "Open the downloaded DayVector Windows installer.":
      "افتح برنامج تثبيت DayVector Windows الذي تم تنزيله.",
    "Review any Windows security prompt, then continue the installer.":
      "قم بمراجعة أي مطالبة أمان لنظام التشغيل Windows، ثم تابع عملية التثبيت.",
    "Launch DayVector from the Start menu or desktop shortcut.":
      'قم بتشغيل DayVector من قائمة "ابدأ" أو من اختصار سطح المكتب.',
    "Android phones and tablets":
      "الهواتف والأجهزة اللوحية التي تعمل بنظام Android",
    "Download the signed DayVector Android package.":
      "قم بتنزيل حزمة DayVector Android الموقعة.",
    "Open the downloaded APK from your browser or Files application.":
      "افتح ملف APK الذي تم تنزيله من متصفحك أو تطبيق الملفات.",
    "If Android asks, allow installation from that source for this install.":
      "إذا طلب Android ذلك، فاسمح بالتثبيت من هذا المصدر لهذا التثبيت.",
    "Review the package details and confirm installation.":
      "قم بمراجعة تفاصيل الحزمة وتأكيد التثبيت.",
    "DayVector never starts an installation without your action. Windows may show a reputation warning for a new, unsigned release, and Android requires confirmation before installing an APK outside an app store.":
      "لا يبدأ DayVector عملية التثبيت مطلقًا بدون إجراء من جانبك. قد يعرض Windows تحذيرًا بشأن السمعة لإصدار جديد غير موقّع، ويتطلب Android التأكيد قبل تثبيت APK خارج متجر التطبيقات.",
    "Check your download": "تحقق من التنزيل الخاص بك",
    "Every official release includes a verification file beside each installer. You can use it to confirm that the download has not changed before opening it.":
      "يتضمن كل إصدار رسمي ملف تحقق بجانب كل أداة تثبيت. يمكنك استخدامه للتأكد من أن التنزيل لم يتغير قبل فتحه.",
    "Need help?": "بحاجة الى مساعدة؟",
    "Email Y. A. Diab at": "البريد الإلكتروني ي. أ. دياب على",
    "A free, adjustable Pomodoro timer from DayVector that remembers the current session and settings locally in your browser.":
      "مؤقت بومودورو مجاني وقابل للتعديل من DayVector يتذكر الجلسة الحالية والإعدادات محليًا في متصفحك.",
    "Free Pomodoro Timer from DayVector":
      "مؤقت بومودورو مجاني من DayVector",
    "Run an adjustable focus timer that resumes where you left off, with an accessible guide to the Pomodoro Technique.":
      "قم بتشغيل مؤقت التركيز القابل للتعديل والذي يستأنف من حيث توقفت، مع دليل يمكن الوصول إليه لتقنية بومودورو.",
    Timer: "الموقت",
    "How to use it": "كيفية استخدامه",
    "Android widget": "أداة الشاشة الرئيسية لأندرويد",
    "Free, private and ready without an account": "مجاني وخاص وجاهز بدون حساب",
    "Make the next": "اصنع التالي",
    "25 minutes": "25 دقيقة",
    "count.": "عدد.",
    "Pick one meaningful task, focus for a bounded interval and take a real break. This timer remembers your session in this browser, even when you close the tab.":
      "اختر مهمة واحدة ذات معنى، وركز على فترة زمنية محددة وخذ استراحة حقيقية. يتذكر هذا المؤقت جلستك في هذا المتصفح، حتى عند إغلاق علامة التبويب.",
    "Timer capabilities": "قدرات الموقت",
    "Remembers your timer on this device":
      "يتذكر الموقت الخاص بك على هذا الجهاز",
    "Adjustable intervals": "فترات قابلة للتعديل",
    "Responsive everywhere": "مستجيب في كل مكان",
    "What is the Pomodoro Technique?": "ما هي تقنية البومودورو؟",
    "History, practical guidance and research context":
      "التاريخ والتوجيه العملي وسياق البحث",
    "Your focus space": "مساحة التركيز الخاصة بك",
    "Browser Pomodoro": "متصفح بومودورو",
    "Saved only in this browser": "تم الحفظ فقط في هذا المتصفح",
    "Saved locally": "تم الحفظ محليًا",
    "Local saving unavailable": "الحفظ المحلي غير متاح",
    "What are you moving forward?": "ماذا تمضي قدما؟",
    "e.g. Review chapter 4": "على سبيل المثال مراجعة الفصل 4",
    "Choose timer phase": "اختر مرحلة الموقت",
    "Short break": "استراحة قصيرة",
    "Long break": "استراحة طويلة",
    "Pomodoro controls": "ضوابط بومودورو",
    Reset: "إعادة ضبط",
    "Start focus": "ابدأ بالتركيز",
    "Start break": "بدء الاستراحة",
    Skip: "يتخطى",
    "Ready when you are. Your progress stays on this device.":
      "جاهز عندما تكون. يبقى تقدمك على هذا الجهاز.",
    "Focus is running. Keep this interval for one clear task.":
      "التركيز قيد التشغيل. احتفظ بهذا الفاصل الزمني لمهمة واحدة واضحة.",
    "Break is running. Step away from the task if you can.":
      "الاستراحة قيد التشغيل. ابتعد عن المهمة إذا استطعت.",
    "Break complete. Your next focus is ready.":
      "اكتمل الكسر. تركيزك التالي جاهز.",
    "Focus complete. Take a deliberate break.":
      "التركيز كامل. خذ استراحة متعمدة.",
    "Adjust timer": "ضبط الموقت",
    "Focus minutes": "دقائق التركيز",
    "Focuses per round": "يركز في كل جولة",
    "Start breaks automatically": "بدء الفواصل تلقائيًا",
    "Start the next focus automatically": "ابدأ التركيز التالي تلقائيًا",
    "Play a gentle completion tone": "قم بتشغيل نغمة إكمال لطيفة",
    "Restore recommended times": "استعادة الأوقات الموصى بها",
    "Your timer stays on this device and is ready when you return. Nothing is sent to DayVector.":
      "يبقى المؤقت الخاص بك على هذا الجهاز ويكون جاهزًا عند عودتك. لا يتم إرسال أي شيء إلى DayVector.",
    "A gentle starting ritual": "طقوس البداية اللطيفة",
    "Use the interval to protect attention, not to race the clock":
      "استخدم الفاصل الزمني لحماية الانتباه، وليس لسباق الزمن",
    "The familiar 25-minute timer is a useful entry point. The complete technique also includes planning, handling interruptions, recording effort and learning from each cycle.":
      "يعد المؤقت المألوف لمدة 25 دقيقة نقطة دخول مفيدة. تتضمن التقنية الكاملة أيضًا التخطيط والتعامل مع الانقطاعات وتسجيل الجهد والتعلم من كل دورة.",
    "Choose one clear outcome": "اختر نتيجة واحدة واضحة",
    "Write a task small enough to move during one focused interval.":
      "اكتب مهمة صغيرة بما يكفي للتحرك خلال فترة زمنية واحدة مركّزة.",
    "Start and protect the interval": "ابدأ وحماية الفاصل الزمني",
    "Put avoidable distractions aside; note interruptions instead of chasing them.":
      "ضع الانحرافات التي يمكن تجنبها جانبا؛ لاحظ الانقطاعات بدلاً من مطاردتها.",
    "Stop when the timer ends": "توقف عندما ينتهي الموقت",
    "Take the break seriously. Stand, breathe, drink water or let your attention reset.":
      "خذ الاستراحة على محمل الجد. قف، تنفس، اشرب الماء أو دع انتباهك يستعيد نشاطه.",
    "Review, then begin again": "قم بالمراجعة، ثم ابدأ من جديد",
    "After several focuses, take a longer break and adjust the durations to fit your work.":
      "بعد عدة تركيزات، خذ استراحة أطول واضبط الفترات لتناسب عملك.",
    "Go deeper into learning": "تعمق في التعلم",
    "A useful companion:": "الرفيق المفيد:",
    "Barbara Oakley’s book explains practical approaches to learning difficult material, overcoming procrastination and moving between focused and more diffuse modes of thinking. Its strategies apply beyond mathematics and science.":
      "يشرح كتاب باربرا أوكلي الأساليب العملية لتعلم المواد الصعبة والتغلب على المماطلة والتنقل بين أنماط التفكير المركزة والأكثر انتشارًا. تنطبق استراتيجياتها خارج نطاق الرياضيات والعلوم.",
    "Read about the book": "اقرأ عن الكتاب",
    "Product website": "موقع المنتج",
    Terms: "شروط",
    "A practical introduction": "مقدمة عملية",
    "The idea behind the Pomodoro Technique": "الفكرة وراء تقنية البومودورو",
    "Close Pomodoro information": "إغلاق معلومات بومودورو",
    "Who created it?": "من خلقه؟",
    "Francesco Cirillo created the technique while he was a university student in the late 1980s, using a tomato-shaped kitchen timer. The name comes from the Italian word for tomato. Cirillo emphasizes that the timer is only one part of a broader system for planning, managing interruptions, estimating effort and improving how you work.":
      "ابتكر فرانشيسكو سيريلو هذه التقنية عندما كان طالبًا جامعيًا في أواخر الثمانينيات، باستخدام مؤقت مطبخ على شكل طماطم. الاسم يأتي من الكلمة الإيطالية التي تعني الطماطم. يؤكد سيريلو على أن المؤقت ليس سوى جزء واحد من نظام أوسع للتخطيط وإدارة الانقطاعات وتقدير الجهد وتحسين طريقة عملك.",
    "How can a timer help?": "كيف يمكن أن يساعد الموقت؟",
    "A bounded interval can lower the barrier to starting, make interruptions visible and create a deliberate stopping point. Research by Atsunori Ariga and Alejandro Lleras found that brief, rare breaks helped prevent a decline in performance during a sustained-attention task. That does not make one duration perfect for everyone. Adjust the timer to the work and to your needs.":
      "يمكن أن يؤدي الفاصل الزمني المحدد إلى خفض حاجز البدء، وجعل الانقطاعات مرئية وإنشاء نقطة توقف متعمدة. وجدت الأبحاث التي أجراها أتسونوري أريجا وأليخاندرو ليراس أن فترات الراحة القصيرة والنادرة ساعدت في منع انخفاض الأداء أثناء مهمة التركيز المستمر. وهذا لا يجعل مدة واحدة مثالية للجميع. اضبط المؤقت ليناسب العمل واحتياجاتك.",
    "A simple first cycle": "دورة أولى بسيطة",
    "Choose one task and define what “moved forward” will mean.":
      'اختر مهمة واحدة وحدد ما يعنيه عبارة "المضي قدمًا".',
    "Focus for 25 minutes, recording interruptions instead of following them.":
      "ركز لمدة 25 دقيقة، وقم بتسجيل المقاطعات بدلاً من متابعتها.",
    "Stop and take a short break when the interval ends.":
      "توقف وخذ استراحة قصيرة عند انتهاء الفاصل الزمني.",
    "After four focus intervals, take a longer break and review the pattern.":
      "بعد أربع فترات تركيز، خذ استراحة أطول وراجع النمط.",
    "The timer is a tool, not a score. Even the creator cautions against reducing the full technique to collecting as many 25-minute intervals as possible.":
      "الموقت هو أداة، وليس النتيجة. حتى المبدع يحذر من اختصار التقنية الكاملة لتجميع أكبر عدد ممكن من الفواصل الزمنية التي تبلغ مدتها 25 دقيقة.",
    "Sources and further reading": "المصادر ومزيد من القراءة",
    "Francesco Cirillo: creator’s account and philosophy":
      "فرانشيسكو سيريلو: رواية المبدع وفلسفته",
    "Official Pomodoro Technique overview":
      "نظرة عامة رسمية على تقنية بومودورو",
    "Ariga & Lleras (2011),": "أريجا وليراس (2011)،",
    ": brief mental breaks and vigilance": ": فترات راحة عقلية قصيرة واليقظة",
    "Barbara Oakley:": "باربرا أوكلي:",
    "Pomodoro® is a registered trademark of Francesco Cirillo. This independent educational timer is not affiliated with or endorsed by Francesco Cirillo.":
      "بومودورو® علامة تجارية مسجلة لفرانشيسكو سيريلو. هذا المؤقت التعليمي المستقل غير تابع لفرانشيسكو سيريلو ولا يحظى بتأييده.",
    "Start a focus interval": "بدء فترة التركيز",
  };

  Object.assign(german, {
    "Activity reports": "Aktivitätsberichte",
    "See where your time actually went":
      "Sieh, wofür deine Zeit wirklich genutzt wurde",
    "Reports group approved application and website activity by duration. Open the underlying activity whenever you want to review or correct it":
      "Berichte gruppieren freigegebene App- und Website-Aktivität nach Dauer. Die zugrunde liegenden Einträge kannst du jederzeit prüfen oder korrigieren.",
    "See the time recorded for each application and website":
      "Sieh die erfasste Zeit für jede App und Website",
    "Connect trusted tools to the task they support":
      "Verbinde vertraute Werkzeuge mit der passenden Aufgabe",
    "Keep uncertain activity ready for your review":
      "Unsichere Aktivität bleibt für deine Prüfung erhalten",
    "Example activity report": "Beispiel für einen Aktivitätsbericht",
    "Development session": "Entwicklungssitzung",
    Application: "Anwendung",
    "42 minutes": "42 Minuten",
    "Website activity": "Website-Aktivität",
    "Paused work": "Pausierte Arbeit",
    "Overdue tasks": "Überfällige Aufgaben",
    "Roadmap progress": "Roadmap-Fortschritt",
    "Rest timing": "Erholungszeit",
    "Focus patterns": "Fokusmuster",
    "Coaching suggestion": "Coaching-Vorschlag",
    "Make the roadmap feel possible again":
      "Lass uns die Roadmap wieder machbar machen",
    "Based on your roadmap": "Aus deiner Roadmap",
    "Part of your roadmap is at risk. Make":
      "Ein Teil deiner Roadmap ist gefährdet. Mach",
    "Prepare launch brief": "Startunterlagen vorbereiten",
    "the recovery step and leave the rest outside this session":
      "zum nächsten Schritt und lass den Rest außerhalb dieser Sitzung.",
    "Evidence: 3 open roadmap tasks": "Grundlage: 3 offene Roadmap-Aufgaben",
    "Next step": "Nächster Schritt",
    "Open the related task and protect one focused session":
      "Öffne die zugehörige Aufgabe und schütze eine konzentrierte Sitzung",
    "Open related task": "Zugehörige Aufgabe öffnen",
    "Not useful": "Nicht hilfreich",
    "Wrong timing": "Falscher Zeitpunkt",
    "Made to feel at home on Android": "Passt natürlich auf deinen Android-Startbildschirm",
  });

  Object.assign(arabic, {
    Features: "المزايا",
    Widget: "أداة الشاشة الرئيسية",
    Health: "الصحة",
    Coaching: "الإرشاد",
    Privacy: "الخصوصية",
    Contact: "تواصل معنا",
    Download: "التنزيل",
    "Download for Android": "تنزيل لأجهزة أندرويد",
    "Offline capable": "يعمل دون اتصال",
    "6 tasks complete": "6 مهام مكتملة",
    Focus: "تركيز",
    "2h 41m active": "ساعتان و41 دقيقة من النشاط",
    "68% complete": "مكتمل بنسبة 68%",
    "Feature status legend": "حالة المزايا",
    Medium: "متوسطة",
    Evidence: "الأدلة",
    "Continuous Timer": "مؤقت مستمر",
    "Pomodoro Focus": "تركيز بومودورو",
    "Focus from your home screen": "ركّز مباشرة من شاشتك الرئيسية",
    "Your running session stays visible and controllable":
      "تبقى جلستك الحالية ظاهرة وتحت سيطرتك",
    "Live focus and break countdowns": "عدّ تنازلي مباشر للتركيز والاستراحة",
    "Pause, break and finish controls": "أزرار للإيقاف والاستراحة والإنهاء",
    "Canonical state shared with the app": "حالة موحّدة مع التطبيق",
    "Get the Android widget": "احصل على أداة الشاشة الرئيسية",
    "Android Widget": "أداة الشاشة الرئيسية لأندرويد",
    "Android widget": "أداة الشاشة الرئيسية لأندرويد",
    "View on Android": "عرض على أندرويد",
    "Interactive widget preview controls":
      "عناصر التحكم في معاينة أداة الشاشة الرئيسية",
    Pause: "إيقاف مؤقت",
    Resume: "استئناف",
    Finish: "إنهاء",
    Productive: "منتج",
    "Needs review": "يحتاج إلى مراجعة",
    "Make the next": "اجعل",
    "25 minutes": "الدقائق الـ25 القادمة",
    "count.": "ذات قيمة",
    Timer: "المؤقت",
    "Local saving unavailable": "تعذّر حفظ المؤقت على هذا الجهاز",
    "What are you moving forward?": "ما المهمة التي تريد إحراز تقدم فيها؟",
    Skip: "تخطَّ",
    "Focuses per round": "جلسات التركيز في كل جولة",
    "A useful companion:": "رفيق مفيد:",
    "Who created it?": "من ابتكرها؟",
    "How can a timer help?": "كيف يمكن للمؤقت أن يساعدك؟",
    Terms: "الشروط",
    "The same live session as the app": "الجلسة المباشرة نفسها داخل التطبيق",
    "Health context without clutter": "صحتك بوضوح ومن دون ازدحام",
    "See movement and recovery beside your work":
      "شاهد الحركة والتعافي بجانب يوم عملك",
    "With your permission, DayVector reads the health summaries you choose to share and presents them in a calm daily view. It helps you notice when movement, rest and focused work are supporting each other.":
      "بعد إذنك، يقرأ DayVector ملخصات الصحة التي تختار مشاركتها ويعرضها في صفحة يومية هادئة. ويساعدك ذلك على ملاحظة كيف تدعم الحركة والراحة والعمل المركّز بعضها بعضاً.",
    "A clear view of today": "نظرة واضحة على يومك",
    "Steps, distance, active energy and workouts at a glance":
      "الخطوات والمسافة والطاقة النشطة والتمارين في لمحة واحدة",
    "Your week in motion": "أسبوعك في حركة",
    "Readable values and a simple seven-day movement chart":
      "قيم سهلة القراءة ورسم بسيط لحركتك خلال سبعة أيام",
    "Health sources together": "مصادر الصحة في مكان واحد",
    "Connected watches and health applications in one tidy place":
      "الساعات المتصلة وتطبيقات الصحة مرتبة في مكان واحد",
    "Useful on Windows too": "مفيد على Windows أيضاً",
    "Daily summaries stay readable across your signed-in devices":
      "تبقى الملخصات اليومية واضحة على أجهزتك التي سجلت الدخول عليها",
    "Swipe down to refresh": "اسحب إلى أسفل للتحديث",
    "Read-only access": "وصول للقراءة فقط",
    "Captured from the Android app": "لقطة حقيقية من تطبيق Android",
    "DayVector Health dashboard showing today's steps, distance, active energy and a seven-day movement chart":
      "لوحة الصحة في DayVector تعرض خطوات اليوم والمسافة والطاقة النشطة ورسم الحركة خلال سبعة أيام",
    "Time does not always follow the schedule. DayVector keeps each activity period available for review and makes sure the same minute is never counted twice":
      "لا يسير اليوم دائماً حسب الجدول. يحتفظ DayVector بكل فترة نشاط للمراجعة ويضمن عدم احتساب الدقيقة نفسها مرتين.",
    "Project task": "مهمة المشروع",
    "Prepare product launch": "الاستعداد لإطلاق المنتج",
    "Activity reports": "تقارير النشاط",
    "See where your time actually went": "اعرف أين ذهب وقتك فعلاً",
    "Reports group approved application and website activity by duration. Open the underlying activity whenever you want to review or correct it":
      "تجمع التقارير نشاط التطبيقات والمواقع الذي اعتمدته حسب المدة. ويمكنك فتح النشاط الأصلي في أي وقت لمراجعته أو تصحيحه.",
    "See the time recorded for each application and website":
      "شاهد الوقت المسجل لكل تطبيق وموقع",
    "Connect trusted tools to the task they support":
      "اربط الأدوات الموثوقة بالمهمة التي تدعمها",
    "Keep uncertain activity ready for your review":
      "اترك النشاط غير المؤكد جاهزاً لمراجعتك",
    "Example activity report": "مثال على تقرير النشاط",
    "Development session": "جلسة تطوير",
    Application: "تطبيق",
    "42 minutes": "42 دقيقة",
    "Website activity": "نشاط موقع ويب",
    "Paused work": "عمل متوقف مؤقتاً",
    "Overdue tasks": "مهام متأخرة",
    "Roadmap progress": "تقدم خارطة الطريق",
    "Rest timing": "توقيت الراحة",
    "Focus patterns": "أنماط التركيز",
    "Coaching suggestion": "اقتراح من المرشد",
    "Make the roadmap feel possible again":
      "لنجعل خارطة الطريق ممكنة من جديد",
    "Based on your roadmap": "استناداً إلى خارطة طريقك",
    "Part of your roadmap is at risk. Make":
      "جزء من خارطة طريقك معرض للتأخر. اجعل",
    "Prepare launch brief": "إعداد ملخص الإطلاق",
    "the recovery step and leave the rest outside this session":
      "خطوة الاستعادة واترك الباقي خارج هذه الجلسة.",
    "Evidence: 3 open roadmap tasks":
      "الأساس: 3 مهام مفتوحة في خارطة الطريق",
    "Next step": "الخطوة التالية",
    "Open the related task and protect one focused session":
      "افتح المهمة المرتبطة وخصص لها جلسة تركيز واحدة",
    "Open related task": "فتح المهمة المرتبطة",
    "Not useful": "غير مفيد",
    "Wrong timing": "توقيت غير مناسب",
    "Start on Windows. Continue on Android":
      "ابدأ على ويندوز وأكمل على أندرويد",
    "Start, pause or resume the same task from Windows or Android. Tasks, roadmaps, settings and approved work stay consistent when devices are online":
      "ابدأ المهمة نفسها أو أوقفها مؤقتاً أو استأنفها من ويندوز أو أندرويد. وتبقى المهام وخرائط الطريق والإعدادات والعمل المعتمد متسقة عندما تكون الأجهزة متصلة.",
    "Start on Windows": "ابدأ على ويندوز",
    "View on Android": "تابع على أندرويد",
    "Continue on Windows": "أكمل على ويندوز",
    "You choose which activity DayVector may record and whether selected data remains local or is synchronized":
      "أنت تحدد النشاط الذي يمكن للتطبيق تسجيله، وما إذا كانت البيانات المختارة ستبقى على جهازك أو تتم مزامنتها.",
    "DayVector does not upload browser cookies, website login tokens, clipboard contents, form contents or unencrypted passwords":
      "لا يرفع التطبيق ملفات تعريف الارتباط أو رموز تسجيل الدخول للمواقع أو محتوى الحافظة أو النماذج أو كلمات المرور غير المشفرة.",
    "DayVector v": "الإصدار",
    "Download DayVector and begin turning long-term goals into practical, measurable daily progress":
      "نزّل التطبيق وابدأ في تحويل أهدافك طويلة المدى إلى تقدم يومي عملي يمكنك قياسه.",
    "DayVector for Windows": "DayVector لويندوز",
    "Designed for Windows 10 and Windows 11": "مصمم لويندوز 10 وويندوز 11",
    "64-bit EXE": "ملف تثبيت 64 بت",
    "DayVector for Android": "DayVector لأندرويد",
    "Designed for Android phones and tablets":
      "مصمم لهواتف أندرويد وأجهزته اللوحية",
    "Signed APK": "حزمة تثبيت موثوقة لأندرويد",
    "Download for Windows": "تنزيل لويندوز",
    "Download for Android": "تنزيل لأندرويد",
    Version: "الإصدار",
    Installer: "ملف التثبيت",
    Package: "حزمة التثبيت",
    Size: "الحجم",
    "Made to feel at home on Android":
      "مصممة لتبدو طبيعية على شاشة أندرويد الرئيسية",
    "Books, PDFs, duration, saved position and notes":
      "الكتب والمستندات والمدة والموضع المحفوظ والملاحظات",
    "The responsive Android widget reflects the current DayVector session. See the remaining time at a glance, pause without opening the app, move to a break or finish when the work is complete.":
      "تعرض أداة الشاشة الرئيسية لأندرويد جلستك الحالية بوضوح. شاهد الوقت المتبقي، وأوقف الجلسة أو ابدأ استراحة أو أنهِ المهمة من دون فتح التطبيق.",
    "Useful on Windows too": "مفيد على ويندوز أيضاً",
    "Track full URLs": "تتبع الروابط كاملة",
    "A personal planning, execution and performance-coaching system for Windows and Android":
      "نظام شخصي للتخطيط والتنفيذ والإرشاد على ويندوز وأندرويد",
  });

  // English remains a safe fallback for infrequent legal copy while the
  // high-traffic product pages are translated here. New website copy belongs
  // in this shared dictionary instead of per-page markup.
  const polish = {
    "DayVector turns direction into daily progress with task planning, roadmaps, focus timers, activity insights and evidence-based coaching on Windows and Android.":
      "DayVector zamienia kierunek w codzienny postęp dzięki planowaniu zadań, mapom drogowym, licznikom skupienia, analizie aktywności i coachingowi opartemu na danych na Windowsie i Androidzie.",
    "DayVector — Turn direction into daily progress":
      "DayVector — Zamień kierunek w codzienny postęp",
    "Plan meaningful goals, focus on the next task and improve with evidence-based coaching across Windows and Android.":
      "Planuj ważne cele, skup się na następnym zadaniu i rozwijaj się dzięki coachingowi opartemu na danych na Windowsie i Androidzie.",
    "Skip to main content": "Przejdź do treści głównej",
    "DayVector home": "Strona główna DayVector",
    "Open navigation": "Otwórz nawigację",
    "Close navigation": "Zamknij nawigację",
    "Main navigation": "Główna nawigacja",
    Features: "Funkcje",
    "How It Works": "Jak to działa",
    Roadmaps: "Mapy drogowe",
    Widget: "Widżet",
    Health: "Zdrowie",
    Coaching: "Coaching",
    Pomodoro: "Pomodoro",
    Privacy: "Prywatność",
    Contact: "Kontakt",
    Download: "Pobierz",
    "Download App": "Pobierz aplikację",
    "Download app": "Pobierz aplikację",
    "Turn direction into daily progress": "Zamień kierunek w codzienny postęp",
    "Plan your goals": "Planuj swoje cele",
    "Execute your tasks": "Realizuj zadania",
    "Improve every day": "Rozwijaj się każdego dnia",
    "Download for Windows": "Pobierz dla Windows",
    "Download for Android": "Pobierz dla Androida",
    "Explore how it works": "Zobacz, jak to działa",
    "Cross-device synchronization": "Synchronizacja między urządzeniami",
    Today: "Dzisiaj",
    Focus: "Skupienie",
    Roadmap: "Mapa drogowa",
    Available: "Dostępne",
    Planned: "Planowane",
    "One connected system": "Jeden połączony system",
    "A practical loop": "Praktyczny cykl",
    "Define your goal": "Określ swój cel",
    "Build the roadmap": "Zbuduj mapę drogową",
    "Execute the work": "Wykonaj pracę",
    "Learn and improve": "Ucz się i rozwijaj",
    "Useful work is never lost": "Przydatna praca nigdy nie przepada",
    "Get a helpful next step": "Otrzymaj pomocny następny krok",
    "Personal coaching": "Osobisty coaching",
    "Your focus space": "Twoja przestrzeń skupienia",
    "Saved locally": "Zapisano lokalnie",
    "Focus session": "Sesja skupienia",
    "Recovery break": "Przerwa regeneracyjna",
    "Short break": "Krótka przerwa",
    "Long break": "Długa przerwa",
    Start: "Rozpocznij",
    Pause: "Wstrzymaj",
    Resume: "Wznów",
    Finish: "Zakończ",
    Version: "Wersja",
    "Installation Help": "Pomoc w instalacji",
    "Privacy policy": "Polityka prywatności",
    "Terms of use": "Warunki korzystania",
    "Polish Language Now Available!": "Język polski jest już dostępny!",
    "Latest DayVector update": "Najnowsza aktualizacja DayVector",
    "Select language": "Wybierz język",
    "Use light theme": "Użyj jasnego motywu",
    "Use dark theme": "Użyj ciemnego motywu",
    "Personal planning, focused execution and evidence-based coaching on Windows and Android.":
      "Osobiste planowanie, skupiona realizacja i coaching oparty na danych na Windowsie i Androidzie.",
    "DayVector — Planning, Focus Timers, Roadmaps and Coaching":
      "DayVector — Planowanie, timery skupienia, mapy drogowe i coaching",
    "DayVector turns goals into roadmaps, recurring tasks and daily actions, measures real effort and provides explainable coaching across Windows and Android.":
      "DayVector zamienia cele w mapy drogowe, zadania cykliczne i codzienne działania, mierzy rzeczywisty wysiłek oraz oferuje zrozumiały coaching na Windowsie i Androidzie.",
    "DayVector: Plan, Focus and Improve": "DayVector: planuj, skupiaj się i rozwijaj",
    "Create roadmaps, execute focused tasks, track real activity and improve through evidence-based coaching.":
      "Twórz mapy drogowe, wykonuj zadania w skupieniu, śledź rzeczywistą aktywność i rozwijaj się dzięki coachingowi opartemu na danych.",
    "DayVector: Planning, Focus and Personal Coaching":
      "DayVector: planowanie, skupienie i osobisty coaching",
    "Skip to timer": "Przejdź do timera",
    "Pomodoro page navigation": "Nawigacja strony Pomodoro",
    "DayVector combines task management, structured roadmaps, time tracking and personalized coaching to help you organize your responsibilities, improve your habits and make better use of your time":
      "DayVector łączy zarządzanie zadaniami, uporządkowane mapy drogowe, śledzenie czasu i spersonalizowany coaching, aby pomóc Ci organizować obowiązki, rozwijać nawyki i lepiej wykorzystywać czas.",
    "It connects planned work with real activity, credits useful effort to the task it supports and turns verified patterns into clear recommendations":
      "Łączy zaplanowaną pracę z rzeczywistą aktywnością, przypisuje pożyteczny wysiłek do wspieranego zadania i zamienia potwierdzone wzorce w jasne zalecenia.",
    "Supported platforms and capabilities": "Obsługiwane platformy i możliwości",
    "DayVector dashboard showing task suggestions, today's schedule, workload and overdue work":
      "Panel DayVector z sugestiami zadań, dzisiejszym planem, obciążeniem i zaległymi zadaniami",
    Windows: "Windows",
    "Android phones": "Telefony z Androidem",
    "Android tablets": "Tablety z Androidem",
    "Offline capable": "Działa offline",
    "6 tasks complete": "6 zadań ukończonych",
    "2h 41m active": "2 godz. 41 min aktywności",
    "68% complete": "68% ukończono",
    "One application for planning, execution, progress and improvement":
      "Jedna aplikacja do planowania, realizacji, postępu i rozwoju",
    "DayVector connects what you plan with what you actually do. It measures real effort, recognizes useful work, identifies delays and helps you improve your future schedule":
      "DayVector łączy to, co planujesz, z tym, co rzeczywiście robisz. Mierzy realny wysiłek, rozpoznaje pożyteczną pracę, wskazuje opóźnienia i pomaga ulepszać przyszły plan.",
    "Feature status legend": "Legenda statusu funkcji",
    Beta: "Beta",
    "Built for meaningful progress": "Stworzone dla znaczącego postępu",
    "Everything you need to turn plans into progress":
      "Wszystko, czego potrzebujesz, aby zamienić plany w postęp",
    "Long-term direction, daily responsibilities, real execution data and personalized guidance come together inside one calm workspace":
      "Długoterminowy kierunek, codzienne obowiązki, rzeczywiste dane z realizacji i spersonalizowane wskazówki spotykają się w jednej spokojnej przestrzeni pracy.",
    "Turn large goals into clear phases": "Zamieniaj duże cele w jasne etapy",
    "Create roadmaps with phases, milestones, checkpoints, recurring work, practice targets and completion requirements":
      "Twórz mapy drogowe z etapami, kamieniami milowymi, punktami kontrolnymi, pracą cykliczną, celami ćwiczeń i wymaganiami ukończenia.",
    "Choose the right next action": "Wybierz właściwe następne działanie",
    "Bring priority, deadlines, available time, dependencies and roadmap importance into one practical recommendation":
      "Połącz priorytet, terminy, dostępny czas, zależności i znaczenie mapy drogowej w jedną praktyczną rekomendację.",
    "Understand how your time is used": "Zrozum, jak wykorzystywany jest Twój czas",
    "Track focused work, continuous sessions, pauses, idle periods, interruptions and the difference between planned and actual effort":
      "Śledź pracę w skupieniu, ciągłe sesje, pauzy, bezczynność, przerwy i różnicę między zaplanowanym a rzeczywistym wysiłkiem.",
    "Review activity from breaks or other sessions and credit approved effort to the task and roadmap it truly supported":
      "Przeglądaj aktywność z przerw lub innych sesji i przypisuj zatwierdzony wysiłek do zadania oraz mapy drogowej, które faktycznie wspierał.",
    "Roadmaps adapt to real performance": "Mapy drogowe dostosowują się do rzeczywistych wyników",
    "Forecasts respond to actual effort, postponed work, missed sessions, confirmed progress and available capacity":
      "Prognozy reagują na rzeczywisty wysiłek, odłożoną pracę, pominięte sesje, potwierdzony postęp i dostępną pojemność.",
    "Coaching uses today’s schedule, paused work, roadmap priorities and your preferences to offer a respectful next action":
      "Coaching wykorzystuje dzisiejszy plan, wstrzymaną pracę, priorytety mapy drogowej i Twoje preferencje, aby zaproponować odpowiednie następne działanie.",
    "From a long-term goal to today’s next action":
      "Od długoterminowego celu do dzisiejszego następnego działania",
    "Create a personal, professional, learning, health or habit goal":
      "Utwórz cel osobisty, zawodowy, edukacyjny, zdrowotny albo związany z nawykiem.",
    "Reach German B1": "Osiągnij poziom B1 z niemieckiego",
    "Divide the goal into phases, milestones, checkpoints and practical recurring tasks":
      "Podziel cel na etapy, kamienie milowe, punkty kontrolne i praktyczne zadania cykliczne.",
    "Match each responsibility with focused sessions, continuous timers, checklists, reading or manual completion":
      "Dopasuj do każdego obowiązku sesje skupienia, ciągłe timery, listy kontrolne, czytanie lub ręczne ukończenie.",
    "Compare the plan with actual performance and use evidence to shape the next one":
      "Porównaj plan z rzeczywistymi wynikami i wykorzystaj dane, aby ukształtować kolejny.",
    "Roadmap workspace": "Przestrzeń mapy drogowej",
    "DayVector roadmap displaying phases, checkpoints and progress forecasts":
      "Mapa drogowa DayVector z etapami, punktami kontrolnymi i prognozami postępu",
    "Build a realistic path toward every goal": "Zbuduj realistyczną drogę do każdego celu",
    "Roadmaps turn long-term direction into measurable phases and responsibilities. Every item remains editable and every percentage has an explanation":
      "Mapy drogowe zamieniają długoterminowy kierunek w mierzalne etapy i obowiązki. Każdy element można edytować, a każdy procent ma wyjaśnienie.",
    "Editable phases": "Edytowalne etapy",
    "Target dates": "Daty docelowe",
    "Recurring tasks": "Zadania cykliczne",
    Milestones: "Kamienie milowe",
    Checkpoints: "Punkty kontrolne",
    "Required effort": "Wymagany wysiłek",
    "Forecast completion": "Prognozowane ukończenie",
    "Risk warnings": "Ostrzeżenia o ryzyku",
    "Forecast example": "Przykład prognozy",
    "The expected phase completion moved by four days because three tasks required more time and two sessions were postponed":
      "Przewidywane ukończenie etapu przesunęło się o cztery dni, ponieważ trzy zadania wymagały więcej czasu, a dwie sesje zostały przełożone.",
    Confidence: "Pewność",
    Medium: "Średnia",
    Evidence: "Dane",
    "11 comparable sessions": "11 porównywalnych sesji",
    "Flexible execution": "Elastyczna realizacja",
    "Different responsibilities need different methods":
      "Różne obowiązki wymagają różnych metod",
    "DayVector is designed to match the work rather than forcing every activity into the same timer":
      "DayVector dopasowuje się do pracy, zamiast zmuszać każdą aktywność do użycia tego samego timera.",
    "Pomodoro Focus": "Skupienie Pomodoro",
    "Focus cycles, breaks, pauses and interruptions":
      "Cykle skupienia, przerwy, pauzy i zakłócenia",
    "Try the free browser timer": "Wypróbuj bezpłatny timer w przeglądarce",
    "Continuous Timer": "Ciągły timer",
    "Long work blocks, active time and overtime":
      "Długie bloki pracy, aktywny czas i nadgodziny",
    Checklist: "Lista kontrolna",
    "Required items, priorities and completion rules":
      "Wymagane elementy, priorytety i zasady ukończenia",
    Reading: "Czytanie",
    "Books, PDFs, duration, saved position and notes":
      "Książki, pliki PDF, czas trwania, zapisana pozycja i notatki",
    Habit: "Nawyk",
    "Streaks, completion rate, recovery and timing":
      "Serie, wskaźnik ukończenia, regeneracja i harmonogram",
    Event: "Wydarzenie",
    "Arrival, duration, lateness and follow-up work":
      "Przybycie, czas trwania, spóźnienie i dalsza praca",
    Hybrid: "Hybrydowe",
    "Combine timers, checklists, checkpoints and resources":
      "Łącz timery, listy kontrolne, punkty kontrolne i materiały.",
    "Focus from your home screen": "Skupienie z ekranu głównego",
    "Your running session stays visible and controllable":
      "Twoja aktywna sesja pozostaje widoczna i możliwa do sterowania",
    "The responsive Android widget reflects the current DayVector session. See the remaining time at a glance, pause without opening the app, move to a break or finish when the work is complete.":
      "Responsywny widżet Androida odzwierciedla bieżącą sesję DayVector. Sprawdź pozostały czas jednym spojrzeniem, wstrzymaj bez otwierania aplikacji, przejdź do przerwy lub zakończ pracę.",
    "Live focus and break countdowns": "Liczniki skupienia i przerw na żywo",
    "Pause, break and finish controls": "Sterowanie pauzą, przerwą i zakończeniem",
    "Compact, medium and expanded sizes": "Rozmiary kompaktowy, średni i rozszerzony",
    "Canonical state shared with the app": "Wspólny stan główny z aplikacją",
    "Try the browser Pomodoro": "Wypróbuj Pomodoro w przeglądarce",
    "Get the Android widget": "Pobierz widżet Androida",
    "Live DayVector Android widget demonstration": "Prezentacja widżetu DayVector na Androida na żywo",
    "Android home screen showing the DayVector widget beside familiar apps":
      "Ekran główny Androida pokazujący widżet DayVector obok znanych aplikacji",
    "Interactive widget preview controls": "Interaktywne sterowanie podglądem widżetu",
    "FOCUS SESSION": "SESJA SKUPIENIA",
    "RECOVERY BREAK": "PRZERWA REGENERACYJNA",
    "Deep work session": "Sesja głębokiej pracy",
    "Time to recharge": "Czas na regenerację",
    Break: "Przerwa",
    "A real live preview with working countdown and controls":
      "Prawdziwy podgląd na żywo z działającym odliczaniem i sterowaniem",
    "Cross-task attribution": "Przypisywanie między zadaniami",
    "Useful activity belongs to the task it actually supports":
      "Przydatna aktywność należy do zadania, które rzeczywiście wspiera",
    "Time does not always follow the schedule. The contribution engine retains raw activity, requests approval when needed and avoids counting the same physical minute twice":
      "Czas nie zawsze podąża za harmonogramem. Mechanizm przypisywania zachowuje surową aktywność, prosi o zatwierdzenie, gdy jest potrzebne, i nie liczy tej samej fizycznej minuty dwa razy.",
    "Current session": "Bieżąca sesja",
    "Programming task": "Zadanie programistyczne",
    "Five-minute Pomodoro break": "Pięciominutowa przerwa Pomodoro",
    "Detected activity": "Wykryta aktywność",
    "German learning app": "Aplikacja do nauki niemieckiego",
    "4 minutes 12 seconds": "4 minuty 12 sekund",
    "Approved result": "Zatwierdzony wynik",
    "German daily practice": "Codzienna nauka niemieckiego",
    "German B1 roadmap updated": "Zaktualizowano mapę drogową niemieckiego B1",
    "Physical timeline": "Rzeczywista oś czasu",
    "Approved practice": "Zatwierdzone ćwiczenie",
    "Duplicated time": "Powielony czas",
    "Unknown and idle-looking activity stays available for review":
      "Nieznana lub wyglądająca na bezczynną aktywność pozostaje dostępna do sprawdzenia",
    "Were you reading, working away from the computer, helping another task or simply taking a break? Your answer can improve future suggestions":
      "Czy czytasz, pracujesz z dala od komputera, pomagasz przy innym zadaniu, czy po prostu robisz przerwę? Twoja odpowiedź może ulepszyć przyszłe sugestie.",
    "Activity insights": "Analiza aktywności",
    "Understand which tools help you perform":
      "Zrozum, które narzędzia pomagają Ci osiągać wyniki",
    "Compare the applications and websites expected for a task with the tools that were actually used, then correct classifications at any time":
      "Porównaj aplikacje i strony oczekiwane dla zadania z narzędziami, których faktycznie użyto, a następnie w każdej chwili popraw klasyfikacje.",
    "Visual Studio Code supported most of this development session":
      "Visual Studio Code wspierał większą część tej sesji programistycznej",
    "The browser was used mainly for documentation research":
      "Przeglądarka była używana głównie do przeglądania dokumentacji",
    "One recurring application still needs a task assignment":
      "Jedna często używana aplikacja nadal wymaga przypisania do zadania",
    "Application report": "Raport aplikacji",
    "Build synchronization engine": "Zbuduj mechanizm synchronizacji",
    "Primary application": "Główna aplikacja",
    Productive: "Produktywna",
    "Web browser": "Przeglądarka internetowa",
    "28 minutes": "28 minut",
    Research: "Badania",
    Email: "E-mail",
    "11 minutes": "11 minut",
    Communication: "Komunikacja",
    "Video platform": "Platforma wideo",
    "14 minutes": "14 minut",
    "Needs review": "Wymaga sprawdzenia",
    "Coaching based on your actual behavior":
      "Coaching oparty na Twoim rzeczywistym zachowaniu",
    "Friendly suggestions use today’s schedule, active or paused work, roadmap priorities and your coaching preferences. You remain in control":
      "Przyjazne sugestie wykorzystują dzisiejszy plan, aktywną lub wstrzymaną pracę, priorytety mapy drogowej i Twoje preferencje coachingu. To Ty zachowujesz kontrolę.",
    "Start delays": "Opóźnienia rozpoczęcia",
    Workload: "Obciążenie pracą",
    "Roadmap risk": "Ryzyko mapy drogowej",
    "Break quality": "Jakość przerw",
    Distraction: "Rozproszenie",
    "Micro-sessions": "Mikrosesje",
    "Coaching insight": "Wskazówka coachingu",
    "Start with less friction": "Zacznij z mniejszym wysiłkiem",
    "High confidence": "Wysoka pewność",
    "Your Work tasks usually begin": "Twoje zadania służbowe zwykle zaczynają się",
    "17 minutes late": "17 minut później",
    "This recommendation is based on your previous 12 Work sessions":
      "Ta rekomendacja opiera się na Twoich poprzednich 12 sesjach służbowych",
    "Suggested action": "Sugerowane działanie",
    "Move the preparation reminder 10 minutes earlier":
      "Przesuń przypomnienie o przygotowaniu o 10 minut wcześniej",
    "Apply suggestion": "Zastosuj sugestię",
    Helpful: "Pomocna",
    "Not helpful": "Niepomocna",
    "Wrong time": "Nieodpowiednia pora",
    "Current focus": "Aktualne skupienie",
    "Start on Windows. Continue on Android":
      "Rozpocznij na Windowsie. Kontynuuj na Androidzie",
    "Start, pause or resume the same task from Windows or Android. Tasks, roadmaps, settings and approved work stay consistent when devices are online":
      "Rozpocznij, wstrzymaj lub wznów to samo zadanie na Windowsie albo Androidzie. Zadania, mapy drogowe, ustawienia i zatwierdzona praca pozostają spójne, gdy urządzenia są online.",
    "Start on Windows": "Rozpocznij na Windowsie",
    "View on Android": "Zobacz na Androidzie",
    "Continue on Windows": "Kontynuuj na Windowsie",
    "Immediate local button response": "Natychmiastowa lokalna reakcja przycisku",
    "Local timer calculation": "Lokalne obliczanie timera",
    "Duplicate-command protection": "Ochrona przed zduplikowanymi poleceniami",
    "One shared active task and session state":
      "Jedno wspólne aktywne zadanie i stan sesji",
    "Offline operation": "Działanie offline",
    "Your work does not stop when the internet does":
      "Twoja praca nie zatrzymuje się, gdy znika internet",
    "Create tasks, update roadmaps and keep working without a connection. Saved changes synchronize safely when your device reconnects":
      "Twórz zadania, aktualizuj mapy drogowe i pracuj bez połączenia. Zapisane zmiany bezpiecznie synchronizują się po ponownym połączeniu urządzenia.",
    Offline: "Offline",
    "3 changes waiting safely": "3 zmiany bezpiecznie czekają",
    Connected: "Połączono",
    "All changes synchronized": "Wszystkie zmiany zsynchronizowane",
    "Privacy and control": "Prywatność i kontrola",
    "Detailed insights under your control": "Szczegółowe informacje pod Twoją kontrolą",
    "You choose which activity DayVector may record and whether selected data remains local or is synchronized":
      "Ty wybierasz, jaką aktywność DayVector może rejestrować oraz czy wybrane dane pozostają lokalne, czy są synchronizowane.",
    "DayVector does not upload browser cookies, website login tokens, clipboard contents, form contents or unencrypted passwords":
      "DayVector nie przesyła plików cookie przeglądarki, tokenów logowania do stron, zawartości schowka, treści formularzy ani niezaszyfrowanych haseł.",
    "View Privacy Policy": "Zobacz politykę prywatności",
    "View Terms of Use": "Zobacz warunki korzystania",
    "Activity privacy": "Prywatność aktywności",
    "Your choices": "Twoje wybory",
    "Track applications": "Śledź aplikacje",
    "Track window titles": "Śledź tytuły okien",
    "Track domains only": "Śledź tylko domeny",
    "Track full URLs": "Śledź pełne adresy URL",
    "Keep selected history local": "Zachowaj wybraną historię lokalnie",
    "Pause tracking": "Wstrzymaj śledzenie",
    "Delete activity history": "Usuń historię aktywności",
    Review: "Sprawdź",
    "The operational view": "Widok operacyjny",
    "Everything important, visible in one place":
      "Wszystko, co ważne, widoczne w jednym miejscu",
    "DayVector dashboard showing task suggestions, schedule, workload and overdue responsibilities":
      "Panel DayVector z sugestiami zadań, planem, obciążeniem i zaległymi obowiązkami",
    "Today’s responsibilities, active work, roadmap progress, unresolved activity and coaching direction in one focused dashboard":
      "Dzisiejsze obowiązki, aktywna praca, postęp mapy drogowej, nierozstrzygnięta aktywność i kierunek coachingu na jednym przejrzystym panelu.",
    "Task suggestions": "Sugestie zadań",
    "Today's workload": "Dzisiejsze obciążenie",
    Schedule: "Harmonogram",
    "Clear current task state": "Jasny stan bieżącego zadania",
    "Next suggested responsibility": "Sugerowany następny obowiązek",
    "Today’s schedule and workload": "Dzisiejszy harmonogram i obciążenie",
    "Overdue work and items needing attention":
      "Zaległa praca i elementy wymagające uwagi",
    "Dynamic coaching and synchronization status":
      "Dynamiczny coaching i stan synchronizacji",
    "Dynamic coaching": "Dynamiczny coaching",
    "DayVector coaching carousel with several evidence-based suggestions":
      "Karuzela coachingu DayVector z kilkoma sugestiami opartymi na danych",
    "Several suggestions, always in your control":
      "Kilka sugestii, zawsze pod Twoją kontrolą",
    "DayVector Activity view grouping useful application time without losing individual periods":
      "Widok aktywności DayVector grupujący przydatny czas w aplikacjach bez utraty pojedynczych okresów",
    "Clear, editable classifications": "Jasne, edytowalne klasyfikacje",
    "Direct contact": "Bezpośredni kontakt",
    "Questions, feedback or support?": "Pytania, opinie lub pomoc?",
    "Contact the creator of DayVector for help with the app, privacy questions, feedback, bug reports, feature suggestions or general enquiries":
      "Skontaktuj się z twórcą DayVector, aby uzyskać pomoc z aplikacją, zapytać o prywatność, przekazać opinię, zgłosić błąd, zaproponować funkcję lub zadać ogólne pytanie.",
    "Created and maintained by": "Stworzone i utrzymywane przez",
    "Contact Y. A. Diab": "Skontaktuj się z Y. A. Diabem",
    "Email Y. A. Diab about DayVector": "Napisz do Y. A. Diaba w sprawie DayVector",
    "Application support": "Pomoc dotycząca aplikacji",
    "Privacy questions": "Pytania dotyczące prywatności",
    "Bug reports": "Zgłoszenia błędów",
    "Feature suggestions": "Sugestie funkcji",
    "Build a better system for your time": "Zbuduj lepszy system dla swojego czasu",
    "Download DayVector and begin turning long-term goals into practical, measurable daily progress":
      "Pobierz DayVector i zacznij zamieniać długoterminowe cele w praktyczny, mierzalny codzienny postęp.",
    "Recommended for your device": "Polecane dla Twojego urządzenia",
    "DayVector for Windows": "DayVector dla Windows",
    "Designed for Windows 10 and Windows 11": "Zaprojektowane dla Windows 10 i Windows 11",
    Installer: "Instalator",
    "64-bit EXE": "64-bitowy EXE",
    Size: "Rozmiar",
    "Shown on GitHub": "Wyświetlane na GitHubie",
    "Checking release…": "Sprawdzanie wydania…",
    "Release notes": "Informacje o wydaniu",
    "Installation help": "Pomoc w instalacji",
    "DayVector for Android": "DayVector dla Androida",
    "Designed for Android phones and tablets":
      "Zaprojektowane dla telefonów i tabletów z Androidem",
    Package: "Pakiet",
    "Signed APK": "Podpisany APK",
    "A personal planning, execution and performance-coaching system for Windows and Android":
      "Osobisty system planowania, realizacji i coachingu wyników dla Windowsa i Androida",
    Product: "Produkt",
    "Android Widget": "Widżet Androida",
    "Free Pomodoro": "Bezpłatne Pomodoro",
    Legal: "Informacje prawne",
    "Privacy Policy": "Polityka prywatności",
    "Terms of Use": "Warunki korzystania",
    "Support and feedback": "Pomoc i opinie",
    "Windows and Android": "Windows i Android",
    "DayVector Release Notes": "Informacje o wydaniu DayVector",
    "Release date available with the notes": "Data wydania dostępna w informacjach",
    "Close release notes": "Zamknij informacje o wydaniu",
    "Loading release notes…": "Wczytywanie informacji o wydaniu…",
    "Latest published release": "Najnowsze opublikowane wydanie",
    "Release notes are temporarily unavailable":
      "Informacje o wydaniu są tymczasowo niedostępne",
    "Try loading the notes again shortly.":
      "Spróbuj wczytać informacje ponownie za chwilę.",
    "Try again": "Spróbuj ponownie",
    Close: "Zamknij",
    "Release date unavailable": "Data wydania niedostępna",
    "Size unavailable": "Rozmiar niedostępny",
    "Coming soon!": "Wkrótce!",
    "Available with the release": "Dostępne wraz z wydaniem",
    "Checking…": "Sprawdzanie…",
    "Privacy Policy for DayVector": "Polityka prywatności DayVector",
    "Privacy choices and data-handling information for DayVector.":
      "Informacje o wyborach prywatności i przetwarzaniu danych w DayVector.",
    "← Back to privacy overview": "← Wróć do przeglądu prywatności",
    "Your activity stays under your control": "Twoja aktywność pozostaje pod Twoją kontrolą",
    "Effective 25 July 2026": "Obowiązuje od 25 lipca 2026 r.",
    "DayVector is a planning, execution and performance-coaching application created and maintained by Y. A. Diab. This policy explains the categories of information the application may process and the choices available to you.":
      "DayVector to aplikacja do planowania, realizacji i coachingu wyników, stworzona i utrzymywana przez Y. A. Diaba. Ta polityka wyjaśnia, jakie kategorie informacji aplikacja może przetwarzać i jakie masz możliwości wyboru.",
    "Information you provide": "Informacje, które podajesz",
    "This may include account details, profile preferences, tasks, roadmaps, notes, reminders, resources and feedback. Authentication is provided through Supabase. Google sign-in, when selected, is processed by Google and Supabase.":
      "Może to obejmować dane konta, preferencje profilu, zadania, mapy drogowe, notatki, przypomnienia, materiały i opinie. Uwierzytelnianie zapewnia Supabase. Wybrane logowanie przez Google jest przetwarzane przez Google i Supabase.",
    "Optional activity information": "Opcjonalne informacje o aktywności",
    "With your permission, DayVector may process application usage, window titles, website domains or URLs, document activity, idle state and manually recorded off-device work. Controls in the application determine which categories are enabled and whether supported activity remains local or is synchronized.":
      "Za Twoją zgodą DayVector może przetwarzać użycie aplikacji, tytuły okien, domeny lub adresy URL stron, aktywność w dokumentach, stan bezczynności i ręcznie rejestrowaną pracę poza urządzeniem. Ustawienia aplikacji określają, które kategorie są włączone oraz czy obsługiwana aktywność pozostaje lokalna, czy jest synchronizowana.",
    "Information DayVector does not upload": "Informacje, których DayVector nie przesyła",
    "The application is designed not to upload browser cookies, website login tokens, clipboard contents, form contents, banking-session information, email-session tokens or unencrypted passwords.":
      "Aplikacja została zaprojektowana tak, aby nie przesyłać plików cookie przeglądarki, tokenów logowania do stron, zawartości schowka, treści formularzy, informacji o sesjach bankowych, tokenów sesji e-mail ani niezaszyfrowanych haseł.",
    "Why information is used": "Dlaczego używamy informacji",
    "Information is used to operate requested features, synchronize connected devices, calculate progress and reports, detect unresolved activity, improve schedules, deliver notifications and generate explainable coaching. Optional data is not treated as medical diagnosis.":
      "Informacje są używane do działania wybranych funkcji, synchronizacji połączonych urządzeń, obliczania postępu i raportów, wykrywania nierozstrzygniętej aktywności, ulepszania harmonogramów, dostarczania powiadomień oraz tworzenia zrozumiałego coachingu. Dane opcjonalne nie są traktowane jako diagnoza medyczna.",
    "Storage and service providers": "Przechowywanie i dostawcy usług",
    "DayVector stores working data locally on your device. When synchronization is enabled, account data may be processed by Supabase infrastructure. Platform services may also process data needed for sign-in, notifications, software downloads and operating-system integrations.":
      "DayVector przechowuje dane robocze lokalnie na Twoim urządzeniu. Gdy synchronizacja jest włączona, dane konta mogą być przetwarzane przez infrastrukturę Supabase. Usługi platform mogą również przetwarzać dane potrzebne do logowania, powiadomień, pobierania oprogramowania i integracji z systemem operacyjnym.",
    "Your controls": "Twoje ustawienia",
    "Depending on the feature status and platform, you can pause tracking, exclude applications or websites, correct classifications, remove history, keep selected information local, revoke device access, export account data and request account deletion.":
      "W zależności od statusu funkcji i platformy możesz wstrzymać śledzenie, wykluczyć aplikacje lub strony, poprawić klasyfikacje, usunąć historię, zachować wybrane informacje lokalnie, cofnąć dostęp urządzenia, wyeksportować dane konta i zażądać usunięcia konta.",
    "Security and sensitive features": "Bezpieczeństwo i funkcje wrażliwe",
    "DayVector uses platform and service security controls appropriate to each feature. Planned security-sensitive features are not represented as available until their implementation and review are complete.":
      "DayVector korzysta z zabezpieczeń platform i usług odpowiednich dla każdej funkcji. Planowane funkcje związane z bezpieczeństwem nie są oznaczane jako dostępne, dopóki ich wdrożenie i przegląd nie zostaną ukończone.",
    "Changes to this policy": "Zmiany w tej polityce",
    "This policy may be updated as DayVector evolves. The effective date above will change when material revisions are published.":
      "Ta polityka może być aktualizowana wraz z rozwojem DayVector. Powyższa data obowiązywania zmieni się po opublikowaniu istotnych zmian.",
    "For privacy questions, email": "W sprawach dotyczących prywatności napisz na adres",
    "Terms of Service for DayVector": "Warunki korzystania z DayVector",
    "Terms governing use of the DayVector application.":
      "Warunki korzystania z aplikacji DayVector.",
    "← Back to DayVector": "← Wróć do DayVector",
    "Terms of service": "Warunki korzystania",
    "Clear terms for using DayVector": "Jasne warunki korzystania z DayVector",
    "These terms apply to your use of DayVector, an application created and maintained by Y. A. Diab. By creating an account or using the application, you agree to use it lawfully and in accordance with these terms.":
      "Te warunki dotyczą korzystania z DayVector, aplikacji stworzonej i utrzymywanej przez Y. A. Diaba. Tworząc konto lub korzystając z aplikacji, zgadzasz się używać jej zgodnie z prawem i tymi warunkami.",
    "Purpose of the application": "Cel aplikacji",
    "DayVector provides tools for planning, task execution, time and activity review, roadmaps, reports and performance coaching. Features marked Beta or Planned may change, remain incomplete or be unavailable on some platforms.":
      "DayVector udostępnia narzędzia do planowania, wykonywania zadań, przeglądu czasu i aktywności, map drogowych, raportów oraz coachingu wyników. Funkcje oznaczone jako Beta lub Planowane mogą się zmieniać, pozostać niekompletne albo być niedostępne na niektórych platformach.",
    "Your account and content": "Twoje konto i treści",
    "You are responsible for safeguarding your sign-in methods, maintaining accurate account information and keeping appropriate backups of important content. You retain responsibility for the tasks, notes, resources and other content you add.":
      "Odpowiadasz za ochronę swoich metod logowania, aktualność danych konta oraz odpowiednie kopie zapasowe ważnych treści. Zachowujesz odpowiedzialność za dodawane zadania, notatki, materiały i inne treści.",
    "Acceptable use": "Dopuszczalne korzystanie",
    "Do not use DayVector to violate law, infringe the rights of others, attempt unauthorized access, distribute malicious software or interfere with the application and its supporting services.":
      "Nie używaj DayVector do łamania prawa, naruszania praw innych osób, prób nieuprawnionego dostępu, rozpowszechniania złośliwego oprogramowania ani zakłócania działania aplikacji i usług ją wspierających.",
    "Updates and availability": "Aktualizacje i dostępność",
    "Software updates may add, change or remove features. You choose whether to install an offered desktop or Android package, and the operating system may require additional confirmation. Availability can be affected by device, network and third-party service conditions.":
      "Aktualizacje oprogramowania mogą dodawać, zmieniać lub usuwać funkcje. To Ty decydujesz, czy zainstalować oferowany pakiet desktopowy lub Androida, a system operacyjny może wymagać dodatkowego potwierdzenia. Dostępność może zależeć od urządzenia, sieci i usług innych firm.",
    "Productivity and coaching information": "Informacje o produktywności i coachingu",
    "DayVector provides planning, productivity and performance information. It does not provide medical, psychological, legal, financial or professional diagnosis or treatment.":
      "DayVector dostarcza informacje o planowaniu, produktywności i wynikach. Nie zapewnia diagnozy ani leczenia medycznego, psychologicznego, prawnego, finansowego lub zawodowego.",
    "No guaranteed outcome": "Brak gwarantowanego wyniku",
    "Forecasts and recommendations depend on available information and may be incomplete or inaccurate. You remain in control of decisions, classifications, schedules and progress.":
      "Prognozy i rekomendacje zależą od dostępnych informacji i mogą być niepełne lub niedokładne. Nadal kontrolujesz decyzje, klasyfikacje, harmonogramy i postęp.",
    "Ending use": "Zakończenie korzystania",
    "You may stop using the application and, when available in the account controls, request deletion of synchronized account information. Some records may be retained temporarily where required for security, integrity or legal reasons.":
      "Możesz przestać korzystać z aplikacji oraz, gdy jest to dostępne w ustawieniach konta, poprosić o usunięcie zsynchronizowanych informacji konta. Niektóre zapisy mogą być tymczasowo zachowane, jeśli wymagają tego względy bezpieczeństwa, integralności lub prawo.",
    "For support or questions about these terms, contact Y. A. Diab at":
      "Aby uzyskać pomoc lub zadać pytanie dotyczące tych warunków, skontaktuj się z Y. A. Diabem pod adresem",
    "Installation Help for DayVector": "Pomoc w instalacji DayVector",
    "Install DayVector on Windows, Android phones and Android tablets.":
      "Zainstaluj DayVector na Windowsie, telefonach i tabletach z Androidem.",
    "← Back to downloads": "← Wróć do pobierania",
    "Get DayVector running": "Uruchom DayVector",
    "Applies to the version shown on the download card":
      "Dotyczy wersji widocznej na karcie pobierania",
    "Windows 10 and Windows 11": "Windows 10 i Windows 11",
    "Download the Windows installer from the official GitHub release.":
      "Pobierz instalator Windows z oficjalnego wydania na GitHubie.",
    "Open the downloaded DayVector Windows installer.":
      "Otwórz pobrany instalator DayVector dla Windows.",
    "Review any Windows security prompt, then continue the installer.":
      "Przejrzyj ewentualny monit zabezpieczeń Windows, a następnie kontynuuj instalację.",
    "Launch DayVector from the Start menu or desktop shortcut.":
      "Uruchom DayVector z menu Start lub skrótu na pulpicie.",
    "Android phones and tablets": "Telefony i tablety z Androidem",
    "Download the signed DayVector Android package.":
      "Pobierz podpisany pakiet DayVector dla Androida.",
    "Open the downloaded APK from your browser or Files application.":
      "Otwórz pobrany plik APK w przeglądarce lub aplikacji Pliki.",
    "If Android asks, allow installation from that source for this install.":
      "Jeśli Android o to poprosi, zezwól na instalację z tego źródła dla tej instalacji.",
    "Review the package details and confirm installation.":
      "Sprawdź szczegóły pakietu i potwierdź instalację.",
    "DayVector never starts an installation without your action. Windows may show a reputation warning for a new, unsigned release, and Android requires confirmation before installing an APK outside an app store.":
      "DayVector nigdy nie rozpoczyna instalacji bez Twojego działania. Windows może wyświetlić ostrzeżenie o reputacji dla nowego, niepodpisanego wydania, a Android wymaga potwierdzenia przed zainstalowaniem pliku APK spoza sklepu z aplikacjami.",
    "Check your download": "Sprawdź pobrany plik",
    "Every official release includes a verification file beside each installer. You can use it to confirm that the download has not changed before opening it.":
      "Każde oficjalne wydanie zawiera plik weryfikacyjny obok każdego instalatora. Możesz go użyć, aby potwierdzić, że pobrany plik nie zmienił się przed otwarciem.",
    "Need help?": "Potrzebujesz pomocy?",
    "Email Y. A. Diab at": "Napisz do Y. A. Diaba na adres",
    "A free, adjustable Pomodoro timer from DayVector that remembers the current session and settings locally in your browser.":
      "Bezpłatny, regulowany timer Pomodoro od DayVector, który zapamiętuje bieżącą sesję i ustawienia lokalnie w przeglądarce.",
    "Free Pomodoro Timer from DayVector": "Bezpłatny timer Pomodoro od DayVector",
    "Run an adjustable focus timer that resumes where you left off, with an accessible guide to the Pomodoro Technique.":
      "Uruchom regulowany timer skupienia, który wznawia pracę od miejsca zakończenia, z przystępnym przewodnikiem po technice Pomodoro.",
    Timer: "Timer",
    "How to use it": "Jak z niego korzystać",
    "Android widget": "Widżet Androida",
    "Free, private and ready without an account":
      "Bezpłatny, prywatny i gotowy bez konta",
    "Make the next": "Spraw, aby następne",
    "25 minutes": "25 minut",
    "count.": "miało znaczenie.",
    "Pick one meaningful task, focus for a bounded interval and take a real break. This timer remembers your session in this browser, even when you close the tab.":
      "Wybierz jedno ważne zadanie, skup się przez określony czas i zrób prawdziwą przerwę. Ten timer zapamiętuje sesję w tej przeglądarce, nawet po zamknięciu karty.",
    "Timer capabilities": "Możliwości timera",
    "Remembers your timer on this device": "Zapamiętuje timer na tym urządzeniu",
    "Adjustable intervals": "Regulowane interwały",
    "Responsive everywhere": "Responsywny wszędzie",
    "What is the Pomodoro Technique?": "Czym jest technika Pomodoro?",
    "History, practical guidance and research context":
      "Historia, praktyczne wskazówki i kontekst badawczy",
    "Browser Pomodoro": "Pomodoro w przeglądarce",
    "Saved only in this browser": "Zapisane tylko w tej przeglądarce",
    "Local saving unavailable": "Lokalny zapis niedostępny",
    "What are you moving forward?": "Co chcesz posunąć do przodu?",
    "e.g. Review chapter 4": "np. Przejrzyj rozdział 4",
    "Choose timer phase": "Wybierz fazę timera",
    "Pomodoro controls": "Sterowanie Pomodoro",
    Reset: "Resetuj",
    "Start focus": "Rozpocznij skupienie",
    "Start break": "Rozpocznij przerwę",
    Skip: "Pomiń",
    "Ready when you are. Your progress stays on this device.":
      "Gotowe, gdy Ty jesteś gotowy. Twój postęp pozostaje na tym urządzeniu.",
    "Focus is running. Keep this interval for one clear task.":
      "Skupienie trwa. Zachowaj ten interwał dla jednego jasnego zadania.",
    "Break is running. Step away from the task if you can.":
      "Trwa przerwa. Odsuń się od zadania, jeśli możesz.",
    "Break complete. Your next focus is ready.":
      "Przerwa zakończona. Twoje następne skupienie jest gotowe.",
    "Focus complete. Take a deliberate break.":
      "Skupienie zakończone. Zrób świadomą przerwę.",
    "Adjust timer": "Dostosuj timer",
    "Focus minutes": "Minuty skupienia",
    "Focuses per round": "Sesje skupienia na rundę",
    "Start breaks automatically": "Rozpoczynaj przerwy automatycznie",
    "Start the next focus automatically": "Rozpoczynaj następne skupienie automatycznie",
    "Play a gentle completion tone": "Odtwarzaj łagodny dźwięk ukończenia",
    "Restore recommended times": "Przywróć zalecane czasy",
    "Your timer stays on this device and is ready when you return. Nothing is sent to DayVector.":
      "Twój timer pozostaje na tym urządzeniu i jest gotowy, gdy wrócisz. Nic nie jest wysyłane do DayVector.",
    "A gentle starting ritual": "Łagodny rytuał rozpoczęcia",
    "Use the interval to protect attention, not to race the clock":
      "Użyj interwału, aby chronić uwagę, a nie ścigać się z czasem",
    "The familiar 25-minute timer is a useful entry point. The complete technique also includes planning, handling interruptions, recording effort and learning from each cycle.":
      "Znany 25-minutowy timer jest dobrym punktem wyjścia. Pełna technika obejmuje także planowanie, radzenie sobie z przerwami, zapisywanie wysiłku i wyciąganie wniosków z każdego cyklu.",
    "Choose one clear outcome": "Wybierz jeden jasny rezultat",
    "Write a task small enough to move during one focused interval.":
      "Zapisz zadanie na tyle małe, aby posunąć je naprzód podczas jednego interwału skupienia.",
    "Start and protect the interval": "Rozpocznij i chroń interwał",
    "Put avoidable distractions aside; note interruptions instead of chasing them.":
      "Odłóż możliwe do uniknięcia rozproszenia; zapisuj przerwy zamiast za nimi podążać.",
    "Stop when the timer ends": "Zatrzymaj się, gdy timer się skończy",
    "Take the break seriously. Stand, breathe, drink water or let your attention reset.":
      "Potraktuj przerwę poważnie. Wstań, odetchnij, napij się wody lub pozwól swojej uwadze się zresetować.",
    "Review, then begin again": "Sprawdź, a potem zacznij ponownie",
    "After several focuses, take a longer break and adjust the durations to fit your work.":
      "Po kilku sesjach skupienia zrób dłuższą przerwę i dostosuj czasy do swojej pracy.",
    "Go deeper into learning": "Pogłęb naukę",
    "A useful companion:": "Pomocne uzupełnienie:",
    "Barbara Oakley’s book explains practical approaches to learning difficult material, overcoming procrastination and moving between focused and more diffuse modes of thinking. Its strategies apply beyond mathematics and science.":
      "Książka Barbary Oakley wyjaśnia praktyczne podejścia do nauki trudnego materiału, pokonywania prokrastynacji oraz przechodzenia między skupionym i bardziej rozproszonym sposobem myślenia. Jej strategie przydają się nie tylko w matematyce i naukach ścisłych.",
    "Read about the book": "Przeczytaj o książce",
    "Product website": "Strona produktu",
    Terms: "Warunki",
    "A practical introduction": "Praktyczne wprowadzenie",
    "The idea behind the Pomodoro Technique": "Idea techniki Pomodoro",
    "Close Pomodoro information": "Zamknij informacje o Pomodoro",
    "Who created it?": "Kto ją stworzył?",
    "Francesco Cirillo created the technique while he was a university student in the late 1980s, using a tomato-shaped kitchen timer. The name comes from the Italian word for tomato. Cirillo emphasizes that the timer is only one part of a broader system for planning, managing interruptions, estimating effort and improving how you work.":
      "Francesco Cirillo stworzył tę technikę jako student pod koniec lat 80., używając kuchennego minutnika w kształcie pomidora. Nazwa pochodzi od włoskiego słowa oznaczającego pomidor. Cirillo podkreśla, że timer jest tylko jedną częścią szerszego systemu planowania, zarządzania przerwami, szacowania wysiłku i doskonalenia sposobu pracy.",
    "How can a timer help?": "Jak może pomóc timer?",
    "A bounded interval can lower the barrier to starting, make interruptions visible and create a deliberate stopping point. Research by Atsunori Ariga and Alejandro Lleras found that brief, rare breaks helped prevent a decline in performance during a sustained-attention task. That does not make one duration perfect for everyone. Adjust the timer to the work and to your needs.":
      "Ograniczony interwał może ułatwić rozpoczęcie, uwidocznić przerwy i stworzyć świadomy moment zatrzymania. Badania Atsunoriego Arigi i Alejandra Llerasa wykazały, że krótkie, rzadkie przerwy pomagały zapobiegać spadkowi wyników podczas zadania wymagającego długotrwałej uwagi. Nie oznacza to, że jeden czas jest idealny dla wszystkich. Dostosuj timer do pracy i swoich potrzeb.",
    "A simple first cycle": "Prosty pierwszy cykl",
    "Choose one task and define what “moved forward” will mean.":
      "Wybierz jedno zadanie i określ, co będzie oznaczać „posunięcie do przodu”.",
    "Focus for 25 minutes, recording interruptions instead of following them.":
      "Skupiaj się przez 25 minut, zapisując przerwy zamiast im ulegać.",
    "Stop and take a short break when the interval ends.":
      "Zatrzymaj się i zrób krótką przerwę, gdy interwał się skończy.",
    "After four focus intervals, take a longer break and review the pattern.":
      "Po czterech interwałach skupienia zrób dłuższą przerwę i przejrzyj wzorzec.",
    "The timer is a tool, not a score. Even the creator cautions against reducing the full technique to collecting as many 25-minute intervals as possible.":
      "Timer jest narzędziem, a nie wynikiem. Nawet twórca ostrzega przed sprowadzaniem pełnej techniki do zbierania jak największej liczby 25-minutowych interwałów.",
    "Sources and further reading": "Źródła i dalsza lektura",
    "Francesco Cirillo: creator’s account and philosophy":
      "Francesco Cirillo: opis i filozofia twórcy",
    "Official Pomodoro Technique overview": "Oficjalne omówienie techniki Pomodoro",
    "Ariga & Lleras (2011),": "Ariga i Lleras (2011),",
    ": brief mental breaks and vigilance":
      ": krótkie przerwy umysłowe i czujność",
    "Barbara Oakley:": "Barbara Oakley:",
    "Pomodoro® is a registered trademark of Francesco Cirillo. This independent educational timer is not affiliated with or endorsed by Francesco Cirillo.":
      "Pomodoro® jest zarejestrowanym znakiem towarowym Francesco Cirillo. Ten niezależny timer edukacyjny nie jest powiązany z Francesco Cirillo ani przez niego popierany.",
    "Start a focus interval": "Rozpocznij interwał skupienia",
    "The same live session as the app": "Ta sama sesja na żywo co w aplikacji",
    "Health context without clutter": "Kontekst zdrowia bez nadmiaru informacji",
    "See movement and recovery beside your work":
      "Zobacz ruch i regenerację obok swojej pracy",
    "With your permission, DayVector reads the health summaries you choose to share and presents them in a calm daily view. It helps you notice when movement, rest and focused work are supporting each other.":
      "Za Twoją zgodą DayVector odczytuje wybrane przez Ciebie podsumowania zdrowia i prezentuje je w spokojnym widoku dziennym. Pomaga zauważyć, kiedy ruch, odpoczynek i skupiona praca wzajemnie się wspierają.",
    "A clear view of today": "Jasny widok na dziś",
    "Steps, distance, active energy and workouts at a glance":
      "Kroki, dystans, aktywna energia i treningi na pierwszy rzut oka",
    "Your week in motion": "Twój tydzień w ruchu",
    "Readable values and a simple seven-day movement chart":
      "Czytelne wartości i prosty siedmiodniowy wykres ruchu",
    "Health sources together": "Źródła zdrowia w jednym miejscu",
    "Connected watches and health applications in one tidy place":
      "Połączone zegarki i aplikacje zdrowotne w jednym uporządkowanym miejscu",
    "Useful on Windows too": "Przydatne także na Windowsie",
    "Daily summaries stay readable across your signed-in devices":
      "Codzienne podsumowania pozostają czytelne na zalogowanych urządzeniach",
    "Swipe down to refresh": "Przeciągnij w dół, aby odświeżyć",
    "Read-only access": "Dostęp tylko do odczytu",
    "Captured from the Android app": "Zrzut z aplikacji Android",
    "DayVector Health dashboard showing today's steps, distance, active energy and a seven-day movement chart":
      "Panel zdrowia DayVector pokazujący dzisiejsze kroki, dystans, aktywną energię i siedmiodniowy wykres ruchu",
    "DayVector Health dashboard showing today's steps, distance, active energy, workouts and a seven-day movement chart":
      "Panel zdrowia DayVector pokazujący dzisiejsze kroki, dystans, aktywną energię, treningi i siedmiodniowy wykres ruchu",
    "Time does not always follow the schedule. DayVector keeps each activity period available for review and makes sure the same minute is never counted twice":
      "Czas nie zawsze podąża za harmonogramem. DayVector pozostawia każdy okres aktywności dostępny do sprawdzenia i dba o to, by ta sama minuta nigdy nie została policzona dwa razy.",
    "Project task": "Zadanie projektu",
    "Prepare product launch": "Przygotuj premierę produktu",
    "Activity reports": "Raporty aktywności",
    "See where your time actually went": "Zobacz, na co naprawdę poszedł Twój czas",
    "Reports group approved application and website activity by duration. Open the underlying activity whenever you want to review or correct it":
      "Raporty grupują zatwierdzoną aktywność aplikacji i stron według czasu trwania. Otwórz źródłową aktywność, kiedy chcesz ją sprawdzić lub poprawić.",
    "See the time recorded for each application and website":
      "Zobacz czas zarejestrowany dla każdej aplikacji i strony",
    "Connect trusted tools to the task they support":
      "Połącz zaufane narzędzia z zadaniem, które wspierają",
    "Keep uncertain activity ready for your review":
      "Pozostaw niepewną aktywność gotową do sprawdzenia",
    "Example activity report": "Przykładowy raport aktywności",
    "Development session": "Sesja programistyczna",
    Application: "Aplikacja",
    "42 minutes": "42 minuty",
    "Website activity": "Aktywność na stronie",
    "Paused work": "Wstrzymana praca",
    "Overdue tasks": "Zaległe zadania",
    "Roadmap progress": "Postęp mapy drogowej",
    "Rest timing": "Pora odpoczynku",
    "Focus patterns": "Wzorce skupienia",
    "Coaching suggestion": "Sugestia coachingu",
    "Make the roadmap feel possible again":
      "Spraw, aby mapa drogowa znów wydawała się możliwa do zrealizowania",
    "Based on your roadmap": "Na podstawie Twojej mapy drogowej",
    "Part of your roadmap is at risk. Make": "Część Twojej mapy drogowej jest zagrożona. Uczyń",
    "Prepare launch brief": "Przygotuj skrót premiery",
    "the recovery step and leave the rest outside this session":
      "krokiem odzyskiwania i zostaw resztę poza tą sesją",
    "Evidence: 3 open roadmap tasks": "Dane: 3 otwarte zadania mapy drogowej",
    "Next step": "Następny krok",
    "Open the related task and protect one focused session":
      "Otwórz powiązane zadanie i chroń jedną sesję skupienia",
    "Open related task": "Otwórz powiązane zadanie",
    "Not useful": "Nieprzydatne",
    "Wrong timing": "Nieodpowiedni moment",
    "Made to feel at home on Android": "Stworzone, aby naturalnie działać na Androidzie",
  };

  const originalText = new WeakMap();
  const originalAttributes = new WeakMap();
  let language = readLanguage();
  let theme = readTheme();
  let observer = null;

  function readLanguage() {
    const requested = new URLSearchParams(window.location.search).get("lang");
    if (SUPPORTED_LANGUAGES.has(requested)) return requested;
    try {
      const saved = localStorage.getItem(LANGUAGE_STORAGE_KEY);
      return SUPPORTED_LANGUAGES.has(saved) ? saved : "en";
    } catch {
      return "en";
    }
  }

  function normalized(value) {
    return String(value || "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function translatedPattern(value) {
    if (language === "ar") {
      let match = value.match(
        /^(\d+) min focus, (\d+) min short break, (\d+) min long break$/,
      );
      if (match)
        return `${match[1]} د للتركيز، ${match[2]} د للاستراحة القصيرة، ${match[3]} د للاستراحة الطويلة`;

      match = value.match(/^Focus (\d+) of (\d+)$/);
      if (match) return `جلسة التركيز ${match[1]} من ${match[2]}`;

      match = value.match(/^(\d+) focus completed$/);
      if (match) return `اكتملت جلسة تركيز واحدة`;

      match = value.match(/^(\d+) focuses completed$/);
      if (match) return `اكتملت ${match[1]} جلسات تركيز`;

      match = value.match(
        /^(Focus|Short break|Long break) paused\. It will resume from (\d{2}:\d{2})\.$/,
      );
      if (match)
        return `تم إيقاف ${arabic[match[1]] || match[1]} مؤقتاً. سيُستأنف من ${match[2]}.`;

      match = value.match(/^(Short break|Long break) is ready when you are\.$/);
      if (match)
        return `${arabic[match[1]] || match[1]} جاهزة عندما تكون مستعداً.`;

      match = value.match(/^(Focus|Short break|Long break) is ready\.$/);
      if (match) return `${arabic[match[1]] || match[1]} جاهزة.`;

      match = value.match(
        /^(\d{2}:\d{2}) (Focus|Short break|Long break), DayVector$/,
      );
      if (match)
        return `${match[1]} ${arabic[match[2]] || match[2]}، DayVector`;

      match = value.match(/^Version (.+)$/);
      if (match) return `الإصدار ${match[1]}`;

      match = value.match(/^(\d+(?:\.\d+)?) MB$/);
      if (match) return `${match[1]} ميجابايت`;

      return value;
    }

    if (language === "pl") {
      let match = value.match(/^Focus (\d+) of (\d+)$/);
      if (match) return `Skupienie ${match[1]} z ${match[2]}`;
      match = value.match(/^Version (.+)$/);
      if (match) return `Wersja ${match[1]}`;
      return value;
    }

    let match = value.match(
      /^(\d+) min focus, (\d+) min short break, (\d+) min long break$/,
    );
    if (match)
      return `${match[1]} Min. Fokus, ${match[2]} Min. kurze Pause, ${match[3]} Min. lange Pause`;

    match = value.match(/^Focus (\d+) of (\d+)$/);
    if (match) return `Fokus ${match[1]} von ${match[2]}`;

    match = value.match(/^(\d+) focus completed$/);
    if (match) return `${match[1]} Fokusphase abgeschlossen`;

    match = value.match(/^(\d+) focuses completed$/);
    if (match) return `${match[1]} Fokusphasen abgeschlossen`;

    match = value.match(
      /^(Focus|Short break|Long break) paused\. It will resume from (\d{2}:\d{2})\.$/,
    );
    if (match)
      return `${german[match[1]] || match[1]} pausiert. Fortsetzung bei ${match[2]}.`;

    match = value.match(/^(Short break|Long break) is ready when you are\.$/);
    if (match) return `${german[match[1]] || match[1]} ist bereit.`;

    match = value.match(/^(Focus|Short break|Long break) is ready\.$/);
    if (match) return `${german[match[1]] || match[1]} ist bereit.`;

    match = value.match(
      /^(\d{2}:\d{2}) (Focus|Short break|Long break), DayVector$/,
    );
    if (match)
      return `${match[1]} ${german[match[2]] || match[2]}, DayVector`;

    match = value.match(/^Version (.+)$/);
    if (match) return `Version ${match[1]}`;

    return value;
  }

  function translate(value) {
    const clean = normalized(value);
    if (!clean || language === "en") return clean;
    const dictionary =
      language === "ar" ? arabic : language === "pl" ? polish : german;
    return dictionary[clean] || translatedPattern(clean);
  }

  function withOriginalWhitespace(original, replacement) {
    const leading = original.match(/^\s*/)?.[0] || "";
    const trailing = original.match(/\s*$/)?.[0] || "";
    return `${leading}${replacement}${trailing}`;
  }

  function shouldSkip(element) {
    return (
      !element ||
      Boolean(
        element.closest(
          "script, style, noscript, .material-symbols-rounded, [data-i18n-ignore], [data-language-toggle], [data-language-select], [data-theme-toggle]",
        ),
      )
    );
  }

  function renderTextNode(node, refreshOriginal = false) {
    const parent = node.parentElement;
    if (shouldSkip(parent)) return;
    if (refreshOriginal || !originalText.has(node))
      originalText.set(node, node.nodeValue);
    const source = originalText.get(node);
    const clean = normalized(source);
    if (!clean) return;
    const next = language === "en" ? clean : translate(clean);
    node.nodeValue = withOriginalWhitespace(source, next);
  }

  function attributeSources(element) {
    if (!originalAttributes.has(element))
      originalAttributes.set(element, new Map());
    return originalAttributes.get(element);
  }

  function renderAttribute(element, name, refreshOriginal = false) {
    if (shouldSkip(element) || !element.hasAttribute(name)) return;
    const sources = attributeSources(element);
    if (refreshOriginal || !sources.has(name))
      sources.set(name, element.getAttribute(name));
    const source = sources.get(name);
    const next = language === "en" ? source : translate(source);
    element.setAttribute(name, next);
  }

  function renderTree(root, refreshOriginal = false) {
    if (!root) return;
    if (root.nodeType === 3) {
      renderTextNode(root, refreshOriginal);
      return;
    }
    if (root.nodeType !== 1 && root.nodeType !== 9) return;
    const element = root.nodeType === 1 ? root : null;
    if (element && shouldSkip(element)) return;

    const elements = element
      ? [element, ...element.querySelectorAll("*")]
      : [...root.querySelectorAll("*")];
    elements.forEach((candidate) => {
      if (shouldSkip(candidate)) return;
      for (const node of candidate.childNodes) {
        if (node.nodeType === 3) renderTextNode(node, refreshOriginal);
      }
      for (const name of [
        "aria-label",
        "placeholder",
        "title",
        "alt",
        "content",
      ]) {
        renderAttribute(candidate, name, refreshOriginal);
      }
    });
  }

  function updateToggle() {
    document.querySelectorAll("[data-language-select] select").forEach((select) => {
      select.value = language;
      select.setAttribute("aria-label", translate("Select language"));
    });
  }

  function readTheme() {
    try {
      const saved = localStorage.getItem(THEME_STORAGE_KEY);
      if (saved === "dark" || saved === "light") return saved;
    } catch {
      // Use the device preference when storage is unavailable.
    }
    return window.matchMedia?.("(prefers-color-scheme: light)").matches
      ? "light"
      : "dark";
  }

  function themeControlLabel() {
    const switchingToLight = theme === "dark";
    if (language === "de") {
      return switchingToLight
        ? "Helles Design verwenden"
        : "Dunkles Design verwenden";
    }
    if (language === "ar") {
      return switchingToLight ? "استخدم المظهر الفاتح" : "استخدم المظهر الداكن";
    }
    return translate(switchingToLight ? "Use light theme" : "Use dark theme");
  }

  function updateThemeToggle() {
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      const label = themeControlLabel();
      const icon = button.querySelector(".material-symbols-rounded");
      const textLabel = button.querySelector("[data-theme-label]");
      if (icon)
        icon.textContent = theme === "dark" ? "light_mode" : "dark_mode";
      if (textLabel) textLabel.textContent = label;
      button.setAttribute("aria-label", label);
      button.setAttribute("title", label);
    });
  }

  function applyTheme(nextTheme, persist = true) {
    theme = nextTheme === "light" ? "light" : "dark";
    document.documentElement.dataset.theme = theme;
    document.documentElement.style.colorScheme = theme;
    const themeColor = document.querySelector('meta[name="theme-color"]');
    if (themeColor)
      themeColor.setAttribute(
        "content",
        theme === "light" ? "#f7f9fc" : "#101828",
      );
    updateThemeToggle();
    if (persist) {
      try {
        localStorage.setItem(THEME_STORAGE_KEY, theme);
      } catch {
        // The active page still changes theme when storage is unavailable.
      }
    }
  }

  function installThemeToggles() {
    document
      .querySelectorAll("[data-language-select]")
      .forEach((languageControl) => {
        if (languageControl.parentElement?.querySelector("[data-theme-toggle]"))
          return;
        const button = document.createElement("button");
        button.type = "button";
        button.className = "theme-toggle";
        button.dataset.themeToggle = "";
        button.innerHTML =
          '<span class="material-symbols-rounded" aria-hidden="true"></span><span class="visually-hidden" data-theme-label></span>';
        button.addEventListener("click", () =>
          applyTheme(theme === "dark" ? "light" : "dark"),
        );
        languageControl.insertAdjacentElement("afterend", button);
      });
  }

  function startObserver() {
    observer?.disconnect();
    observer = new MutationObserver((records) => {
      observer.disconnect();
      records.forEach((record) => {
        if (record.type === "characterData") {
          renderTextNode(record.target, true);
          return;
        }
        if (record.type === "attributes") {
          renderAttribute(record.target, record.attributeName, true);
          return;
        }
        record.addedNodes.forEach((node) => renderTree(node, true));
      });
      updateToggle();
      startObserver();
    });
    observer.observe(document.documentElement, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: ["aria-label", "placeholder", "title", "alt", "content"],
    });
  }

  function applyLanguage(nextLanguage, persist = true) {
    language = SUPPORTED_LANGUAGES.has(nextLanguage) ? nextLanguage : "en";
    observer?.disconnect();
    document.documentElement.lang = language;
    document.documentElement.dir = language === "ar" ? "rtl" : "ltr";
    renderTree(document);
    updateToggle();
    updateThemeToggle();
    if (persist) {
      try {
        localStorage.setItem(LANGUAGE_STORAGE_KEY, language);
      } catch {
        // The page still switches when storage is unavailable.
      }
      const url = new URL(window.location.href);
      url.searchParams.set("lang", language);
      window.history.replaceState(null, "", url);
    }
    startObserver();
    window.dispatchEvent(
      new CustomEvent("dayvector:languagechange", {
        detail: { language },
      }),
    );
  }

  installThemeToggles();
  applyTheme(theme, false);

  document.querySelectorAll("[data-language-select] select").forEach((select) => {
    select.addEventListener("change", () => applyLanguage(select.value));
  });

  window.DayVectorI18n = {
    get language() {
      return language;
    },
    setLanguage: applyLanguage,
    translate(value) {
      return language === "en" ? normalized(value) : translate(value);
    },
    refresh() {
      observer?.disconnect();
      renderTree(document);
      updateToggle();
      updateThemeToggle();
      startObserver();
    },
  };

  window.DayVectorTheme = {
    get theme() {
      return theme;
    },
    setTheme: applyTheme,
  };

  applyLanguage(language, false);
})();
