'use strict';

const printings = [
  ['ring', 'Sol Ring', 'Солнечное кольцо', 'CMM', '410', 'en'],
  ['ring-foil', 'Sol Ring', 'Солнечное кольцо', 'CMM', '410', 'en', true, 'ring'],
  ['swords', 'Swords to Plowshares', 'Мечи на орала', 'STA', '10', 'en'],
  ['swords-ru', 'Swords to Plowshares', 'Мечи на орала', 'STA', '10', 'ru'],
  ['forest', 'Forest', 'Лес', 'ELD', '267', 'en'],
  ['signet', 'Arcane Signet', 'Магическая печать', 'CMM', '367', 'en'],
  ['witness', 'Eternal Witness', 'Вечная свидетельница', '2X2', '145', 'en'],
  ['bolt', 'Lightning Bolt', 'Удар молнии', '2X2', '117', 'en'],
  ['dragon', "Dragon's Rage Channeler", 'Проводница драконьей ярости', 'MH2', '121', 'en'],
  ['counter', 'Counterspell', 'Контрзаклинание', 'STA', '15', 'en'],
  ['counter-ru', 'Counterspell', 'Контрзаклинание', 'STA', '15', 'ru'],
  ['opt', 'Opt', 'Выбор', 'ELD', '59', 'en'],
  ['island', 'Island', 'Остров', 'ELD', '254', 'en'],
  ['brainstorm', 'Brainstorm', 'Мозговой штурм', 'STA', '13', 'en'],
  ['bouncer', "Bouncer's Beatdown", 'Избиение вышибалы', 'SNC', '135', 'en'],
  ['bouncer-ru', "Bouncer's Beatdown", 'Избиение вышибалы', 'SNC', '135', 'ru'],
  ['bouncer-foil', "Bouncer's Beatdown", 'Избиение вышибалы', 'SNC', '135', 'en', true, 'bouncer'],
  ['bouncer-ru-foil', "Bouncer's Beatdown", 'Избиение вышибалы', 'SNC', '135', 'ru', true, 'bouncer-ru'],
];

const cards = Object.fromEntries(printings.map(([id, name, alias, set, number, language, foil = false, art = id]) =>
  [id, { id, name, alias, set, number, language, foil, art }],
));

const sample = {
  albums: [
    { id: 'main', name: 'Основная коллекция', cover: 'forest', counts: { ring: 3, 'ring-foil': 2, 'swords-ru': 1, forest: 12, signet: 4, witness: 3, bouncer: 1 }, flags: ['ring-foil', 'swords-ru'] },
    { id: 'trade', name: 'На обмен', cover: 'dragon', counts: { bolt: 4, dragon: 5, swords: 2, ring: 1 }, flags: ['bolt'] },
    { id: 'draft', name: 'Вечерний драфт', cover: 'island', counts: { counter: 3, opt: 4, island: 9, brainstorm: 2 }, flags: [] },
  ],
  recent: [{ album: 'main', card: 'ring' }, { album: 'trade', card: 'bolt' }, { album: 'draft', card: 'counter' }],
  pending: [],
};

const storageKey = 'kartoved-ui-prototype-v1';
const covers = new Set(['forest', 'dragon', 'island']);
const sides = { en: 'Английский', ru: 'Русский' };
const screen = document.querySelector('#screen');
const sheet = document.querySelector('#sheet');
const toast = document.querySelector('#toast');
const globalSearch = document.querySelector('#global-query');

let library = readLibrary();
let activeRoute;
let scanAlbum = library.albums[0].id;
let scanLanguage = 'auto';
let albumQuery = '';
let catalogQuery = '';
let flaggedOnly = false;
let grouped = false;
let selection = null;
let undoAction;
let toastTimer;

const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"></use></svg>`;
const esc = (value) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
const getAlbum = (id) => library.albums.find((album) => album.id === id);
const total = (counts) => Object.values(counts).reduce((sum, count) => sum + count, 0);
const numberFormat = new Intl.NumberFormat('ru');
const plural = new Intl.PluralRules('ru');
const counted = (count, one, few, many) => `${numberFormat.format(count)} ${{ one, few, many, other: many }[plural.select(count)]}`;
const cardCount = (count) => counted(count, 'карта', 'карты', 'карт');
const albumCount = (count) => counted(count, 'альбом', 'альбома', 'альбомов');
const specimenCount = (count) => counted(count, 'экземпляр', 'экземпляра', 'экземпляров');
const matches = (card, query) => `${card.name} ${card.alias} ${card.set} ${card.number}`.toLocaleLowerCase('ru').includes(query.trim().toLocaleLowerCase('ru'));
const thumb = (card) => `<img class="card-thumb" src="media/${card.art}.webp" alt="" width="35" height="49">`;
const uid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 9)}`;

function edition(card, { styled = false } = {}) {
  const code = `${card.set} #${card.number}`;
  const label = styled ? `<span class="edition-code">${code}</span>` : code;
  return `${label} · ${card.language.toUpperCase()}${card.foil ? ' · Фольга' : ''}`;
}

