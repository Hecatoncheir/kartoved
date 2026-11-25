// Запуск из корня проекта: node tool/web/tray_repeat_test.mjs http://localhost:8080/
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {chromium} from 'playwright-core';

const [url, english = 'test/fixtures/bouncers-beatdown.jpg',
  russian = 'test/fixtures/bouncers-beatdown-ru.jpg'] = process.argv.slice(2);
const pictures = await Promise.all([english, russian].map(async path =>
  'data:image/jpeg;base64,' + (await readFile(path)).toString('base64')));
const browser = await chromium.launch({channel: 'chrome', args: [
  '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--enable-unsafe-swiftshader',
]});

const page = await browser.newPage({viewport: {width: 960, height: 900}, permissions: ['camera']});
try {
  page.setDefaultTimeout(90000);
  await page.addInitScript(async sources => {
    const images = await Promise.all(sources.map(async src => {
      const image = new Image();
      image.src = src;
      await image.decode();
      return image;
    }));
    const canvas = Object.assign(document.createElement('canvas'), {width: 1280, height: 720});
    const ctx = canvas.getContext('2d');
    let card = 0;
    window.showCard = index => { card = index; };
    function draw() {
      ctx.fillStyle = '#665f55';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      if (card !== null) ctx.drawImage(images[card], 415, 45, 450, 630);
    }
    draw();
    setInterval(draw, 65);
    navigator.mediaDevices.getUserMedia = async () => canvas.captureStream(15);
  }, pictures);

  const button = name => page.getByRole('button', {name, exact: typeof name === 'string'});
  await page.goto(url);
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await button('Сканировать карту').click();
  for (const name of ['Только необходимое', 'Одинаковые подряд']) {
    await button('Меню сканера').click();
    await page.getByRole('menuitemcheckbox', {name}).or(page.getByRole('menuitem', {name})).click();
  }
  // Меняем изображение сразу после записи в базу. Камера, распознавание и SQLite настоящие.
  await page.evaluate(() => {
    window.shots = [];
    let footerReads = 0;
    const crop = kartoved.trayPhoto, sound = kartoved.chime;
    kartoved.trayPhoto = (file, area, readFooter) => {
      if (readFooter) footerReads++;
      return crop(file, area, readFooter);
    };
    kartoved.chime = outcome => {
      shots.push({outcome, footerReads});
      if (shots.length === 2) {
        showCard(null);
        setTimeout(() => showCard(0), 450);
      }
      if (shots.length === 3) showCard(1);
      if (shots.length === 4) showCard(null);
      return sound(outcome);
    };
  });
  const tray = page.getByRole('switch', {name: 'Автоскан в лотке'});
  await tray.click();
  await page.waitForFunction(() => shots.length >= 4, null, {timeout: 120000});
  await tray.click();
  const shots = await page.evaluate(() => window.shots);
  assert.deepEqual(shots.map(s => s.outcome), ['added','added','added','added']);
  assert.equal(shots[1].footerReads, shots[0].footerReads, 'Неподвижная карта учитывается без повторного OCR');
  assert.ok(shots[3].footerReads > shots[2].footerReads, 'Текст новой карты должен быть прочитан');

  await page.reload();
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await button('Резервная копия').click();
  const [file] = await Promise.all([page.waitForEvent('download'), button(/Сохранить в файл/).click()]);
  const {scans} = JSON.parse(await readFile(await file.path(), 'utf8'));
  console.log(JSON.stringify({shots, cards: scans.map(({name,lang,set_code,number}) => ({name,lang,set_code,number}))}));
  assert.deepEqual(scans.map(s => s.lang), ['en','en','en','ru']);
  const expectedName = process.argv.length > 3 ? 'Opt' : "Bouncer's Beatdown";
  assert.ok(scans.every(s => s.name === expectedName && s.qty === 1 && !s.review));
  assert.equal(scans[0].id, scans[1].id);
  if (scans[0].name === 'Opt') {
    assert.ok(scans.slice(0,3).every(s => (!s.set_code && !s.number) || (s.set_code === 'eld' && s.number === '59')));
    const last = scans[3];
    assert.ok((!last.set_code && !last.number) || (last.set_code === 'dom' && last.number === '60'));
  }
} catch (error) {
  console.error(await page.locator('body').ariaSnapshot());
  console.error(await page.evaluate(() => ({shots: window.shots, video: [...document.querySelectorAll('video')].map(v => [v.videoWidth, v.videoHeight])})));
  throw error;
} finally {
  await browser.close();
}
