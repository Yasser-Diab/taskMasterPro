import { expect, test } from '@playwright/test';

test('all main sections render browser-native content without grey platform surfaces', async ({ page }) => {
  await page.goto('/');

  const main = page.getByTestId('app-main');
  await expect(main).toBeVisible();
  await expect(page.getByTestId('dashboard-page')).toBeVisible();

  for (const label of ['Tasks', 'Pomodoro', 'History', 'Roadmap', 'Settings']) {
    await page.getByTestId(`nav-${label.toLowerCase()}`).click();
    await expect(page.getByTestId(`${label.toLowerCase()}-page`)).toBeVisible();
    await expect(page.locator('iframe, webview, .native-surface')).toHaveCount(0);
    const background = await main.evaluate((element) => getComputedStyle(element).backgroundColor);
    expect(background).not.toBe('rgb(181, 181, 181)');
  }
});

test('browser workspace stores metadata and never mounts a native webview', async ({ page }) => {
  await page.goto('/');
  await page.getByTestId('nav-browser').click();
  await expect(page.getByTestId('browser-page')).toBeVisible();
  await expect(page.getByTestId('browser-shell')).toContainText('External pages open');
  await expect(page.locator('iframe, webview, .native-surface')).toHaveCount(0);
});

test('quick note dialog is explicit and usable on compact screens', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: /Quick note/i }).click();
  await expect(page.getByRole('dialog', { name: 'Quick note' })).toBeVisible();
  await page.getByLabel('Title or note').fill('Capture this idea');
  await page.getByRole('button', { name: 'Save note' }).click();
  await expect(page.getByRole('dialog', { name: 'Quick note' })).toHaveCount(0);
});
