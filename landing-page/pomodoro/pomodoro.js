(() => {
  const app = document.querySelector('[data-pomodoro-app]')
  if (!app) return

  const STORAGE_KEY = 'taskmaster-pro:pomodoro:v1'
  const DEFAULT_TITLE = 'Free Pomodoro Timer from TaskMaster Pro'
  const PHASES = {
    focus: { label: 'Focus', setting: 'focusMinutes' },
    shortBreak: { label: 'Short break', setting: 'shortBreakMinutes' },
    longBreak: { label: 'Long break', setting: 'longBreakMinutes' },
  }
  const DEFAULT_CONFIG = {
    focusMinutes: 25,
    shortBreakMinutes: 5,
    longBreakMinutes: 15,
    focusesPerRound: 4,
    autoStartBreaks: false,
    autoStartFocus: false,
    soundEnabled: true,
  }
  const SETTING_LIMITS = {
    focusMinutes: [1, 120],
    shortBreakMinutes: [1, 60],
    longBreakMinutes: [1, 90],
    focusesPerRound: [1, 12],
  }

  const timerStage = app.querySelector('[data-timer-stage]')
  const timerValue = app.querySelector('[data-timer-value]')
  const phaseLabel = app.querySelector('[data-phase-label]')
  const roundLabel = app.querySelector('[data-round-label]')
  const startLabel = app.querySelector('[data-start-label]')
  const startIcon = app.querySelector('[data-start-icon]')
  const status = app.querySelector('[data-timer-status]')
  const taskInput = app.querySelector('[data-task-input]')
  const settingsSummary = app.querySelector('[data-settings-summary]')
  const saveStatus = app.querySelector('[data-save-status]')
  const phaseButtons = Array.from(app.querySelectorAll('[data-phase-button]'))
  const settingInputs = Array.from(app.querySelectorAll('[data-setting]'))
  let audioContext = null
  let infoOpener = null
  let saveStatusTimer = null

  const clampInteger = (value, minimum, maximum, fallback) => {
    const parsed = Number.parseInt(value, 10)
    if (!Number.isFinite(parsed)) return fallback
    return Math.min(maximum, Math.max(minimum, parsed))
  }

  const sanitizeConfig = (candidate = {}) => {
    const config = { ...DEFAULT_CONFIG }
    Object.entries(SETTING_LIMITS).forEach(([key, [minimum, maximum]]) => {
      config[key] = clampInteger(
        candidate[key],
        minimum,
        maximum,
        DEFAULT_CONFIG[key],
      )
    })
    config.autoStartBreaks = candidate.autoStartBreaks === true
    config.autoStartFocus = candidate.autoStartFocus === true
    config.soundEnabled = candidate.soundEnabled !== false
    return config
  }

  const phaseDuration = (phase, config) =>
    config[PHASES[phase]?.setting || 'focusMinutes'] * 60

  const defaultState = () => {
    const config = { ...DEFAULT_CONFIG }
    return {
      version: 1,
      config,
      phase: 'focus',
      remainingSeconds: phaseDuration('focus', config),
      totalSeconds: phaseDuration('focus', config),
      isRunning: false,
      targetEpoch: null,
      completedFocuses: 0,
      task: '',
      updatedAt: Date.now(),
    }
  }

  const loadState = () => {
    const fallback = defaultState()
    try {
      const candidate = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null')
      if (!candidate || typeof candidate !== 'object') return fallback
      const config = sanitizeConfig(candidate.config)
      const phase = Object.hasOwn(PHASES, candidate.phase)
        ? candidate.phase
        : 'focus'
      const configuredDuration = phaseDuration(phase, config)
      const totalSeconds = clampInteger(
        candidate.totalSeconds,
        1,
        120 * 60,
        configuredDuration,
      )
      const remainingSeconds = clampInteger(
        candidate.remainingSeconds,
        0,
        totalSeconds,
        totalSeconds,
      )
      const isRunning = candidate.isRunning === true && remainingSeconds > 0
      const targetEpoch = Number(candidate.targetEpoch)
      return {
        version: 1,
        config,
        phase,
        remainingSeconds,
        totalSeconds,
        isRunning: isRunning && Number.isFinite(targetEpoch),
        targetEpoch:
          isRunning && Number.isFinite(targetEpoch) ? targetEpoch : null,
        completedFocuses: clampInteger(
          candidate.completedFocuses,
          0,
          100000,
          0,
        ),
        task: typeof candidate.task === 'string'
          ? candidate.task.slice(0, 120)
          : '',
        updatedAt: Number(candidate.updatedAt) || Date.now(),
      }
    } catch {
      return fallback
    }
  }

  let state = loadState()

  const showSaved = (message = 'Saved locally') => {
    if (!saveStatus) return
    saveStatus.textContent = message
    window.clearTimeout(saveStatusTimer)
    if (message !== 'Saved locally') return
    saveStatusTimer = window.setTimeout(() => {
      saveStatus.textContent = 'Saved locally'
    }, 1400)
  }

  const saveState = () => {
    state.updatedAt = Date.now()
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state))
      showSaved()
    } catch {
      showSaved('Local saving unavailable')
    }
  }

  const timeText = (seconds) => {
    const safeSeconds = Math.max(0, Math.floor(seconds))
    const minutes = Math.floor(safeSeconds / 60)
    return `${String(minutes).padStart(2, '0')}:${String(safeSeconds % 60).padStart(2, '0')}`
  }

  const durationAttribute = (seconds) =>
    `PT${Math.floor(seconds / 60)}M${seconds % 60}S`

  const currentFocusNumber = () =>
    (state.completedFocuses % state.config.focusesPerRound) + 1

  const statusMessage = () => {
    if (state.isRunning) {
      return state.phase === 'focus'
        ? 'Focus is running. Keep this interval for one clear task.'
        : 'Break is running. Step away from the task if you can.'
    }
    if (state.remainingSeconds < state.totalSeconds) {
      return `${PHASES[state.phase].label} paused. It will resume from ${timeText(state.remainingSeconds)}.`
    }
    return state.phase === 'focus'
      ? 'Ready when you are. Your progress stays on this device.'
      : `${PHASES[state.phase].label} is ready when you are.`
  }

  const updateSettingsSummary = () => {
    if (!settingsSummary) return
    settingsSummary.textContent =
      `${state.config.focusMinutes} min focus, ${state.config.shortBreakMinutes} min short break, ${state.config.longBreakMinutes} min long break`
  }

  const render = ({ syncTaskInput = false } = {}) => {
    const display = timeText(state.remainingSeconds)
    const progress = state.totalSeconds > 0
      ? Math.max(0, Math.min(1, state.remainingSeconds / state.totalSeconds))
      : 0

    app.dataset.phase = state.phase
    timerStage?.style.setProperty('--timer-progress', `${progress * 360}deg`)
    if (timerValue) {
      timerValue.textContent = display
      timerValue.setAttribute('datetime', durationAttribute(state.remainingSeconds))
    }
    if (phaseLabel) phaseLabel.textContent = PHASES[state.phase].label
    if (roundLabel) {
      roundLabel.textContent = state.phase === 'focus'
        ? `Focus ${currentFocusNumber()} of ${state.config.focusesPerRound}`
        : `${state.completedFocuses} focus${state.completedFocuses === 1 ? '' : 'es'} completed`
    }

    const untouched = state.remainingSeconds === state.totalSeconds
    if (startLabel) {
      startLabel.textContent = state.isRunning
        ? 'Pause'
        : untouched
          ? `Start ${state.phase === 'focus' ? 'focus' : 'break'}`
          : 'Resume'
    }
    if (startIcon) startIcon.textContent = state.isRunning ? 'pause' : 'play_arrow'
    if (status) status.textContent = statusMessage()
    if (syncTaskInput && taskInput) taskInput.value = state.task

    phaseButtons.forEach((button) => {
      const selected = button.getAttribute('data-phase-button') === state.phase
      button.setAttribute('aria-pressed', String(selected))
    })
    updateSettingsSummary()
    document.title = state.isRunning
      ? `${display} ${PHASES[state.phase].label}, TaskMaster Pro`
      : DEFAULT_TITLE
  }

  const initializeAudio = () => {
    if (audioContext || !state.config.soundEnabled) return
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return
    try {
      audioContext = new AudioContextClass()
    } catch {
      audioContext = null
    }
  }

  const playCompletionTone = () => {
    if (!state.config.soundEnabled || !audioContext) return
    try {
      const startAt = audioContext.currentTime
      ;[523.25, 659.25, 783.99].forEach((frequency, index) => {
        const oscillator = audioContext.createOscillator()
        const gain = audioContext.createGain()
        const noteStart = startAt + index * 0.13
        oscillator.type = 'sine'
        oscillator.frequency.setValueAtTime(frequency, noteStart)
        gain.gain.setValueAtTime(0.0001, noteStart)
        gain.gain.exponentialRampToValueAtTime(0.11, noteStart + 0.025)
        gain.gain.exponentialRampToValueAtTime(0.0001, noteStart + 0.22)
        oscillator.connect(gain)
        gain.connect(audioContext.destination)
        oscillator.start(noteStart)
        oscillator.stop(noteStart + 0.24)
      })
    } catch {
      // The timer remains fully functional when audio is unavailable.
    }
  }

  const shouldAutoStart = (phase) =>
    phase === 'focus'
      ? state.config.autoStartFocus
      : state.config.autoStartBreaks

  const nextPhaseAfter = (phase, completedFocuses) => {
    if (phase !== 'focus') return 'focus'
    return completedFocuses % state.config.focusesPerRound === 0
      ? 'longBreak'
      : 'shortBreak'
  }

  const enterPhase = (
    phase,
    { running = false, anchorEpoch = Date.now(), persist = true } = {},
  ) => {
    state.phase = phase
    state.totalSeconds = phaseDuration(phase, state.config)
    state.remainingSeconds = state.totalSeconds
    state.isRunning = running
    state.targetEpoch = running
      ? anchorEpoch + state.totalSeconds * 1000
      : null
    if (persist) saveState()
    render()
  }

  const completeCurrentPhase = ({ anchorEpoch = Date.now(), audible = true } = {}) => {
    if (state.phase === 'focus') state.completedFocuses += 1
    const nextPhase = nextPhaseAfter(state.phase, state.completedFocuses)
    const autoStart = shouldAutoStart(nextPhase)
    if (audible) playCompletionTone()
    enterPhase(nextPhase, { running: autoStart, anchorEpoch, persist: false })
    if (status) {
      status.textContent = nextPhase === 'focus'
        ? 'Break complete. Your next focus is ready.'
        : 'Focus complete. Take a deliberate break.'
    }
    saveState()
  }

  const reconcileElapsedTime = ({ audible = false } = {}) => {
    if (!state.isRunning || !Number.isFinite(state.targetEpoch)) return
    const now = Date.now()
    let guard = 0
    while (state.isRunning && now >= state.targetEpoch && guard < 100) {
      const completedAt = state.targetEpoch
      completeCurrentPhase({ anchorEpoch: completedAt, audible: audible && guard === 0 })
      guard += 1
    }
    if (state.isRunning && Number.isFinite(state.targetEpoch)) {
      state.remainingSeconds = Math.max(
        0,
        Math.ceil((state.targetEpoch - now) / 1000),
      )
    }
  }

  const toggleTimer = () => {
    initializeAudio()
    if (audioContext?.state === 'suspended') audioContext.resume().catch(() => {})
    if (state.isRunning) {
      reconcileElapsedTime()
      state.isRunning = false
      state.targetEpoch = null
    } else {
      if (state.remainingSeconds <= 0) {
        state.totalSeconds = phaseDuration(state.phase, state.config)
        state.remainingSeconds = state.totalSeconds
      }
      state.isRunning = true
      state.targetEpoch = Date.now() + state.remainingSeconds * 1000
    }
    saveState()
    render()
  }

  const resetCurrentPhase = () => {
    state.totalSeconds = phaseDuration(state.phase, state.config)
    state.remainingSeconds = state.totalSeconds
    state.isRunning = false
    state.targetEpoch = null
    saveState()
    render()
  }

  const skipCurrentPhase = () => {
    const nextPhase = state.phase === 'focus' ? 'shortBreak' : 'focus'
    enterPhase(nextPhase)
    if (status) status.textContent = `${PHASES[nextPhase].label} is ready.`
  }

  const syncSettingInputs = () => {
    settingInputs.forEach((input) => {
      const key = input.getAttribute('data-setting')
      if (!key || !Object.hasOwn(state.config, key)) return
      if (input.type === 'checkbox') {
        input.checked = state.config[key] === true
      } else {
        input.value = String(state.config[key])
      }
    })
  }

  app.querySelector('[data-action="start"]')?.addEventListener('click', toggleTimer)
  app.querySelector('[data-action="reset"]')?.addEventListener('click', resetCurrentPhase)
  app.querySelector('[data-action="skip"]')?.addEventListener('click', skipCurrentPhase)
  app.querySelector('[data-action="restore-defaults"]')?.addEventListener('click', () => {
    state.config = { ...DEFAULT_CONFIG }
    syncSettingInputs()
    resetCurrentPhase()
  })

  phaseButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const phase = button.getAttribute('data-phase-button')
      if (!Object.hasOwn(PHASES, phase)) return
      enterPhase(phase)
    })
  })

  taskInput?.addEventListener('input', () => {
    state.task = taskInput.value.slice(0, 120)
    saveState()
  })

  settingInputs.forEach((input) => {
    const applySetting = ({ normalize }) => {
      const key = input.getAttribute('data-setting')
      if (!key || !Object.hasOwn(state.config, key)) return
      if (input.type === 'checkbox') {
        state.config[key] = input.checked
      } else {
        const [minimum, maximum] = SETTING_LIMITS[key]
        const parsed = Number.parseInt(input.value, 10)
        if (!Number.isFinite(parsed) && !normalize) return
        state.config[key] = clampInteger(
          parsed,
          minimum,
          maximum,
          DEFAULT_CONFIG[key],
        )
        if (normalize) input.value = String(state.config[key])
      }
      const changesCurrentDuration =
        PHASES[state.phase].setting === key
      if (!state.isRunning && changesCurrentDuration) {
        state.totalSeconds = phaseDuration(state.phase, state.config)
        state.remainingSeconds = state.totalSeconds
      }
      saveState()
      render()
    }

    if (input.type === 'checkbox') {
      input.addEventListener('change', () => applySetting({ normalize: true }))
    } else {
      input.addEventListener('input', () => applySetting({ normalize: false }))
      input.addEventListener('change', () => applySetting({ normalize: true }))
    }
  })

  window.setInterval(() => {
    if (!state.isRunning) return
    const previousPhase = state.phase
    reconcileElapsedTime({ audible: true })
    if (state.isRunning && Number.isFinite(state.targetEpoch)) {
      const nextRemaining = Math.max(
        0,
        Math.ceil((state.targetEpoch - Date.now()) / 1000),
      )
      if (nextRemaining !== state.remainingSeconds) {
        state.remainingSeconds = nextRemaining
        if (nextRemaining % 5 === 0) saveState()
      }
    }
    render()
    if (previousPhase !== state.phase) saveState()
  }, 250)

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') {
      saveState()
      return
    }
    reconcileElapsedTime()
    saveState()
    render()
  })
  window.addEventListener('pagehide', saveState)

  const infoModal = document.querySelector('[data-info-modal]')
  const infoPanel = document.querySelector('[data-info-panel]')
  const openInfo = () => {
    if (!infoModal || !infoPanel) return
    infoOpener = document.activeElement
    infoModal.hidden = false
    document.body.classList.add('modal-open')
    infoPanel.focus()
  }
  const closeInfo = () => {
    if (!infoModal || infoModal.hidden) return
    infoModal.hidden = true
    document.body.classList.remove('modal-open')
    infoOpener?.focus()
  }

  document.querySelector('[data-info-open]')?.addEventListener('click', openInfo)
  document.querySelectorAll('[data-info-close]').forEach((button) => {
    button.addEventListener('click', closeInfo)
  })
  infoModal?.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      closeInfo()
      return
    }
    if (event.key !== 'Tab' || !infoPanel) return
    const focusable = Array.from(
      infoPanel.querySelectorAll('a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'),
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

  const currentYear = document.getElementById('current-year')
  if (currentYear) currentYear.textContent = String(new Date().getFullYear())

  reconcileElapsedTime()
  syncSettingInputs()
  render({ syncTaskInput: true })
  saveState()
})()