function button(label, action, symbol, variant = 'button-light', attributes = '') {
  return `<button type="button" class="button ${variant}" data-action="${action}" ${attributes}>${symbol ? icon(symbol) : ''}${label}</button>`;
}

function iconButton(label, action, symbol, attributes = '') {
  return `<button type="button" class="icon-button outline" data-action="${action}" aria-label="${label}" title="${label}" ${attributes}>${icon(symbol)}</button>`;
}

function validLibrary(value) {
  if (!value || !Array.isArray(value.albums) || !value.albums.length || !Array.isArray(value.recent) || !Array.isArray(value.pending)) return false;
  const ids = new Set();
  for (const album of value.albums) {
    if (!album || typeof album.id !== 'string' || !/^[a-z\d-]{1,60}$/.test(album.id) || ids.has(album.id)) return false;
    if (typeof album.name !== 'string' || !album.name.trim() || album.name.length > 60) return false;
    if (album.cover !== null && !covers.has(album.cover)) return false;
    if (!album.counts || typeof album.counts !== 'object' || Array.isArray(album.counts) || !Array.isArray(album.flags)) return false;
    if (!Object.entries(album.counts).every(([id, count]) => Object.hasOwn(cards, id) && Number.isSafeInteger(count) && count > 0)) return false;
    if (!album.flags.every((id) => Object.hasOwn(album.counts, id))) return false;
    ids.add(album.id);
  }
  return value.recent.every((row) => row && ids.has(row.album) && Object.hasOwn(cards, row.card)) &&
    value.pending.every((row) => row && typeof row.id === 'string' && ids.has(row.album) && ['auto', 'en', 'ru'].includes(row.language));
}

function readLibrary() {
  try {
    const stored = JSON.parse(localStorage.getItem(storageKey));
    if (validLibrary(stored)) return stored;
  } catch {
    // При недоступном хранилище прототип открывает исходную библиотеку.
  }
  return structuredClone(sample);
}

function save() {
  try {
    localStorage.setItem(storageKey, JSON.stringify(library));
  } catch {
    return false;
  }
  return true;
}

function notify(message, undo) {
  window.clearTimeout(toastTimer);
  undoAction = undo;
  toast.hidden = false;
  document.querySelector('#toast-message').textContent = message;
  document.querySelector('#toast-undo').hidden = !undo;
  toastTimer = window.setTimeout(() => { toast.hidden = true; }, undo ? 10000 : 5000);
}

function commit(change, message, reversible = false) {
  const before = reversible ? structuredClone(library) : null;
  change();
  const undo = before && (() => commit(() => { library = before; }, 'Действие отменено'));
  const stored = save();
  if (message) notify(stored ? message : `${message}. Изменения сохранены до закрытия страницы.`, undo);
  else {
    toast.hidden = true;
    undoAction = null;
  }
  refresh();
}

function addCount(album, card, amount) {
  const next = (album.counts[card] || 0) + amount;
  if (next > 0) album.counts[card] = next;
  else {
    delete album.counts[card];
    album.flags = album.flags.filter((flag) => flag !== card);
  }
}

function record(album, card) {
  library.recent = [{ album, card }, ...library.recent.filter((row) => row.album !== album || row.card !== card)].slice(0, 15);
}

function readRoute() {
  const [name, id] = location.hash.slice(1).split('/');
  if (name === 'album' && getAlbum(id)) return { name, id, nav: 'library' };
  if (name === 'scan') return { name, id, nav: 'scan' };
  if (name === 'catalog' || name === 'owned') return { name, nav: 'catalog' };
  return { name: 'library', nav: 'library' };
}

function refresh() {
  const route = readRoute();
  const previousControl = document.activeElement;
  const canRefocus = screen.contains(previousControl);
  const locator = canRefocus && controlLocator(previousControl);
  const fromSamePage = activeRoute?.name === route.name && activeRoute?.id === route.id;
  if (!fromSamePage) {
    selection = null;
    albumQuery = '';
    flaggedOnly = false;
    grouped = false;
    if (route.name === 'scan' && getAlbum(route.id)) scanAlbum = route.id;
  }
  activeRoute = route;
  document.querySelectorAll('[data-nav]').forEach((link) => {
    if (link.dataset.nav === route.nav) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  });
  const pages = {
    library: ['Коллекции', renderLibrary],
    album: [route.name === 'album' ? getAlbum(route.id).name : '', renderAlbum],
    scan: ['Сканер', renderScanner],
    catalog: ['Каталог', renderCatalog],
    owned: ['Мои карты', renderCatalog],
  };
  const [title, view] = pages[route.name];
  document.title = `Картовед — ${title}`;
  screen.innerHTML = view(route);
  if (!fromSamePage) {
    window.scrollTo(0, 0);
    if (location.hash) screen.focus({ preventScroll: true });
  } else if (canRefocus) {
    (locator && screen.querySelector(locator) || screen).focus({ preventScroll: true });
  }
}

