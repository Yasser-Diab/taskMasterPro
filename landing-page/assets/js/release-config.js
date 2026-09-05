window.DAYVECTOR_RELEASES = Object.freeze({
  repository: 'Yasser-Diab/taskMasterPro',
  tagPrefix: 'v',
  releasesPage: 'https://github.com/Yasser-Diab/taskMasterPro/releases',
  // This endpoint is maintained by GitHub and redirects only to a published
  // release. It is the safe download-page fallback when the public API has
  // exhausted its unauthenticated rate limit.
  latestReleasePage:
    'https://github.com/Yasser-Diab/taskMasterPro/releases/latest',
  latestApiUrl:
    'https://api.github.com/repos/Yasser-Diab/taskMasterPro/releases/latest',
  apiBase:
    'https://api.github.com/repos/Yasser-Diab/taskMasterPro/releases/tags/',
  // The announcement content lives in the dedicated file, so a feature launch
  // can be updated without coupling editorial copy to the release API setup.
  // Resolve from this file rather than the current page: this works for the
  // landing page as well as its nested legal and Pomodoro pages.
  announcementsUrl: new URL(
    '../../announcements.html?v=20260905e',
    document.currentScript?.src || window.location.href,
  ).href,
})
