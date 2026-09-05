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
  announcement: Object.freeze({
    id: 'polish-language-0-0-30',
    message: 'Polish Language Now Available!',
    href: '#download',
    // The site removes an expired announcement without a deploy.  Replace this
    // object for the next feature drop instead of adding another page-body path.
    expiresAt: '2027-03-05T00:00:00.000Z',
  }),
})