function controlLocator(control) {
  if (control.id) return `#${CSS.escape(control.id)}`;
  if (!control.dataset.action) return '';
  return Object.entries(control.dataset).map(([key, value]) => `[data-${key}="${CSS.escape(value)}"]`).join('');
}

function searchField(id, label, value) {
  return `<label class="search-field" for="${id}">${icon('search')}<input id="${id}" type="search" aria-label="${label}" placeholder="${label}" value="${esc(value)}" autocomplete="off"></label>`;
}

function empty(title, description, symbol = 'inbox') {
  return `<div class="empty">${icon(symbol)}<h3>${title}</h3><p>${description}</p></div>`;
}

function cardRow(card, meta, options = {}) {
  const { action = 'detail', album = '', count, flag = false, checked, controls = '' } = options;
  const box = checked === undefined ? '' : `<span class="select-box">${checked ? icon('check') : ''}</span>`;
  return `<div class="card-row"><button class="row-main" type="button" data-action="${action}" data-album="${album}" data-card="${card.id}" ${checked === undefined ? '' : `aria-pressed="${checked}"`}>
    ${box}${thumb(card)}<span class="row-text"><strong class="row-title">${esc(card.name)}${flag ? `<span title="Отмечено">${icon('flag')}</span>` : ''}</strong><small>${meta}</small></span>
    ${count === undefined ? '' : `<span class="qty-pill" aria-label="${specimenCount(count)}">×${count}</span>`}${checked === undefined ? icon('chevron') : ''}</button>${controls}</div>`;
}

function cover(album) {
  return album.cover
    ? `<div class="album-cover"><img src="../../assets/design/${album.cover}-cover.webp" alt="" width="640" height="300"></div>`
    : `<div class="album-cover default">${icon('brand')}</div>`;
}

function recentRows(albumId) {
  return library.recent.filter((row) => {
    const album = getAlbum(row.album);
    return album?.counts[row.card] && (!albumId || album.id === albumId);
  }).slice(0, 3).map((row) => {
    const card = cards[row.card];
    const album = getAlbum(row.album);
    const meta = `${edition(card, { styled: true })}${albumId ? '' : ` · ${esc(album.name)}`}`;
    return cardRow(card, meta, { album: album.id, count: album.counts[row.card] });
  }).join('');
}

function renderLibrary() {
  const count = library.albums.reduce((sum, album) => sum + total(album.counts), 0);
  const recent = recentRows();
  return `<section class="hero" aria-labelledby="library-title"><div class="hero-copy">
      <h1 id="library-title">Мои коллекции</h1>
      <div class="hero-stats"><strong>${albumCount(library.albums.length)}</strong><span class="dot" aria-hidden="true"></span><span>${cardCount(count)}</span></div>
      <a class="button button-main" href="#scan">${icon('scan')} Сканировать карту</a>
    </div></section>
    <section class="section" aria-labelledby="albums-title">
      <div class="section-head"><h2 id="albums-title">Альбомы</h2>${button('Новый альбом', 'create', 'plus')}</div>
      <div class="album-grid">${library.albums.map((album) => `<a class="album-card" href="#album/${album.id}">
        ${cover(album)}<span class="album-meta"><strong>${esc(album.name)}</strong><small>${cardCount(total(album.counts))}</small>${icon('chevron')}</span></a>`).join('')}</div>
    </section>
    <section class="section" aria-labelledby="recent-title">
      <div class="section-head"><h2 id="recent-title">Недавно добавленные</h2><a class="text-link" href="#owned" data-action="all-owned">Все карты ${icon('arrow')}</a></div>
      <div class="list-panel">${recent || empty('Список пока пуст', 'Добавьте карту из сканера или каталога.')}</div>
    </section>`;
}

