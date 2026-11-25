// Запуск из корня проекта: node tool/web/review_test.mjs http://localhost:8080/
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {chromium} from 'playwright-core';

const url = process.argv[2];
if (!url) throw new Error('Укажите адрес тестовой сборки Картоведа');
const photo = resolve('test/fixtures/bouncers-beatdown.jpg');
const camera = process.env.KARTOVED_TEST_CAMERA;
const browser = await chromium.launch({
  channel: 'chrome',
  args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--enable-unsafe-swiftshader',
    ...(camera ? ['--use-file-for-fake-video-capture=' + resolve(camera)] : [])],
});
const context = await browser.newContext({viewport: {width: 390, height: 780}});
const page = await context.newPage();
page.setDefaultTimeout(20000);
const button = name => page.getByRole('button', {name, exact: typeof name === 'string'});
const album = button(/^Моя коллекция, /);
const first = {id: '54772e15-d99d-4eec-ba8d-b9202a7e318b', name: "Bouncer's Beatdown", set_code: 'snc', number: '135', lang: 'en', foil: 0};
const second = {id: 'c3669391-8f64-4904-b432-0f0582f30449', name: 'Opt', set_code: 'eld', number: '59', lang: 'en', foil: 0};
const pending = (card, seq) => ({...card, seq, folder: 1, qty: 1, flagged: 0, review: {reason: 'printing', choices: [card]}});
const backup = {format: 'kartoved', version: 1, folders: [{folder: 1, title: 'Моя коллекция'}], scans: [pending(first, 1), pending(second, 2)]};

async function enableSemantics() {
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await album.waitFor();
}
async function upload(action, file) {
  const chooser = page.waitForEvent('filechooser');
  await action.click();
  await (await chooser).setFiles(file);
}
function filter(count) {
  const name = 'На проверке · ' + count;
  return button(name).or(page.getByRole('checkbox', {name, exact: true}));
}
async function screenshot(name) {
  if (process.env.KARTOVED_QA_DIR) await page.screenshot({path: resolve(process.env.KARTOVED_QA_DIR, name + '.png')});
}

try {
  await page.goto(url);
  await enableSemantics();
  await button('База карт').click();
  await button('Подготовить сканер без сети').click();
  await button('Сканер готов к работе без сети').waitFor({timeout: 300000});
  await page.keyboard.press('Escape');
  await button('Резервная копия').click();
  await upload(button('Восстановить из файла'), {name: 'reviews.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(backup))});
  await button('Заменить коллекции').click();
  await page.getByRole('region').getByText('Коллекции восстановлены', {exact: true}).waitFor();
  await page.keyboard.press('Escape');

  await context.setOffline(true);
  assert.equal(await page.evaluate(async () => {
    try { await fetch('network-probe-' + Date.now()); return true; } catch { return false; }
  }), false, 'У браузера осталось соединение');
  await page.reload();
  await enableSemantics();
  for (const art of ['forest', 'dragon', 'island']) {
    const header = await page.evaluate(async name => {
      const response = await fetch('assets/assets/design/' + name + '-cover.webp');
      return new TextDecoder().decode((await response.arrayBuffer()).slice(8, 12));
    }, art);
    assert.equal(header, 'WEBP', 'Обложка должна быть доступна без сети: ' + art);
  }
  for (const sound of ['added', 'found', 'review']) {
    const header = await page.evaluate(async (name) => {
      const response = await fetch('runtime/card_' + name + '.wav');
      const bytes = await response.arrayBuffer();
      return new TextDecoder().decode(bytes.slice(0, 4));
    }, sound);
    assert.equal(header, 'RIFF', 'Сигнал должен быть доступен без сети: ' + sound);
  }
  await button('На проверке · 2').click();
  await button('Переснять ' + second.name).waitFor();
  await screenshot('before');
  await button('Переснять ' + first.name).click();
  if (camera) {
    await button('Сделать новый снимок').click();
    if (process.env.KARTOVED_QA_DIR) {
      await page.getByText(/Сверяю иллюстрацию|Уточняю по тексту/).first().waitFor();
      await screenshot('mesh');
    }
  } else {
    await upload(button('Из фото'), photo);
  }
  await filter(1).waitFor({timeout: 90000});
  await button('Переснять ' + second.name).waitFor();
  assert.equal(await button('Переснять ' + first.name).count(), 0);
  await screenshot('after');

  if (camera) {
    await button('Сканировать карту').click();
    await button('Добавить карту').waitFor();
    await page.waitForFunction(() => [...document.querySelectorAll('video')].some(video => video.videoWidth > 0));
    await button('Переснять ' + first.name).click();
    await button('Переснять ' + first.name).click({trial: true, timeout: 90000});
    await page.getByText(/Bouncer's Beatdown\s+Учтено в «Моя коллекция»/).first().waitFor({timeout: 90000});
    assert.equal(await button(/^Проверить/).count(), 0);
    await screenshot('scanner');
  }

  await page.reload();
  await enableSemantics();
  await button(/^Моя коллекция, 1 карта$/).waitFor();
  await button(/Bouncer's Beatdown.*×1/).waitFor();
  await screenshot('reloaded');
  await album.click();
  await filter(1).click();
  await button('Переснять ' + second.name).waitFor();
  await button('Назад').click();
  await button('Резервная копия').click();
  const downloaded = page.waitForEvent('download');
  await button(/Сохранить в файл/).click();
  const {scans} = JSON.parse(await readFile(await (await downloaded).path(), 'utf8'));
  assert.equal(scans.length, 2);
  const saved = scans.find(s => s.seq === 1);
  assert.deepEqual(saved, {...backup.scans[0], review: null});
  assert.deepEqual(scans.find(s => s.seq === 2), backup.scans[1]);
  console.log('Без сети после перезагрузки: Bouncer’s Beatdown ×1, Opt на проверке. Обе записи сохранили исходные номера.');
  await page.reload();
  await enableSemantics();
  await button('На проверке · 1').click();
  await button('Переснять ' + second.name).click();
  await upload(button('Из фото'), photo);
  await button('К альбому').waitFor({timeout: 90000});
  await page.getByText('Все карты проверены', {exact: true}).waitFor();
  await button('К альбому').click();
  await button('Найти карту').waitFor();
  await button(/Действия с картой Bouncer's Beatdown, ×2/).waitFor();
  console.log('После второго снимка очередь пуста, в альбоме два подтверждённых экземпляра.');
} catch (error) {
  console.error(await page.locator('body').ariaSnapshot().catch(() => ''));
  throw error;
} finally {
  await browser.close();
}
