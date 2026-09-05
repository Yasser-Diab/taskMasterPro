(() => {
  const announcementSelector = 'template[data-dayvector-announcement]'

  function parseTimestamp(value, fallback) {
    const parsed = Date.parse(value || '')
    return Number.isFinite(parsed) ? parsed : fallback
  }

  function readAnnouncements(markup, now) {
    const documentFromFile = new DOMParser().parseFromString(markup, 'text/html')
    return Array.from(documentFromFile.querySelectorAll(announcementSelector))
      .map((template, index) => {
        const publishedAt = parseTimestamp(template.dataset.publishedAt, 0)
        const expiresAt = parseTimestamp(template.dataset.expiresAt, NaN)
        const message = template.content.textContent.replace(/\s+/g, ' ').trim()
        const target = template.dataset.target || '#top'
        return {
          expiresAt,
          icon: template.dataset.icon || 'new_releases',
          id: template.dataset.id || `announcement-${index}`,
          index,
          message,
          publishedAt,
          target,
        }
      })
      .filter(
        (announcement) =>
          announcement.message &&
          Number.isFinite(announcement.expiresAt) &&
          announcement.publishedAt <= now &&
          now < announcement.expiresAt,
      )
      .sort(
        (first, second) =>
          second.publishedAt - first.publishedAt || second.index - first.index,
      )
  }

  function localTarget(host, target) {
    if (!target.startsWith('#')) return '#top'
    const prefix = host.dataset.announcementHomePrefix || ''
    return `${prefix}${target}`
  }

  function renderAnnouncement(host, announcement) {
    const label =
      window.DayVectorI18n?.translate?.('Latest DayVector update') ||
      'Latest DayVector update'
    host.closest('[data-release-announcement-section]')?.setAttribute('aria-label', label)

    const badge = document.createElement('a')
    badge.className = 'timeout-badge'
    badge.dataset.releaseAnnouncement = announcement.id
    badge.href = localTarget(host, announcement.target)
    badge.setAttribute('aria-label', announcement.message)

    const icon = document.createElement('span')
    icon.className = 'material-symbols-rounded timeout-badge-icon'
    icon.setAttribute('aria-hidden', 'true')
    icon.textContent = announcement.icon

    const message = document.createElement('span')
    message.className = 'timeout-badge-message'
    message.textContent = announcement.message

    const action = document.createElement('span')
    action.className = 'material-symbols-rounded timeout-badge-action'
    action.setAttribute('aria-hidden', 'true')
    action.textContent = 'arrow_forward'

    badge.append(icon, message, action)
    host.append(badge)
    window.DayVectorI18n?.refresh?.()
  }

  async function installAnnouncement() {
    const host = document.querySelector('[data-release-announcement-host]')
    const source = window.DAYVECTOR_RELEASES?.announcementsUrl
    if (!host || !source || host.querySelector('[data-release-announcement]')) return

    try {
      const response = await fetch(source, { cache: 'no-store' })
      if (!response.ok) throw new Error(`Announcement source returned ${response.status}`)
      const [announcement] = readAnnouncements(await response.text(), Date.now())
      if (announcement) renderAnnouncement(host, announcement)
    } catch (error) {
      console.warn('DayVector announcement was not loaded.', error)
    }
  }

  installAnnouncement()
})()