function renderAlbum({ id }) {
  const album = getAlbum(id);
  const foil = Object.entries(album.counts).reduce((sum, [key, count]) => sum + (cards[key].foil ? count : 0), 0);
  const pending = library.pending.filter((row) => row.album === id).length;
  return `<header class="subpage-head"><div><a class="breadcrumb" href="#library">${icon('back')} Коллекции</a>
      <h1 class="page-title">${esc(album.name)}</h1><p class="page-description">${cardCount(total(album.counts))}${foil ? ` · фольга: ${foil}` : ''}</p></div>
      <div class="page-actions"><a class="button button-main" href="#scan/${id}">${icon('scan')} Сканировать</a>${iconButton('Экспорт CSV', 'export', 'download', `data-album="${id}"`)}</div></header>
    ${pending ? `<button class="button notice" data-action="review" data-album="${id}">${icon('info')}<span>Проверить: ${cardCount(pending)}</span>${icon('chevron')}</button>` : ''}
    <div class="toolbar">${searchField('album-query', 'Найти в альбоме…', albumQuery)}
      ${iconButton('Только отмеченные', 'filter-flags', 'flag', `aria-pressed="${flaggedOnly}"`)}
      ${iconButton('Группировать по названию', 'group', 'layers', `aria-pressed="${grouped}" ${selection ? 'disabled' : ''}`)}
      ${iconButton(selection ? 'Снять выбор' : 'Выбрать карты', 'select', selection ? 'close' : 'list', `aria-pressed="${Boolean(selection)}"`)}</div>
    <div id="album-results">${albumResults(album)}</div>`;
}

function visibleVariants(album) {
  return Object.keys(album.counts).map((id) => cards[id])
    .filter((card) => (!flaggedOnly || album.flags.includes(card.id)) && matches(card, albumQuery));
}

function groupsByName(list) {
  const byName = new Map();
  for (const card of list) {
    if (!byName.has(card.name)) byName.set(card.name, []);
    byName.get(card.name).push(card);
  }
  return [...byName.values()];
}

function stepper(kind, key, count, min = 0, max = Number.MAX_SAFE_INTEGER) {
  return `<div class="stepper" role="group" aria-label="Количество">
    ${iconButton('Уменьшить количество', kind, 'minus', `data-card="${key}" data-step="-1" ${count <= min ? 'disabled' : ''}`)}
    <output>${count}</output>
    ${iconButton('Увеличить количество', kind, 'plus', `data-card="${key}" data-step="1" ${count >= max ? 'disabled' : ''}`)}</div>`;
}

function albumResults(album) {
  const visible = visibleVariants(album);
  const rows = grouped && !selection ? groupsByName(visible) : visible.map((card) => [card]);
  const content = rows.map((variants) => {
    const [card] = variants;
    const count = variants.reduce((sum, variant) => sum + album.counts[variant.id], 0);
    const meta = variants.length > 1 ? counted(variants.length, 'вариант', 'варианта', 'вариантов') : edition(card, { styled: true });
    if (!selection) return cardRow(card, meta, { album: album.id, count, flag: variants.some((variant) => album.flags.includes(variant.id)) });
    const chosen = selection[card.id] || 0;
    return cardRow(card, `${meta} · в альбоме ${count}`, {
      action: 'pick', album: album.id, checked: chosen > 0,
      controls: stepper('picked-count', card.id, chosen, 0, count),
    });
  }).join('');
  const selectionBar = selection ? `<div class="selection"><strong aria-live="polite">Выбрано: ${specimenCount(total(selection))}</strong>
    ${button('Выбрать лишние', 'extras', '', 'button-light', visible.some((card) => album.counts[card.id] > 1) ? '' : 'disabled')}
    ${button('Переместить', 'move-selected', 'swap', 'button-main', total(selection) ? '' : 'disabled')}</div>` : '';
  const placeholder = albumQuery || flaggedOnly
    ? empty('Карты не найдены', 'Измените запрос или сбросьте фильтр.', 'search')
    : empty('В альбоме пока нет карт', 'Добавьте первую карту через сканер или каталог.');
  return `${selectionBar}<div class="list-panel">${content || placeholder}</div>`;
}

function renderCatalog({ name }) {
  const owned = name === 'owned';
  return `<header class="subpage-head"><div><h1 class="page-title">Поиск карт</h1><p class="page-description">По названию, коду выпуска или номеру</p></div></header>
    ${searchField('catalog-query', 'Например, Sol Ring или Выбор', catalogQuery)}
    <div class="search-tabs" aria-label="Где искать">
      ${button('Каталог', 'scope', '', '', `data-scope="catalog" aria-pressed="${!owned}"`)}
      ${button('Мои карты', 'scope', '', '', `data-scope="owned" aria-pressed="${owned}"`)}
    </div><div class="list-panel catalog-results" id="catalog-results">${catalogResults(owned)}</div>`;
}

function catalogResults(owned) {
  const matching = Object.values(cards).filter((card) => matches(card, catalogQuery));
  const rows = groupsByName(matching).flatMap((variants) => {
    const [card] = variants;
    if (!owned) {
      const meta = `${esc(card.alias)} · ${counted(variants.length, 'вариант', 'варианта', 'вариантов')}`;
      return cardRow(card, meta, { action: 'add-card' });
    }
    return library.albums.flatMap((album) => {
      const present = variants.filter((variant) => album.counts[variant.id]);
      if (!present.length) return [];
      const count = present.reduce((sum, variant) => sum + album.counts[variant.id], 0);
      return [cardRow(present[0], esc(album.name), { album: album.id, count })];
    });
  });
  return rows.join('') || empty('Карты не найдены', 'Попробуйте другое название или код выпуска.', 'search');
}

