# DayVector landing page

Live site: `https://yasser-diab.github.io/DayVector_landing/`

This is a dependency-free static website. Upload the contents of this directory
to any static host.

The standalone browser timer is available at `/pomodoro/`. It stores the
visitor's task label, durations, current phase, round and remaining time only in
that browser's `localStorage`; no account or backend request is required.

The English/German/Arabic switch is implemented by `i18n.js`. The chosen language is
stored locally under `dayvector:site-language`, reflected in the `lang` URL
parameter and applies to the landing,
Pomodoro, privacy, terms and installation-help pages.

The Android widget showcase combines the real, privacy-cleaned phone backdrop
in `assets/images/widget-phone-backdrop.png` with an interactive HTML widget, so
the countdown and controls remain live and responsive.

The Health section uses a real capture from the verified Android DayVector app.
build at `assets/images/health-dashboard-phone-clean.png`. Only the phone's
unrelated media-status indicator was removed from the capture.

The page reads the latest published DayVector release from:

`https://github.com/Yasser-Diab/taskMasterPro/releases`

When a release contains Windows `.exe`, Android `.apk` and Android `.aab` assets, the download
buttons link directly to them. Until then, the page shows that the installers
are not yet published.

To preview locally from the repository root:

```powershell
python -m http.server 4173 --directory landing-page
```

Then open `http://localhost:4173`.
