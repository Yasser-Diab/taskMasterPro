(() => {
  const announcement = window.DAYVECTOR_RELEASES?.announcement
  if (!announcement?.message || !announcement?.expiresAt) return

  const expiresAt = Date.parse(announcement.expiresAt)
  if (!Number.isFinite(expiresAt) || Date.now() >= expiresAt) return

  const host = document.querySelector('main [data-release-announcement-host]')
  if (!host || host.querySelector('[data-release-announcement]')) return

  const label = window.DayVectorI18n?.translate?.('Latest DayVector update') ||
    'Latest DayVector update'
  host.closest('[data-release-announcement-section]')?.setAttribute('aria-label', label)

  const badge = document.createElement('a')
  badge.className = 'timeout-badge'
  badge.dataset.releaseAnnouncement = announcement.id || 'announcement'
  badge.href = announcement.href || '#download'
  badge.innerHTML =
    '<span class="material-symbols-rounded" aria-hidden="true">new_releases</span><span></span>'
  badge.querySelector('span:last-child').textContent = announcement.message
  badge.setAttribute('aria-label', announcement.message)

  host.append(badge)
})()