function albumOptions(albums, selected = '') {
  return albums.map((album) => `<option value="${album.id}" ${selected === album.id ? 'selected' : ''}>${esc(album.name)}</option>`).join('');
}

function renderScanner() {
  const album = getAlbum(scanAlbum) || library.albums[0];
  const pending = library.pending.filter((row) => row.album === album.id).length;
  const recent = recentRows(album.id);
  return `<header class="subpage-head"><div><h1 class="page-title">Сканер</h1><p class="page-description">Добавление карт в выбранный альбом</p></div></header>
    <div class="scan-layout"><section class="scan-panel" aria-label="Видоискатель">
      <div class="scan-toolbar"><label>${icon('library')}<select id="scan-album" aria-label="Альбом для сканирования">${albumOptions(library.albums, album.id)}</select></label>
        ${button('Настройки', 'batch', 'layers', 'button-ghost')}</div>
      <div class="viewfinder">
        <div class="viewfinder-frame">
          <img src="media/bouncer.webp" width="226" height="316" alt="Пример карты Bouncer’s Beatdown">
          <span class="reticle" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
        </div>
        <p class="scan-guide">Поместите карту в рамку</p>
      </div>
      <div class="scan-dock">${button('Сканировать пример', 'capture', 'camera', 'button-main')}<p>Демонстрационный кадр</p></div></section>
      <section class="scan-side" aria-labelledby="scan-recent"><div class="section-head"><h2 id="scan-recent">Недавние в альбоме</h2></div>
        ${pending ? `<button type="button" class="button notice" data-action="review" data-album="${album.id}">${icon('info')}<span>Проверить: ${cardCount(pending)}</span>${icon('chevron')}</button>` : ''}
        <div class="list-panel">${recent || empty('Пока нет добавлений', 'Подтверждённые карты появятся здесь.')}</div></section></div>`;
}

function showSheet(title, content) {
  sheet.innerHTML = `<div class="sheet-inner"><header class="sheet-heading"><h2 id="sheet-title">${esc(title)}</h2>
    <button class="icon-button" type="button" data-action="close" aria-label="Закрыть">${icon('close')}</button></header>${content}</div>`;
  if (!sheet.open) sheet.showModal();
}

function formMarkup(action, fields, submit, attributes = '') {
  return `<form class="sheet-form" data-form="${action}" ${attributes}>${fields}<div class="sheet-actions">
    ${button('Отмена', 'close', '', 'button-ghost')}<button class="button button-main" type="submit">${submit}</button></div></form>`;
}

function createSheet() {
  showSheet('Новый альбом', formMarkup('create', `<label class="field">Название
    <input name="name" placeholder="Например, На обмен" autocomplete="off" maxlength="60" required autofocus></label>`, 'Создать'));
}

function printingOptions(variants, current) {
  return variants.map((card) => `<option value="${card.id}" ${card.id === current ? 'selected' : ''}>${edition(card)}</option>`).join('');
}

function showDetail(album, key, focus = '') {
  const card = cards[key];
  const variants = Object.keys(album.counts).map((id) => cards[id]).filter((other) => other.name === card.name);
  const quantity = album.counts[key];
  const marked = album.flags.includes(key);
  sheet.dataset.album = album.id;
  showSheet(card.name, `<div class="sheet-card"><img src="media/${card.art}.webp" alt="${esc(card.name)}">
    <div class="sheet-card-copy"><small>${esc(card.alias)}</small>
      ${variants.length > 1 ? `<label class="field">Вариант карты<select id="detail-variant">${printingOptions(variants, key)}</select></label>` : `<p>${edition(card, { styled: true })}</p>`}
      <small>${esc(album.name)}</small></div></div>
    <div class="sheet-count"><strong>Экземпляров</strong>${stepper('detail-count', key, quantity, 1)}</div>
    <div class="sheet-actions">
      ${button('Убрать', 'remove', '', 'button-ghost button-warn', `data-album="${album.id}" data-card="${key}"`)}
      ${iconButton(marked ? 'Снять флажок' : 'Отметить карту', 'toggle-flag', 'flag', `aria-pressed="${marked}" data-album="${album.id}" data-card="${key}"`)}
      ${button('Переместить', 'move-one', 'swap', 'button-main', `data-album="${album.id}" data-card="${key}"`)}</div>`);
  if (focus) (sheet.querySelector(focus) || sheet.querySelector('[data-action="close"]')).focus();
}

