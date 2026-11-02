import { test, expect } from '@playwright/test';
test('unauthenticated users see login rather than admin screens', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible();
  await expect(page.getByRole('textbox', { name: 'Email' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible();
  await expect(page.getByText('Registered Users')).toHaveCount(0);
});
test('login form validates email and requires password', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('textbox', { name: 'Email' }).fill('not-an-email');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('textbox', { name: 'Email' })).toHaveJSProperty('validity', expect.objectContaining({ typeMismatch: true }));
});
