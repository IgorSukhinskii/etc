const { chromium } = require('playwright');
const fs = require('fs/promises');

(async () => {
  const url = process.argv[2];
  const userDataDir = process.env.PLAYWRIGHT_PROFILE_DIR;
  const stateFile = process.env.PLAYWRIGHT_STATE_FILE;

  const context = await chromium.launchPersistentContext(userDataDir, {
    headless: false,
    viewport: null,
  });

  // Cookies live in storage-state.json, not in the user-data-dir profile.
  // Chromium deletes session-scoped cookies (e.g. Django sessionid) on
  // graceful shutdown, so the on-disk profile is unreliable. We snapshot
  // live cookies into JSON periodically and re-inject them on launch.
  try {
    const saved = JSON.parse(await fs.readFile(stateFile, 'utf8'));
    if (saved.cookies?.length) {
      await context.addCookies(saved.cookies);
    }
  } catch (_) { /* first run, no saved state */ }

  const save = async () => {
    try {
      const state = await context.storageState();
      await fs.writeFile(stateFile, JSON.stringify(state, null, 2));
    } catch (_) { /* context closing */ }
  };

  // Continuous capture covers Cmd-Q (the 'close' event fires after the CDP
  // pipe is gone, so storageState() is unreachable from there). Anything
  // within ~2s of the last save is preserved.
  const interval = setInterval(save, 2000);

  const cleanup = async () => {
    clearInterval(interval);
    await save();
    try { await context.close(); } catch (_) {}
    process.exit(0);
  };
  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);
  context.on('close', () => { clearInterval(interval); process.exit(0); });

  const page = context.pages()[0] ?? await context.newPage();
  if (url) {
    try {
      await page.goto(url);
    } catch (e) {
      console.error('Navigation error:', e.message);
    }
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