function addSheet(key) {
  const card = cards[key];
  const variants = Object.values(cards).filter((other) => other.name === card.name);
  showSheet(card.name, formMarkup('add', `<div class="sheet-card"><img id="add-art" src="media/${card.art}.webp" alt="${esc(card.name)}">
    <div class="sheet-card-copy"><small>${esc(card.alias)}</small><label class="field">Вариант карты
      <select id="add-variant" name="card">${printingOptions(variants, key)}</select></label></div></div>
    <label class="field">Альбом<select name="album">${albumOptions(library.albums)}</select></label>
    <label class="field">Экземпляров<input name="quantity" type="number" value="1" min="1" max="999" step="1" required></label>`, 'Добавить'));
}

function showMove(album, quantities, single = false) {
  const entries = Object.entries(quantities).filter(([, count]) => count > 0);
  if (!entries.length) return;
  const destinations = library.albums.filter((destination) => destination.id !== album.id);
  const items = entries.map(([key, count]) => `<li>${esc(cards[key].name)} · ${edition(cards[key], { styled: true })}${single ? '' : ` · <span class="edition-code">×${count}</span>`}</li>`).join('');
  const quantityInput = single ? `<label class="field">Сколько экземпляров переместить
    <input name="quantity" type="number" min="1" max="${entries[0][1]}" value="1" required></label>` : '';
  showSheet('Переместить карты', formMarkup('move', `<ul class="move-list">${items}</ul>${quantityInput}
    <label class="field">Куда переместить<select id="move-album" name="destination" required>
      ${destinations.length ? '<option value="" disabled selected>Выберите альбом</option>' : ''}${albumOptions(destinations)}
      <option value="new">Создать коллекцию</option></select></label>
    <label id="new-destination" class="field" ${destinations.length ? 'hidden' : ''}>Название нового альбома
      <input name="newName" maxlength="60" placeholder="Например, На обмен" ${destinations.length ? '' : 'required'}></label>`, 'Переместить',
  `data-album="${album.id}" ${single ? `data-card="${entries[0][0]}"` : ''}`));
}

function makeAlbum(name) {
  return { id: uid(), name, cover: null, counts: {}, flags: [] };
}

function getName(form, input) {
  const field = form.elements[input];
  const name = field.value.trim();
  field.setCustomValidity(name ? '' : 'Введите название альбома.');
  if (!name) field.reportValidity();
  return name;
}

function moveCards(form, fields) {
  const from = getAlbum(form.dataset.album);
  const key = form.dataset.card;
  const quantities = key ? { [key]: Number(fields.get('quantity')) } : selection;
  const entries = Object.entries(quantities || {}).filter(([, count]) => count > 0);
  if (!entries.length || !entries.every(([id, count]) => count <= from.counts[id])) return;

  const destination = fields.get('destination');
  const name = destination === 'new' ? getName(form, 'newName') : '';
  if (destination === 'new' && !name) return;
  const to = destination === 'new' ? makeAlbum(name) : getAlbum(destination);
  if (!to || to === from) return;

  sheet.close();
  selection = null;
  commit(() => {
    if (name) library.albums.push(to);
    for (const [id, count] of entries) {
      const flagged = from.flags.includes(id);
      addCount(from, id, -count);
      addCount(to, id, count);
      if (flagged && !to.flags.includes(id)) to.flags.push(id);
      record(to.id, id);
    }
  }, `Перемещено в «${to.name}»: ${cardCount(total(quantities))}`, true);
}

function reviewSheet(albumId) {
  const pending = library.pending.find((row) => row.album === albumId);
  if (!pending) return;
  const options = [cards.bouncer, cards['bouncer-ru']].filter((card) => pending.language === 'auto' || card.language === pending.language);
  const [first] = options;
  showSheet('Проверить карту', formMarkup('review', `<div class="sheet-card"><img id="review-art" src="media/${first.art}.webp" alt="${esc(first.name)}">
    <div class="sheet-card-copy"><strong>${esc(first.name)}</strong><br><small>${esc(getAlbum(albumId).name)}</small></div></div>
    ${options.map((card, index) => `<label class="sheet-choice"><input type="radio" name="card" value="${card.id}" ${index ? '' : 'checked'}>
      <span><strong>${sides[card.language]}</strong><small>${edition(card, { styled: true })}</small></span></label>`).join('')}
    <label class="field-check"><input type="checkbox" name="foil"> Фольга</label>`, 'Подтвердить', `data-pending="${esc(pending.id)}"`));
  sheet.querySelector('.sheet-actions').insertAdjacentHTML('afterbegin',
    button('Отклонить', 'discard-scan', '', 'button-ghost button-warn', `data-pending="${esc(pending.id)}"`));
}

function scannerCapture() {
  const album = getAlbum(scanAlbum) || library.albums[0];
  commit(() => { library.pending.unshift({ id: uid(), album: album.id, language: scanLanguage }); });
  reviewSheet(album.id);
}

