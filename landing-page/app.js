(() => {
  const header = document.querySelector('[data-header]')
  const menuButton = document.querySelector('[data-menu-button]')
  const navigation = document.getElementById('main-navigation')
  const navigationLinks = navigation
    ? Array.from(navigation.querySelectorAll('a[href^="#"]'))
    : []

  const closeMenu = () => {
    if (!menuButton || !navigation) return
    menuButton.setAttribute('aria-expanded', 'false')
    menuButton.setAttribute('aria-label', 'Open navigation')
    navigation.classList.remove('open')
    document.body.classList.remove('menu-open')
  }

  if (menuButton && navigation) {
    menuButton.addEventListener('click', () => {
      const willOpen = menuButton.getAttribute('aria-expanded') !== 'true'
      menuButton.setAttribute('aria-expanded', String(willOpen))
      menuButton.setAttribute(
        'aria-label',
        willOpen ? 'Close navigation' : 'Open navigation',
      )
      navigation.classList.toggle('open', willOpen)
      document.body.classList.toggle('menu-open', willOpen)
    })

    navigationLinks.forEach((link) => link.addEventListener('click', closeMenu))
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        closeMenu()
        menuButton.focus()
      }
    })
  }

  const updateHeader = () => {
    header?.classList.toggle('scrolled', window.scrollY > 18)
  }
  updateHeader()
  window.addEventListener('scroll', updateHeader, { passive: true })

  const currentYearElement = document.getElementById('current-year')
  if (currentYearElement) {
    currentYearElement.textContent = String(new Date().getFullYear())
  }

  const reducedMotion = window.matchMedia(
    '(prefers-reduced-motion: reduce)',
  ).matches
  const revealElements = Array.from(document.querySelectorAll('.reveal'))
  revealElements.forEach((element) => {
    const delay = Number(element.getAttribute('data-delay') || 0)
    element.style.setProperty('--reveal-delay', `${delay}ms`)
  })

  if (reducedMotion || !('IntersectionObserver' in window)) {
    revealElements.forEach((element) => element.classList.add('is-visible'))
  } else {
    const revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return
          entry.target.classList.add('is-visible')
          observer.unobserve(entry.target)
        })
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.08 },
    )
    revealElements.forEach((element) => revealObserver.observe(element))
  }

  const sectionIds = navigationLinks
    .map((link) => link.getAttribute('href'))
    .filter((href) => href && href.startsWith('#'))
  const sections = sectionIds
    .map((href) => document.querySelector(href))
    .filter(Boolean)

  if ('IntersectionObserver' in window) {
    const navObserver = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((entry) => entry.isIntersecting)
          .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0]
        if (!visible) return
        navigationLinks.forEach((link) => {
          const active = link.getAttribute('href') === `#${visible.target.id}`
          link.classList.toggle('active', active)
          if (active) {
            link.setAttribute('aria-current', 'page')
          } else {
            link.removeAttribute('aria-current')
          }
        })
      },
      { rootMargin: '-25% 0px -62% 0px', threshold: [0.05, 0.2, 0.5] },
    )
    sections.forEach((section) => navObserver.observe(section))
  }

  const userAgent = navigator.userAgent.toLowerCase()
  const likelyPlatform = userAgent.includes('android')
    ? 'android'
    : userAgent.includes('windows')
      ? 'windows'
      : null
  if (likelyPlatform) {
    const card = document.querySelector(
      `[data-platform-card="${likelyPlatform}"]`,
    )
    const recommendation = card?.querySelector('.recommendation')
    card?.classList.add('recommended')
    if (recommendation) recommendation.hidden = false
  }

  const fileSize = (bytes) => {
    if (!Number.isFinite(bytes) || bytes <= 0) return 'Shown on GitHub'
    const megabytes = bytes / (1024 * 1024)
    return `${megabytes.toFixed(megabytes >= 10 ? 0 : 1)} MB`
  }

  const loadLatestRelease = async () => {
    const config = window.TASKMASTER_RELEASES
    if (!config) return

    const fallbackLinks = [
      document.getElementById('windows-download'),
      document.getElementById('android-download'),
    ]
    fallbackLinks.forEach((link) => {
      if (link) link.href = config.releasePage
    })

    try {
      const response = await fetch(config.apiUrl, {
        headers: {
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      })
      if (!response.ok) throw new Error('No published release')
      const release = await response.json()
      const assets = Array.isArray(release.assets) ? release.assets : []
      const windows = assets.find((asset) =>
        String(asset.name).toLowerCase().endsWith('.exe'),
      )
      const android = assets.find((asset) =>
        String(asset.name).toLowerCase().endsWith('.apk'),
      )
      const version = String(release.tag_name || config.currentVersion).replace(
        /^v/i,
        '',
      )

      document
        .querySelectorAll('[data-release-version]')
        .forEach((element) => {
          element.textContent = version
        })

      if (windows) {
        document.getElementById('windows-download').href =
          windows.browser_download_url
        const size = document.querySelector('[data-windows-size]')
        if (size) size.textContent = fileSize(windows.size)
      }
      if (android) {
        document.getElementById('android-download').href =
          android.browser_download_url
        const size = document.querySelector('[data-android-size]')
        if (size) size.textContent = fileSize(android.size)
      }

      const note = document.querySelector('[data-release-note]')
      if (note) {
        note.textContent =
          windows || android
            ? `Latest published release ${version} · Downloads delivered securely by GitHub`
            : 'The latest release page is available while installer assets are being published'
      }
    } catch {
      const note = document.querySelector('[data-release-note]')
      if (note) {
        note.textContent =
          'Open the official GitHub releases page for the latest verified installers'
      }
    }
  }

  loadLatestRelease()
})()
