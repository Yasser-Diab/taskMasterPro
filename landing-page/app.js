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

  const widgetDemo = document.querySelector('[data-widget-demo]')
  if (widgetDemo) {
    const widgetCard = widgetDemo.querySelector('[data-widget-card]')
    const widgetCountdown = widgetDemo.querySelector('[data-widget-countdown]')
    const widgetProgress = widgetDemo.querySelector('[data-widget-progress]')
    const widgetLabel = widgetDemo.querySelector('[data-widget-label]')
    const widgetTask = widgetDemo.querySelector('[data-widget-task]')
    const widgetPauseLabel = widgetDemo.querySelector(
      '[data-widget-pause-label]',
    )
    const widgetBreakLabel = widgetDemo.querySelector(
      '[data-widget-break-label]',
    )
    const widgetPauseIcon = widgetDemo.querySelector(
      '[data-widget-action="pause"] .material-symbols-rounded',
    )
    const widgetDurations = { focus: 25 * 60, break: 5 * 60 }
    let widgetMode = 'focus'
    let widgetRemaining = widgetDurations.focus
    let widgetRunning = true
    let widgetDeadline = Date.now() + widgetRemaining * 1000

    const widgetTimeText = (seconds) => {
      const minutes = Math.floor(seconds / 60)
      return `${String(minutes).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`
    }

    const widgetDurationValue = (seconds) =>
      `PT${Math.floor(seconds / 60)}M${seconds % 60}S`

    const renderWidgetDemo = () => {
      const total = widgetDurations[widgetMode]
      if (widgetCountdown) {
        widgetCountdown.textContent = widgetTimeText(widgetRemaining)
        widgetCountdown.setAttribute(
          'datetime',
          widgetDurationValue(widgetRemaining),
        )
      }
      if (widgetProgress) {
        widgetProgress.style.width = `${Math.max(0, Math.min(100, (widgetRemaining / total) * 100))}%`
      }
      if (widgetCard) widgetCard.dataset.mode = widgetMode
      if (widgetLabel) {
        widgetLabel.textContent =
          widgetMode === 'focus' ? 'Focus session' : 'Recovery break'
      }
      if (widgetTask) {
        widgetTask.textContent =
          widgetMode === 'focus' ? 'Deep work session' : 'Time to recharge'
      }
      if (widgetPauseLabel) {
        widgetPauseLabel.textContent = widgetRunning ? 'Pause' : 'Resume'
      }
      if (widgetPauseIcon) {
        widgetPauseIcon.textContent = widgetRunning ? 'pause' : 'play_arrow'
      }
      if (widgetBreakLabel) {
        widgetBreakLabel.textContent = widgetMode === 'focus' ? 'Break' : 'Focus'
      }
    }

    const startWidgetMode = (mode) => {
      widgetMode = mode
      widgetRemaining = widgetDurations[mode]
      widgetRunning = true
      widgetDeadline = Date.now() + widgetRemaining * 1000
      renderWidgetDemo()
    }

    widgetDemo.querySelectorAll('[data-widget-action]').forEach((control) => {
      control.addEventListener('click', () => {
        const action = control.getAttribute('data-widget-action')
        if (action === 'pause') {
          if (widgetRunning) {
            widgetRemaining = Math.max(
              0,
              Math.ceil((widgetDeadline - Date.now()) / 1000),
            )
            widgetRunning = false
          } else {
            widgetRunning = true
            widgetDeadline = Date.now() + widgetRemaining * 1000
          }
        } else if (action === 'break') {
          startWidgetMode(widgetMode === 'focus' ? 'break' : 'focus')
          return
        } else if (action === 'finish') {
          startWidgetMode('focus')
          return
        }
        renderWidgetDemo()
      })
    })

    window.setInterval(() => {
      if (!widgetRunning) return
      const nextRemaining = Math.max(
        0,
        Math.ceil((widgetDeadline - Date.now()) / 1000),
      )
      if (nextRemaining === widgetRemaining) return
      widgetRemaining = nextRemaining
      if (widgetRemaining === 0) {
        startWidgetMode(widgetMode === 'focus' ? 'break' : 'focus')
        return
      }
      renderWidgetDemo()
    }, 250)

    renderWidgetDemo()
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
    if (!Number.isFinite(bytes) || bytes <= 0) return 'Size unavailable'
    const megabytes = bytes / (1024 * 1024)
    return `${megabytes.toFixed(megabytes >= 10 ? 0 : 1)} MB`
  }

  const releaseModal = document.querySelector('[data-release-modal]')
  const releaseModalPanel = document.querySelector('[data-release-modal-panel]')
  const releaseModalBody = document.querySelector('[data-release-modal-body]')
  const releaseModalState = document.querySelector('[data-release-modal-state]')
  const releaseModalVersion = document.querySelector(
    '[data-release-modal-version]',
  )
  const releaseLoadingVersion = document.querySelector(
    '[data-release-loading-version]',
  )
  const releaseModalDate = document.querySelector('[data-release-modal-date]')
  let releaseModalOpener = null
  let selectedReleaseVersion = null
  let latestReleasePromise = null

  const releaseVersion = (release) => {
    const tag = String(release?.tag_name || '')
    const prefix = window.DAYVECTOR_RELEASES?.tagPrefix || 'v'
    return tag.toLowerCase().startsWith(prefix.toLowerCase())
      ? tag.slice(prefix.length)
      : null
  }

  const validPublishedRelease = (release) =>
    Boolean(
      release &&
        release.draft !== true &&
        release.prerelease !== true &&
        releaseVersion(release) &&
        typeof release.body === 'string',
    )

  const loadLatestPublishedRelease = async () => {
    const config = window.DAYVECTOR_RELEASES
    if (!config?.latestApiUrl) {
      throw new Error('Release configuration unavailable')
    }
    if (!latestReleasePromise) {
      latestReleasePromise = fetch(config.latestApiUrl, {
        headers: {
          Accept: 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      })
        .then(async (response) => {
          if (!response.ok) throw new Error('No published release')
          const release = await response.json()
          if (!validPublishedRelease(release)) {
            throw new Error('Invalid published release')
          }
          return release
        })
        .catch((error) => {
          latestReleasePromise = null
          throw error
        })
    }
    return latestReleasePromise
  }

  const appendInlineMarkdown = (parent, source) => {
    const tokenPattern =
      /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)|\*\*([^*]+)\*\*|`([^`]+)`/g
    let cursor = 0
    let match
    while ((match = tokenPattern.exec(source)) !== null) {
      if (match.index > cursor) {
        parent.append(document.createTextNode(source.slice(cursor, match.index)))
      }
      if (match[1] && match[2]) {
        const link = document.createElement('a')
        link.textContent = match[1]
        link.href = match[2]
        link.target = '_blank'
        link.rel = 'noopener noreferrer'
        parent.append(link)
      } else if (match[3]) {
        const strong = document.createElement('strong')
        strong.textContent = match[3]
        parent.append(strong)
      } else if (match[4]) {
        const code = document.createElement('code')
        code.textContent = match[4]
        parent.append(code)
      }
      cursor = tokenPattern.lastIndex
    }
    if (cursor < source.length) {
      parent.append(document.createTextNode(source.slice(cursor)))
    }
  }

  const renderReleaseMarkdown = (markdown) => {
    if (!releaseModalBody) return
    releaseModalBody.replaceChildren()
    const lines = String(markdown || '').replace(/\r/g, '').split('\n')
    let list = null
    let listType = null

    const closeList = () => {
      list = null
      listType = null
    }

    lines.forEach((rawLine) => {
      const line = rawLine.trim()
      if (!line) {
        closeList()
        return
      }
      const heading = line.match(/^(#{1,3})\s+(.+)$/)
      if (heading) {
        closeList()
        const level = Math.min(4, heading[1].length + 1)
        const element = document.createElement(`h${level}`)
        appendInlineMarkdown(element, heading[2])
        releaseModalBody.append(element)
        return
      }
      if (/^---+$/.test(line)) {
        closeList()
        releaseModalBody.append(document.createElement('hr'))
        return
      }
      const unordered = line.match(/^[-*]\s+(.+)$/)
      const ordered = line.match(/^\d+\.\s+(.+)$/)
      if (unordered || ordered) {
        const nextType = ordered ? 'ol' : 'ul'
        if (!list || listType !== nextType) {
          list = document.createElement(nextType)
          listType = nextType
          releaseModalBody.append(list)
        }
        const item = document.createElement('li')
        appendInlineMarkdown(item, (unordered || ordered)[1])
        list.append(item)
        return
      }
      closeList()
      const paragraph = document.createElement('p')
      appendInlineMarkdown(paragraph, line)
      releaseModalBody.append(paragraph)
    })
  }

  const releaseCacheKey = (version) =>
    `dayvector-release-notes:${window.DAYVECTOR_RELEASES?.repository || 'dayvector'}:v${version}`

  const validRelease = (release, version) => {
    const expected = `v${version}`.toLowerCase()
    return (
      release &&
      String(release.tag_name || '').toLowerCase() === expected &&
      release.draft !== true &&
      release.prerelease !== true &&
      typeof release.body === 'string'
    )
  }

  const loadReleaseForVersion = async (version) => {
    const config = window.DAYVECTOR_RELEASES
    if (!config) throw new Error('Release configuration unavailable')
    const cacheKey = releaseCacheKey(version)
    try {
      const cached = JSON.parse(localStorage.getItem(cacheKey) || 'null')
      if (validRelease(cached, version)) return cached
    } catch {
      localStorage.removeItem(cacheKey)
    }

    const tag = `${config.tagPrefix || 'v'}${version}`
    const response = await fetch(`${config.apiBase}${encodeURIComponent(tag)}`, {
      headers: {
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    })
    if (!response.ok) throw new Error('Release unavailable')
    const release = await response.json()
    if (!validRelease(release, version)) throw new Error('Release mismatch')
    localStorage.setItem(cacheKey, JSON.stringify(release))
    return release
  }

  const showReleaseLoading = (version) => {
    const label = version || 'Latest published release'
    if (releaseModalVersion) releaseModalVersion.textContent = version || '—'
    if (releaseLoadingVersion) releaseLoadingVersion.textContent = label
    if (releaseModalDate) {
      releaseModalDate.textContent = 'Release date available with the notes'
    }
    if (releaseModalBody) releaseModalBody.hidden = true
    if (releaseModalState) {
      releaseModalState.hidden = false
      releaseModalState.replaceChildren()
      const spinner = document.createElement('span')
      spinner.className = 'release-modal-spinner'
      spinner.setAttribute('aria-hidden', 'true')
      const title = document.createElement('strong')
      title.textContent = 'Loading release notes…'
      const detail = document.createElement('span')
      detail.textContent = version ? `Version ${version}` : label
      releaseModalState.append(spinner, title, detail)
    }
  }

  const showReleaseFailure = () => {
    if (!releaseModalState) return
    releaseModalState.hidden = false
    releaseModalState.replaceChildren()
    const title = document.createElement('strong')
    title.textContent = 'Release notes are temporarily unavailable'
    const detail = document.createElement('span')
    detail.textContent = 'Try loading the notes again shortly.'
    const actions = document.createElement('div')
    actions.className = 'release-modal-state-actions'
    const retry = document.createElement('button')
    retry.type = 'button'
    retry.className = 'button button-secondary'
    retry.textContent = 'Try again'
    retry.addEventListener('click', () => openReleaseNotes(selectedReleaseVersion))
    const close = document.createElement('button')
    close.type = 'button'
    close.className = 'button button-primary'
    close.textContent = 'Close'
    close.addEventListener('click', closeReleaseNotes)
    actions.append(retry, close)
    releaseModalState.append(title, detail, actions)
  }

  const openReleaseNotes = async (version, opener = null) => {
    if (!releaseModal || !releaseModalPanel) return
    selectedReleaseVersion = version
    if (opener) releaseModalOpener = opener
    releaseModal.hidden = false
    document.body.classList.add('release-modal-open')
    showReleaseLoading(version)
    releaseModalPanel.focus()
    try {
      const release = version
        ? await loadReleaseForVersion(version)
        : await loadLatestPublishedRelease()
      version = releaseVersion(release)
      if (!version) throw new Error('Release tag unavailable')
      selectedReleaseVersion = version
      if (releaseModalVersion) releaseModalVersion.textContent = version
      if (releaseModalDate) {
        const published = new Date(release.published_at)
        releaseModalDate.textContent = Number.isNaN(published.valueOf())
          ? 'Release date unavailable'
          : new Intl.DateTimeFormat(document.documentElement.lang || 'en', {
              dateStyle: 'long',
            }).format(published)
      }
      renderReleaseMarkdown(release.body)
      if (releaseModalState) releaseModalState.hidden = true
      if (releaseModalBody) releaseModalBody.hidden = false
    } catch {
      showReleaseFailure()
    }
  }

  function closeReleaseNotes() {
    if (!releaseModal || releaseModal.hidden) return
    releaseModal.hidden = true
    document.body.classList.remove('release-modal-open')
    releaseModalOpener?.focus()
  }

  document.querySelectorAll('[data-release-notes]').forEach((control) => {
    control.addEventListener('click', () => {
      const version = control.getAttribute('data-release-version-value')
      openReleaseNotes(version, control)
    })
  })

  document.querySelectorAll('[data-release-modal-close]').forEach((control) => {
    control.addEventListener('click', closeReleaseNotes)
  })

  releaseModal?.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      closeReleaseNotes()
      return
    }
    if (event.key !== 'Tab' || !releaseModalPanel) return
    const focusable = Array.from(
      releaseModalPanel.querySelectorAll(
        'a[href], button:not([disabled]), select, [tabindex]:not([tabindex="-1"])',
      ),
    )
    if (!focusable.length) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  })

  const loadLatestRelease = async () => {
    const config = window.DAYVECTOR_RELEASES
    const setDownload = (platform, asset) => {
      const link = document.getElementById(`${platform}-download`)
      const size = document.querySelector(`[data-${platform}-size]`)
      const label = link?.querySelector('[data-download-label]')
      const platformName = platform === 'windows' ? 'Windows' : 'Android'
      if (!link) return
      if (asset?.browser_download_url) {
        link.href = asset.browser_download_url
        link.removeAttribute('aria-disabled')
        link.removeAttribute('tabindex')
        if (label) label.textContent = `Download for ${platformName}`
        if (size) size.textContent = fileSize(asset.size)
        return
      }
      link.href = '#'
      link.setAttribute('aria-disabled', 'true')
      link.setAttribute('tabindex', '-1')
      if (label) label.textContent = 'Coming soon!'
      if (size) size.textContent = 'Available with the release'
    }
    const setReleaseUnavailable = (version = null) => {
      document.querySelectorAll('[data-release-version]').forEach((element) => {
        element.textContent = version || 'Coming soon!'
      })
      if (version) {
        document.querySelectorAll('[data-release-notes]').forEach((control) => {
          control.setAttribute('data-release-version-value', version)
        })
      }
      setDownload('windows', null)
      setDownload('android', null)
    }
    if (!config?.latestApiUrl) {
      setReleaseUnavailable()
      return
    }

    try {
      // Download metadata is public-facing.  Never present a local build or a
      // planned tag as released: only GitHub's latest published release may
      // supply the displayed version, notes and installer links.
      const release = await loadLatestPublishedRelease()
      const assets = Array.isArray(release.assets) ? release.assets : []
      const windows = assets.find((asset) =>
        String(asset.name).toLowerCase().endsWith('.exe'),
      )
      const android = assets.find((asset) =>
        String(asset.name).toLowerCase().endsWith('.apk'),
      )
      const version = releaseVersion(release)
      if (!version) throw new Error('Release tag unavailable')

      document
        .querySelectorAll('[data-release-version]')
        .forEach((element) => {
          element.textContent = version
        })
      document.querySelectorAll('[data-release-notes]').forEach((control) => {
        control.setAttribute('data-release-version-value', version)
      })

      setDownload('windows', windows)
      setDownload('android', android)
    } catch {
      setReleaseUnavailable()
    }
  }

  loadLatestRelease()
})()