function batchSheet() {
  showSheet('Настройки стопки', formMarkup('batch', `<p class="sheet-p">В примере используется карта из «Улиц Новой Капенны», <span class="edition-code">SNC</span>.</p>
    <label class="field">Язык<select name="language"><option value="auto">Авто</option>
      <option value="en" ${scanLanguage === 'en' ? 'selected' : ''}>Английский</option>
      <option value="ru" ${scanLanguage === 'ru' ? 'selected' : ''}>Русский</option></select></label>`, 'Сохранить'));
}

function download(name, content, mime) {
  const url = URL.createObjectURL(new Blob([content], { type: mime }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function exportCsv(album, flagged = false) {
  const quote = (value) => `"${String(value).replaceAll('"', '""')}"`;
  const rows = ['Count,Name,Edition,Condition,Language,Foil,Collector Number'];
  for (const [id, count] of Object.entries(album.counts)) {
    if (flagged && !album.flags.includes(id)) continue;
    const { name, set, language, foil, number } = cards[id];
    rows.push([count, name, set, '', language === 'ru' ? 'Russian' : 'English', foil ? 'foil' : '', number].map(quote).join(','));
  }
  download(`${album.name.replace(/[<>:"/\\|?*]/g, '_')}.csv`, `${rows.join('\r\n')}\r\n`, 'text/csv;charset=utf-8');
  sheet.close();
  notify('CSV для Moxfield сохранён');
}

function exportSheet(album) {
  if (!album.flags.length) return exportCsv(album);
  showSheet('Экспорт CSV', formMarkup('export', `<p class="sheet-p">Сохранение в формате Moxfield CSV.</p>
    <label class="sheet-choice"><input type="radio" name="scope" value="all" checked><span>Вся коллекция</span></label>
    <label class="sheet-choice"><input type="radio" name="scope" value="flagged"><span>Только отмеченные</span></label>`, 'Сохранить CSV', `data-album="${album.id}"`));
}

function backupSheet() {
  showSheet('Резервная копия', `<p class="sheet-p">Файл содержит альбомы, флажки и очередь проверки из этого прототипа.</p>
    <div class="backup-actions">${button('Сохранить в JSON', 'save-backup', 'download')}${button('Восстановить из JSON', 'load-backup', 'upload')}</div>
    <input type="file" id="backup-file" accept=".json,application/json" hidden><p class="sheet-p" id="backup-error" role="alert" hidden></p>`);
}

async function readBackup(file) {
  const error = document.querySelector('#backup-error');
  if (!file || !error) return;
  try {
    const backup = JSON.parse(await file.text());
    if (backup.version !== 1 || !validLibrary(backup.library)) throw new Error();
    showSheet('Восстановить альбомы?', formMarkup('restore', `<p class="sheet-p">В файле ${albumCount(backup.library.albums.length)}. После восстановления они заменят текущую библиотеку.</p>`, 'Заменить альбомы'));
    sheet.querySelector('form').addEventListener('submit', (event) => {
      event.preventDefault();
      sheet.close();
      commit(() => { library = backup.library; }, 'Альбомы восстановлены', true);
      location.hash = '#library';
    }, { once: true });
  } catch {
    error.textContent = 'Не удалось прочитать файл прототипа «Картовед».';
    error.hidden = false;
  }
}

const actions = {
  create: createSheet,
  close: () => sheet.close(),
  backup: backupSheet,
  'all-owned': () => { catalogQuery = ''; },
  scope: (data) => { location.hash = `#${data.scope}`; },
  'filter-flags': () => { flaggedOnly = !flaggedOnly; refresh(); },
  group: () => { grouped = !grouped; refresh(); },
  select: () => { selection = selection ? null : {}; refresh(); },
  pick: ({ card }) => { selection[card] = selection[card] ? 0 : 1; refresh(); },
  'picked-count': ({ card, step }) => { selection[card] = (selection[card] || 0) + Number(step); refresh(); },
  extras: () => {
    const album = getAlbum(activeRoute.id);
    selection = Object.fromEntries(visibleVariants(album).map((card) => [card.id, album.counts[card.id] - 1]));
    refresh();
  },
  'move-selected': () => showMove(getAlbum(activeRoute.id), selection),
  'move-one': ({ album, card }) => showMove(getAlbum(album), { [card]: getAlbum(album).counts[card] }, true),
  detail: ({ album, card }) => showDetail(getAlbum(album), card),
  'detail-count': ({ card, step }, control) => {
    const album = getAlbum(sheet.dataset.album);
    const locator = controlLocator(control);
    commit(() => { addCount(album, card, Number(step)); });
    showDetail(album, card, locator);
  },
  'toggle-flag': ({ album: id, card }, control) => {
    const album = getAlbum(id);
    const marked = album.flags.includes(card);
    commit(() => { album.flags = marked ? album.flags.filter((flag) => flag !== card) : [...album.flags, card]; });
    showDetail(album, card, controlLocator(control));
  },
  remove: ({ album: id, card }) => {
    const album = getAlbum(id);
    sheet.close();
    commit(() => { addCount(album, card, -album.counts[card]); }, 'Карта убрана из альбома', true);
  },
  'add-card': ({ card }) => addSheet(card),
  capture: scannerCapture,
  review: ({ album }) => reviewSheet(album),
  'discard-scan': ({ pending }) => {
    sheet.close();
    commit(() => { library.pending = library.pending.filter((row) => row.id !== pending); }, 'Снимок отклонён', true);
  },
  batch: batchSheet,
  export: ({ album }) => exportSheet(getAlbum(album)),
  'load-backup': () => document.querySelector('#backup-file').click(),
  'save-backup': () => {
    download('kartoved-prototype.json', JSON.stringify({ version: 1, library }, null, 2), 'application/json');
    sheet.close();
    notify('Резервная копия сохранена');
  },
};

const formActions = {
  create: (form) => {
    const name = getName(form, 'name');
    if (!name) return;
    const album = makeAlbum(name);
    sheet.close();
    commit(() => { library.albums.push(album); }, `Создан альбом «${name}»`);
    location.hash = `#album/${album.id}`;
  },
  add: (form, fields) => {
    const album = getAlbum(fields.get('album'));
    const card = fields.get('card');
    const quantity = Number(fields.get('quantity'));
    sheet.close();
    commit(() => { addCount(album, card, quantity); record(album.id, card); }, `Добавлено в «${album.name}»: ${cardCount(quantity)}`, true);
  },
  move: moveCards,
  batch: (form, fields) => { scanLanguage = fields.get('language'); sheet.close(); },
  review: (form, fields) => {
    const pending = library.pending.find((row) => row.id === form.dataset.pending);
    if (!pending) return;
    const card = `${fields.get('card')}${fields.has('foil') ? '-foil' : ''}`;
    const album = getAlbum(pending.album);
    sheet.close();
    commit(() => {
      addCount(album, card, 1);
      library.pending = library.pending.filter((row) => row !== pending);
      record(album.id, card);
    }, `Добавлено в «${album.name}»`, true);
  },
  export: (form, fields) => exportCsv(getAlbum(form.dataset.album), fields.get('scope') === 'flagged'),
};

document.addEventListener('click', (event) => {
  const control = event.target.closest('[data-action]');
  if (control) actions[control.dataset.action]?.(control.dataset, control);
  else if (event.target === sheet) sheet.close();
});

document.addEventListener('submit', (event) => {
  const form = event.target;
  if (form.id === 'global-search') {
    event.preventDefault();
    catalogQuery = globalSearch.value;
    if (location.hash === '#catalog') refresh();
    else location.hash = '#catalog';
    return;
  }
  const handle = formActions[form.dataset.form];
  if (!handle) return;
  event.preventDefault();
  handle(form, new FormData(form));
});

document.addEventListener('input', (event) => {
  const input = event.target;
  if (input.id === 'catalog-query') {
    catalogQuery = input.value;
    document.querySelector('#catalog-results').innerHTML = catalogResults(activeRoute.name === 'owned');
  } else if (input.id === 'album-query') {
    albumQuery = input.value;
    document.querySelector('#album-results').innerHTML = albumResults(getAlbum(activeRoute.id));
  } else if (input.name === 'name' || input.name === 'newName') {
    input.setCustomValidity('');
  }
});

document.addEventListener('change', (event) => {
  const input = event.target;
  if (input.id === 'detail-variant') showDetail(getAlbum(sheet.dataset.album), input.value, '#detail-variant');
  else if (input.id === 'add-variant') document.querySelector('#add-art').src = `media/${cards[input.value].art}.webp`;
  else if (input.name === 'card' && input.type === 'radio') document.querySelector('#review-art').src = `media/${cards[input.value].art}.webp`;
  else if (input.id === 'move-album') {
    const label = document.querySelector('#new-destination');
    const field = label.querySelector('input');
    label.hidden = input.value !== 'new';
    field.required = !label.hidden;
    field.setCustomValidity('');
  } else if (input.id === 'scan-album') {
    scanAlbum = input.value;
    refresh();
  } else if (input.id === 'backup-file') readBackup(input.files[0]);
});

document.addEventListener('keydown', (event) => {
  if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey || sheet.open) return;
  if (event.target.closest('input, textarea, select, [contenteditable]') || !globalSearch.getClientRects().length) return;
  event.preventDefault();
  globalSearch.focus();
});

document.querySelector('#toast-undo').addEventListener('click', () => undoAction?.());
window.addEventListener('hashchange', () => {
  if (sheet.open) sheet.close();
  refresh();
});

refresh();
