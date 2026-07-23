import { expect, test } from '@playwright/test';

async function openPreviewWorkspace(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    window.localStorage.setItem('taskmaster-pro-next.preview-auth', '1');
  });
  await page.goto('/');
}

test('unauthenticated startup shows the user login screen with working branding', async ({ page }) => {
  await page.goto('/');

  await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible();
  await expect(page.getByText('Your planning workspace')).toBeVisible();
  await expect(page.locator('.auth-card .primary-btn.full')).toContainText('Sign in');
  await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();

  await page.waitForFunction(() => {
    const img = document.querySelector('.auth-logo') as HTMLImageElement | null;
    return Boolean(img?.complete && img.naturalWidth > 0);
  });
  await expect(page.locator('iframe, webview, .native-surface')).toHaveCount(0);
});

test('main sections render without native grey platform surfaces in preview mode', async ({ page }) => {
  await openPreviewWorkspace(page);

  const main = page.getByTestId('app-main');
  await expect(main).toBeVisible();
  await expect(page.getByTestId('dashboard-page')).toBeVisible();

  for (const label of ['Tasks', 'Pomodoro', 'History', 'Roadmap', 'Settings']) {
    await page.getByTestId(`nav-${label.toLowerCase()}`).click();
    await expect(page.getByTestId(`${label.toLowerCase()}-page`)).toBeVisible();
    await expect(page.locator('iframe, webview, .native-surface')).toHaveCount(0);
  }
});

test('task editor supports resources and related applications', async ({ page }) => {
  await openPreviewWorkspace(page);
  await page.getByTestId('nav-tasks').click();

  await page.getByRole('button', { name: 'New task' }).click();
  await page.getByLabel('Title').fill('Prepare client proposal');
  await page.getByLabel('What should count as useful work for this task?').fill('Writing the proposal and reading project files');
  await page.getByPlaceholder('Resource name').fill('Project brief');
  await page.getByPlaceholder('URL or reference').fill('https://example.com/brief');
  await page.getByRole('button', { name: 'Add' }).first().click();
  await page.getByPlaceholder('Application name').fill('Word');
  await page.getByPlaceholder('Process name, optional').fill('WINWORD');
  await page.getByRole('button', { name: 'Add' }).last().click();
  await page.getByRole('button', { name: 'Save task' }).click();

  await expect(page.getByText('Prepare client proposal')).toBeVisible();
  await expect(page.getByText('1 resources')).toBeVisible();
  await expect(page.getByText('1 related apps')).toBeVisible();
});

test('pomodoro page is a standalone timer, not a duplicate task board', async ({ page }) => {
  await openPreviewWorkspace(page);
  await page.getByTestId('nav-pomodoro').click();
  await expect(page.getByTestId('pomodoro-page')).toContainText('Standalone Pomodoro');
  await expect(page.getByTestId('pomodoro-page')).toContainText('Pomodoro is only the timer');
  await expect(page.locator('.task-board')).toHaveCount(0);
});

test('browser workspace stores metadata and never mounts a native webview', async ({ page }) => {
  await openPreviewWorkspace(page);
  await page.getByTestId('nav-browser').click();
  await expect(page.getByTestId('browser-page')).toBeVisible();
  await expect(page.getByTestId('browser-shell')).toContainText('External pages open');
  await expect(page.locator('iframe, webview, .native-surface')).toHaveCount(0);
});

test('quick note dialog is explicit and usable on compact screens', async ({ page }) => {
  await openPreviewWorkspace(page);
  await page.getByRole('button', { name: 'Quick note' }).click();
  await expect(page.getByRole('dialog', { name: 'Quick note' })).toBeVisible();
  await page.getByLabel('Title or note').fill('Capture this idea');
  await page.getByRole('button', { name: 'Save note' }).click();
  await expect(page.getByRole('dialog', { name: 'Quick note' })).toHaveCount(0);
});
