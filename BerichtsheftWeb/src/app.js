// App-Schicht: Ordner-/Dateizugriff (File System Access API), Speichern,
// und die vier Tabs (Woche, Auswertung, Steuer, Belege).
//
// Architektur-Hinweis zu Texteingaben: Ein volles Neu-Rendern des Tabs bei
// jedem Tastendruck würde den Cursor aus dem Eingabefeld werfen. Deshalb
// aktualisieren Texteingaben (Tätigkeit/Ort/Hotel/Betrag/Notiz/Adressen) den
// Zustand per oninput OHNE Neu-Rendern — nur die davon abhängigen, separat
// referenzierten Anzeige-Elemente (Prüfsumme, Beleg-Namensvorschau, Summen)
// werden gezielt per textContent aktualisiert. Strukturelle Änderungen
// (Buchung hinzufügen/löschen, Tagesart wählen, Stepper) rendern den Tab neu.

const state = {
  tab: "woche",
  year: currentYear(),
  cw: currentWeek(),
  weeks: [],
  settings: newSettings(),
  dirHandle: null,
  folderName: "",
  folderFiles: [],
  fileFound: false,
  legacyImportCount: 0,
  saveStatus: "idle", // idle|pending|saving|saved|error
  saveError: null,
  lastSaved: null,
};

function getWeek(cw) {
  let w = state.weeks.find((w) => w.cw === cw);
  if (!w) {
    w = newWeek(cw);
    state.weeks.push(w);
    state.weeks.sort((a, b) => a.cw - b.cw);
  }
  return w;
}
function currentWeekObj() {
  return getWeek(state.cw);
}

// --- IndexedDB: Ordner-Handle über Sitzungen hinweg merken -----------------

const DB_NAME = "berichtsheft-web";
const STORE = "handles";

function idbOpen() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
async function idbSet(key, val) {
  const db = await idbOpen();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put(val, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}
async function idbGet(key) {
  const db = await idbOpen();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readonly");
    const req = tx.objectStore(STORE).get(key);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// --- Ordnerzugriff ----------------------------------------------------------

function fsAccessSupported() {
  return typeof window.showDirectoryPicker === "function";
}

async function pickFolder() {
  try {
    const handle = await window.showDirectoryPicker({ id: "berichtsheft", mode: "readwrite" });
    state.dirHandle = handle;
    await idbSet("dir", handle).catch(() => {});
    await loadFromFolder();
  } catch (e) {
    if (e && e.name !== "AbortError") alertError("Ordner konnte nicht geöffnet werden: " + e.message);
  }
}

async function tryAutoReconnect() {
  const handle = await idbGet("dir").catch(() => null);
  if (!handle) return false;
  state.dirHandle = handle;
  state.folderName = handle.name;
  return true;
}

async function confirmReconnect() {
  try {
    const opts = { mode: "readwrite" };
    let perm = await state.dirHandle.queryPermission(opts);
    if (perm !== "granted") perm = await state.dirHandle.requestPermission(opts);
    if (perm === "granted") await loadFromFolder();
    else alertError("Zugriff auf den Ordner wurde nicht erlaubt.");
  } catch (e) {
    alertError("Verbindung zum Ordner fehlgeschlagen: " + e.message);
  }
  render();
}

async function refreshFolderListing() {
  if (!state.dirHandle) return;
  const files = [];
  for await (const [name, handle] of state.dirHandle.entries()) {
    if (handle.kind === "file") files.push(name);
  }
  state.folderFiles = files;
}

async function loadFromFolder() {
  state.folderName = state.dirHandle.name;
  await refreshFolderListing();
  const xlsxName = `Berichtsheft_${state.year}.xlsx`;
  if (state.folderFiles.includes(xlsxName)) {
    const fh = await state.dirHandle.getFileHandle(xlsxName);
    const file = await fh.getFile();
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: "array" });
    const parsed = parseWorkbook(wb, state.year);
    state.weeks = parsed.weeks;
    state.settings = parsed.settings;
    state.legacyImportCount = parsed.legacyImportCount;
    state.fileFound = true;
  } else {
    state.weeks = [];
    state.settings = newSettings();
    state.fileFound = false;
    state.legacyImportCount = 0;
  }
  render();
}

async function importLegacyFile(file) {
  try {
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: "array" });
    const parsed = parseWorkbook(wb, state.year);
    if (parsed.legacyImportCount === 0 && state.weeks.length === 0) {
      alertError("In dieser Datei wurden keine passenden Spalten gefunden (erwartet: CW, Hotel, Nächte, Summe, PB Tage, HO Tage, FT, U, EZ, Kind_Krank, Krank).");
      return;
    }
    state.weeks = parsed.weeks;
    if (parsed.legacyImportCount > 0) state.legacyImportCount = parsed.legacyImportCount;
    state.fileFound = true;
    render();
    scheduleSave();
  } catch (e) {
    alertError("Datei konnte nicht gelesen werden: " + e.message);
  }
}

// --- Speichern (debounced) --------------------------------------------------

let saveTimer = null;
function scheduleSave() {
  if (!state.dirHandle) return;
  clearTimeout(saveTimer);
  state.saveStatus = "pending";
  updateSaveBar();
  saveTimer = setTimeout(doSave, 700);
}
async function doSave() {
  state.saveStatus = "saving";
  updateSaveBar();
  try {
    const wb = buildWorkbook(state.year, state.weeks, state.settings);
    const buf = XLSX.write(wb, { type: "array", bookType: "xlsx" });
    const fh = await state.dirHandle.getFileHandle(`Berichtsheft_${state.year}.xlsx`, { create: true });
    const writable = await fh.createWritable();
    await writable.write(buf);
    await writable.close();
    state.saveStatus = "saved";
    state.lastSaved = new Date();
    state.fileFound = true;
    await refreshFolderListing();
  } catch (e) {
    state.saveStatus = "error";
    state.saveError = e.message;
  }
  updateSaveBar();
}
async function saveNow() {
  clearTimeout(saveTimer);
  await doSave();
}

function updateSaveBar() {
  const el = document.getElementById("savebar");
  if (!el) return;
  el.className = "savebar " + state.saveStatus;
  const label = {
    idle: "Noch nicht gespeichert",
    pending: "Änderungen …",
    saving: "Speichere …",
    saved: state.lastSaved ? `Gespeichert um ${state.lastSaved.toLocaleTimeString("de-DE")}` : "Gespeichert",
    error: "Fehler beim Speichern: " + (state.saveError || ""),
  }[state.saveStatus];
  el.innerHTML = `<span class="dot"></span><span>${label}</span>`;
}

function alertError(msg) {
  const el = document.getElementById("errorbar");
  if (!el) { console.error(msg); return; }
  el.textContent = msg;
  el.hidden = false;
  clearTimeout(alertError._t);
  alertError._t = setTimeout(() => { el.hidden = true; }, 8000);
}

// --- Beleg-Check -------------------------------------------------------------

function computeReceiptChecks() {
  const existingSet = new Set(state.folderFiles);
  const existingLower = new Map(state.folderFiles.map((f) => [f.toLowerCase(), f]));
  const rows = [];
  for (const w of state.weeks) {
    w.bookings.forEach((b, i) => {
      const expected = receiptName(state.year, w.cw, b.hotel, i + 1);
      let status = "missing", foundAs = null;
      if (existingSet.has(expected)) status = "ok";
      else if (existingLower.has(expected.toLowerCase())) { status = "warn"; foundAs = existingLower.get(expected.toLowerCase()); }
      else if (b.receiptFile && existingSet.has(b.receiptFile)) { status = "warn"; foundAs = b.receiptFile; }
      rows.push({ cw: w.cw, hotel: b.hotel || "(ohne Namen)", index: i + 1, expected, status, foundAs });
    });
  }
  return rows;
}
function receiptStatusFor(week, bookingIndex) {
  const b = week.bookings[bookingIndex];
  const expected = receiptName(state.year, week.cw, b.hotel, bookingIndex + 1);
  const existingSet = new Set(state.folderFiles);
  const existingLower = new Map(state.folderFiles.map((f) => [f.toLowerCase(), f]));
  if (existingSet.has(expected)) return { status: "ok", expected };
  if (existingLower.has(expected.toLowerCase())) return { status: "warn", expected, foundAs: existingLower.get(expected.toLowerCase()) };
  if (b.receiptFile && existingSet.has(b.receiptFile)) return { status: "warn", expected, foundAs: b.receiptFile };
  return { status: "missing", expected };
}

// --- Kleine DOM-Helfer -------------------------------------------------------

function h(strings, ...values) {
  return strings.reduce((out, s, i) => out + s + (i < values.length ? esc(values[i]) : ""), "");
}
function esc(v) {
  if (v == null) return "";
  return String(v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}
function raw(v) { return v; } // bewusst ungeescaptes Fragment (z. B. verschachteltes Markup)

function on(id, event, fn) {
  const el = document.getElementById(id);
  if (el) el.addEventListener(event, fn);
}

// --- Sidebar / Grundgerüst ---------------------------------------------------

const ICONS = {
  woche: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 9.5h17M8 2.8v3.4M16 2.8v3.4"/></svg>',
  auswertung: '<svg viewBox="0 0 24 24"><rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M3.5 9h17M3.5 14h17M9.5 4v16"/></svg>',
  steuer: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M12 7v10M9.2 9.3c0-1.3 1.2-2.3 2.8-2.3s2.8 1 2.8 2.1c0 1.4-1.2 1.9-2.8 2.4-1.6.5-2.8 1-2.8 2.4 0 1.1 1.2 2.1 2.8 2.1s2.8-1 2.8-2.3"/></svg>',
  belege: '<svg viewBox="0 0 24 24"><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-10.5Z"/></svg>',
};

function yearOptions() {
  const stored = state.weeks.length ? [state.year] : [];
  const set = new Set([currentYear() - 1, currentYear(), currentYear() + 1, ...stored, state.year]);
  return [...set].sort((a, b) => a - b);
}

function renderShell() {
  document.getElementById("app").innerHTML = `
    <nav class="side">
      <div class="brand">
        <div class="logo"><svg viewBox="0 0 24 24"><path d="M5 4.5A2.5 2.5 0 0 1 7.5 2H19v17.5H7.5A2.5 2.5 0 0 0 5 22V4.5Z" fill="none" stroke="#29EB9F" stroke-width="1.6"/><path d="M5 19.5A2.5 2.5 0 0 1 7.5 17H19" fill="none" stroke="#29EB9F" stroke-width="1.6"/></svg></div>
        <b>Berichtsheft</b>
      </div>
      <div class="yearpick">
        <span style="font-size:11.5px;color:var(--mut)">Jahr</span>
        <select id="year-select">${yearOptions().map((y) => `<option value="${y}" ${y === state.year ? "selected" : ""}>${y}</option>`).join("")}</select>
      </div>
      <button class="tab ${state.tab === "woche" ? "on" : ""}" data-tab="woche">${ICONS.woche}Woche</button>
      <button class="tab ${state.tab === "auswertung" ? "on" : ""}" data-tab="auswertung">${ICONS.auswertung}Auswertung</button>
      <button class="tab ${state.tab === "steuer" ? "on" : ""}" data-tab="steuer">${ICONS.steuer}Steuer</button>
      <button class="tab ${state.tab === "belege" ? "on" : ""}" data-tab="belege">${ICONS.belege}Belege</button>
      <div class="spacer"></div>
      <div style="padding:8px 10px;">
        <div style="font-size:11px;color:var(--mut);margin-bottom:4px;">${state.folderName ? "📁 " + esc(state.folderName) : "Kein Ordner verbunden"}</div>
        <div id="savebar" class="savebar"></div>
      </div>
      <div id="errorbar" class="hint err" hidden style="padding:0 10px;"></div>
    </nav>
    <main id="main"></main>
  `;
  document.querySelectorAll("nav.side button.tab").forEach((btn) => {
    btn.addEventListener("click", () => { state.tab = btn.dataset.tab; renderMain(); });
  });
  on("year-select", "change", async (e) => {
    state.year = Number(e.target.value);
    state.cw = Math.min(state.cw, isoWeeksInYear(state.year));
    if (state.dirHandle) await loadFromFolder(); else renderMain();
  });
  updateSaveBar();
}

function render() {
  renderShell();
  renderMain();
}

function renderMain() {
  const main = document.getElementById("main");
  if (!state.dirHandle) { main.innerHTML = renderConnectPrompt(); wireConnectPrompt(); return; }
  if (!state.fileFound && state.weeks.length === 0) { main.innerHTML = renderEmptyFolderState(); wireEmptyFolderState(); return; }
  if (state.tab === "woche") { main.innerHTML = renderWoche(); wireWoche(); }
  else if (state.tab === "auswertung") { main.innerHTML = renderAuswertung(); wireAuswertung(); }
  else if (state.tab === "steuer") { main.innerHTML = renderSteuer(); wireSteuer(); }
  else if (state.tab === "belege") { main.innerHTML = renderBelege(); wireBelege(); }
}

// --- Verbindungs-/Leerzustände ----------------------------------------------

function renderConnectPrompt() {
  if (!fsAccessSupported()) {
    return `<div class="empty-state">
      <h3>Dieser Browser wird nicht unterstützt</h3>
      <p>Für den Ordnerzugriff wird die File System Access API benötigt — die gibt es in Google Chrome und Microsoft Edge, aber nicht in Firefox oder Safari. Bitte diese Datei in Chrome öffnen.</p>
    </div>`;
  }
  return `<div class="empty-state">
    <svg viewBox="0 0 24 24"><path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2v-10.5Z"/></svg>
    <h3>${state.folderName ? "Mit Ordner verbinden" : "Ordner wählen"}</h3>
    <p style="max-width:420px;margin:0 auto;">
      ${state.folderName
        ? `Der zuletzt verwendete Ordner „${esc(state.folderName)}“ ist gemerkt — der Browser verlangt aber bei jedem Neuöffnen einen Klick, um den Zugriff zu bestätigen.`
        : `Wähle deinen iCloud-Jahresordner (z. B. SteuerHotelFahrtkosten/${state.year}) — die Datei Berichtsheft_${state.year}.xlsx wird dort gelesen und gespeichert, genau wie bei der iPhone-App.`}
    </p>
    <div class="actions">
      ${state.folderName ? `<button class="primary" id="btn-reconnect">Verbinden</button><button id="btn-pick-other">Anderen Ordner wählen</button>` : `<button class="primary" id="btn-pick">Ordner wählen</button>`}
    </div>
  </div>`;
}
function wireConnectPrompt() {
  on("btn-pick", "click", pickFolder);
  on("btn-pick-other", "click", pickFolder);
  on("btn-reconnect", "click", confirmReconnect);
}

function renderEmptyFolderState() {
  return `<div class="empty-state">
    <svg viewBox="0 0 24 24"><path d="M12 3v11M8 6.5 12 3l4 3.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8"/></svg>
    <h3>Noch keine Daten für ${state.year}</h3>
    <p style="max-width:440px;margin:0 auto;">Im Ordner „${esc(state.folderName)}“ liegt noch keine Berichtsheft_${state.year}.xlsx. Entweder leer starten, oder deine bisherige Excel-Tabelle importieren.</p>
    <div class="actions">
      <button class="primary" id="btn-start-empty">Leer starten</button>
      <button id="btn-import-legacy">Alte Excel importieren…</button>
    </div>
    <input type="file" id="legacy-input" accept=".xlsx,.xls" hidden>
  </div>`;
}
function wireEmptyFolderState() {
  on("btn-start-empty", "click", () => { state.weeks = []; state.fileFound = true; scheduleSave(); render(); });
  on("btn-import-legacy", "click", () => document.getElementById("legacy-input").click());
  on("legacy-input", "change", (e) => { if (e.target.files[0]) importLegacyFile(e.target.files[0]); });
}

// --- Tab: Woche ---------------------------------------------------------------

function renderWoche() {
  const w = currentWeekObj();
  const mon = isoMonday(state.year, state.cw);
  const sun = dateForDay(state.year, state.cw, 6);
  const legacyNotice = state.legacyImportCount > 0
    ? `<div class="card" style="border-color:#4a3a1f;background:#1a160c;"><div class="hint warn" style="margin:0;">⚠ ${state.legacyImportCount} Wochen wurden aus der alten Excel übernommen — die Tagesart-Verteilung auf Mo–Fr ist dabei geschätzt (Reihenfolge PB, HO, FT, U, EZ, KiKr, Kr), da das alte Format keine Tageszuordnung kennt. Bitte insbesondere aktuelle Wochen prüfen und ggf. korrigieren.</div></div>`
    : "";

  return `
    <h1>Berichtsheft</h1>
    <p class="sub">${state.year} · Ordner: ${esc(state.folderName)}</p>
    ${legacyNotice}
    <div class="card">
      <div class="row">
        <button id="btn-prev-week" class="ghost">&larr;</button>
        <div style="flex:1;text-align:center;">
          <select id="cw-select" class="plain" style="width:auto;display:inline-block;font-weight:700;color:var(--grn);font-size:16px;border:0;background:none;">
            ${Array.from({ length: isoWeeksInYear(state.year) }, (_, i) => i + 1)
              .map((cw) => `<option value="${cw}" ${cw === state.cw ? "selected" : ""}>CW ${cw}</option>`).join("")}
          </select>
          <div class="hint" style="margin:0;">${formatDateDE(mon)} – ${formatDateDE(sun)}</div>
        </div>
        <button id="btn-next-week" class="ghost">&rarr;</button>
      </div>
    </div>

    <div class="card">
      <h2>Tage <span id="checksum-badge" class="hint ${weekIsComplete(w) ? "" : "warn"}" style="margin:0;">${weekIsComplete(w) ? "✓ 5/5" : `⚠ ${weekdaysFilled(w)}/5`}</span>
        <span class="right">
          <button class="small" data-fill="PB">Mo–Fr PB</button>
          <button class="small" data-fill="HO">Mo–Fr HO</button>
          <button class="small" data-fill="DR">Mo–Fr DR</button>
          <button class="small" data-fill="U">Mo–Fr Urlaub</button>
          <button class="small" data-fill="EZ">Mo–Fr EZ</button>
        </span>
      </h2>
      <table class="daytable"><tbody>
        ${w.days.map((d, i) => renderDayRow(w, d, i)).join("")}
      </tbody></table>
    </div>

    <div class="card">
      <h2>Hotel / Buchungen <span id="booking-summary" class="right">${weekNights(w) > 0 ? `${weekNights(w)} Nächte · ${germanNumber(weekAmount(w))} €` : ""}</span></h2>
      <div id="bookings-list">${w.bookings.map((b, i) => renderBooking(w, b, i)).join("") || `<p class="hint" style="margin:0;">Keine Buchung diese Woche.</p>`}</div>
      <div style="margin-top:10px;"><button id="btn-add-booking">+ Buchung hinzufügen</button></div>
    </div>

    <div class="card">
      <h2>Fahrten <span id="allowance-preview" class="right">${weekAllowance(state.settings, w) > 0 ? germanNumber(weekAllowance(state.settings, w)) + " €" : ""}</span></h2>
      <div class="row wrap" style="margin-bottom:10px;">
        <span style="font-size:13px;">Familienheimfahrten:</span>
        <button class="small" id="home-minus">−</button>
        <b id="home-trips-val" style="min-width:16px;text-align:center;">${w.homeTrips}</b>
        <button class="small" id="home-plus">+</button>
        <span class="hint" style="margin:0;">${w.homeTrips === 1 ? "Fahrt" : "Fahrten"}</span>
      </div>
      <div class="row wrap">
        <span style="font-size:13px;">Fahrtage Unterkunft→Arbeit:</span>
        <button class="small" id="commute-minus">−</button>
        <b id="commute-days-val" style="min-width:16px;text-align:center;">${commuteDays(w)}</b>
        <button class="small" id="commute-plus">+</button>
        <span class="hint" style="margin:0;">${w.commuteDaysOverride == null ? "automatisch aus PB-Tagen" : "manuell gesetzt"}</span>
        ${w.commuteDaysOverride != null ? `<button class="small ghost" id="commute-auto">zurücksetzen</button>` : ""}
      </div>
      ${primaryHotel(w) ? `<div class="hint" style="margin-top:8px;">${commuteKm(state.settings, w) > 0 ? `${esc(primaryHotel(w))}: ${germanNumber(commuteKm(state.settings, w))} km einfach` : `Für „${esc(primaryHotel(w))}“ ist im Steuer-Tab noch keine Strecke hinterlegt.`}</div>` : ""}
    </div>

    <div class="card">
      <h2>Notiz</h2>
      <textarea id="week-note" rows="2" placeholder="z. B. Priv. Fahrt …">${esc(w.note)}</textarea>
    </div>
  `;
}

function renderDayRow(w, d, i) {
  const date = dateForDay(state.year, w.cw, i);
  return `<tr data-day="${i}">
    <td class="dcol"><b>${DAY_NAMES[i]}</b><span>${formatDateDE(date).slice(0, 5)}</span></td>
    <td class="bcol">
      <select class="plain day-kind" data-day="${i}" style="font-family:var(--mono);font-size:11px;">
        ${DAY_KINDS.map((k) => `<option value="${k.id}" ${k.id === d.kind ? "selected" : ""}>${k.id}</option>`).join("")}
      </select>
    </td>
    <td class="fcol">
      <input type="text" class="day-activity" data-day="${i}" placeholder="Tätigkeit (z. B. V103 OpenLoop Test)" value="${esc(d.activity)}">
      <input type="text" class="day-location" data-day="${i}" placeholder="Ort" value="${esc(d.location)}">
    </td>
  </tr>`;
}

function renderBooking(w, b, i) {
  const rc = receiptStatusFor(w, i);
  const statusClass = rc.status === "ok" ? "ok" : rc.status === "warn" ? "warn" : "missing";
  const statusText = rc.status === "ok" ? "✓ " + rc.expected
    : rc.status === "warn" ? `⚠ erwartet „${rc.expected}“, gefunden „${rc.foundAs}“`
    : `benötigt: ${rc.expected}`;
  return `<div class="booking" data-booking="${i}">
    <div class="row">
      <span class="ix">${String(i + 1).padStart(2, "0")}</span>
      <input type="text" class="grow booking-hotel" data-booking="${i}" placeholder="Hotel" value="${esc(b.hotel)}">
      <span class="hint" style="margin:0;">Nächte</span>
      <input type="number" class="nights booking-nights" data-booking="${i}" value="${b.nights}" min="0">
      <span class="hint" style="margin:0;">Betrag</span>
      <input type="number" class="amount booking-amount" data-booking="${i}" value="${b.amount}" step="0.01" min="0">
      <span class="hint" style="margin:0;">€</span>
      <button class="small danger ghost" data-remove-booking="${i}">✕</button>
    </div>
    <div class="receipt-preview ${statusClass}">${statusText}</div>
  </div>`;
}

function wireWoche() {
  on("btn-prev-week", "click", () => { step(-1); });
  on("btn-next-week", "click", () => { step(1); });
  on("cw-select", "change", (e) => { state.cw = Number(e.target.value); renderMain(); });

  document.querySelectorAll("[data-fill]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const w = currentWeekObj();
      for (let i = 0; i < 5; i++) w.days[i] = { ...w.days[i], kind: btn.dataset.fill };
      scheduleSave(); renderMain();
    });
  });

  document.querySelectorAll(".day-kind").forEach((sel) => {
    sel.addEventListener("change", (e) => {
      const w = currentWeekObj();
      w.days[Number(e.target.dataset.day)].kind = e.target.value;
      scheduleSave(); renderMain();
    });
  });
  document.querySelectorAll(".day-activity").forEach((inp) => {
    inp.addEventListener("input", (e) => {
      currentWeekObj().days[Number(e.target.dataset.day)].activity = e.target.value;
      scheduleSave();
    });
  });
  document.querySelectorAll(".day-location").forEach((inp) => {
    inp.addEventListener("input", (e) => {
      currentWeekObj().days[Number(e.target.dataset.day)].location = e.target.value;
      scheduleSave();
    });
  });

  on("btn-add-booking", "click", () => {
    const w = currentWeekObj();
    w.bookings.push(newBooking());
    if (w.homeTrips === 0) w.homeTrips = 1;
    scheduleSave(); renderMain();
  });
  document.querySelectorAll("[data-remove-booking]").forEach((btn) => {
    btn.addEventListener("click", () => {
      currentWeekObj().bookings.splice(Number(btn.dataset.removeBooking), 1);
      scheduleSave(); renderMain();
    });
  });
  document.querySelectorAll(".booking-hotel").forEach((inp) => {
    inp.addEventListener("input", (e) => {
      const w = currentWeekObj();
      w.bookings[Number(e.target.dataset.booking)].hotel = e.target.value;
      scheduleSave();
      patchBookingPreview(w, Number(e.target.dataset.booking));
      patchAllowancePreview(w);
    });
  });
  document.querySelectorAll(".booking-nights").forEach((inp) => {
    inp.addEventListener("input", (e) => {
      const w = currentWeekObj();
      w.bookings[Number(e.target.dataset.booking)].nights = Number(e.target.value) || 0;
      scheduleSave();
      patchBookingSummary(w);
    });
  });
  document.querySelectorAll(".booking-amount").forEach((inp) => {
    inp.addEventListener("input", (e) => {
      const w = currentWeekObj();
      w.bookings[Number(e.target.dataset.booking)].amount = Number(e.target.value) || 0;
      scheduleSave();
      patchBookingSummary(w);
    });
  });

  on("home-minus", "click", () => { const w = currentWeekObj(); w.homeTrips = Math.max(0, w.homeTrips - 1); scheduleSave(); renderMain(); });
  on("home-plus", "click", () => { const w = currentWeekObj(); w.homeTrips += 1; scheduleSave(); renderMain(); });
  on("commute-minus", "click", () => { const w = currentWeekObj(); w.commuteDaysOverride = Math.max(0, commuteDays(w) - 1); scheduleSave(); renderMain(); });
  on("commute-plus", "click", () => { const w = currentWeekObj(); w.commuteDaysOverride = commuteDays(w) + 1; scheduleSave(); renderMain(); });
  on("commute-auto", "click", () => { currentWeekObj().commuteDaysOverride = null; scheduleSave(); renderMain(); });

  on("week-note", "input", (e) => { currentWeekObj().note = e.target.value; scheduleSave(); });
}

function step(delta) {
  const total = isoWeeksInYear(state.year);
  let next = state.cw + delta;
  if (next < 1) { state.year -= 1; state.cw = isoWeeksInYear(state.year); loadFromFolder(); return; }
  if (next > total) { state.year += 1; state.cw = 1; loadFromFolder(); return; }
  state.cw = next;
  renderMain();
}

function patchBookingSummary(w) {
  const el = document.getElementById("booking-summary");
  if (el) el.textContent = weekNights(w) > 0 ? `${weekNights(w)} Nächte · ${germanNumber(weekAmount(w))} €` : "";
}
function patchBookingPreview(w, i) {
  const row = document.querySelector(`.booking[data-booking="${i}"] .receipt-preview`);
  if (!row) return;
  const rc = receiptStatusFor(w, i);
  row.className = "receipt-preview " + (rc.status === "ok" ? "ok" : rc.status === "warn" ? "warn" : "missing");
  row.textContent = rc.status === "ok" ? "✓ " + rc.expected
    : rc.status === "warn" ? `⚠ erwartet „${rc.expected}“, gefunden „${rc.foundAs}“`
    : `benötigt: ${rc.expected}`;
}
function patchAllowancePreview(w) {
  const el = document.getElementById("allowance-preview");
  if (el) el.textContent = weekAllowance(state.settings, w) > 0 ? germanNumber(weekAllowance(state.settings, w)) + " €" : "";
}

// --- Tab: Auswertung ---------------------------------------------------------

const COUNT_COLS = [
  ["PB", "pb"], ["HO", "ho"], ["DR", "dr"], ["FT", "ft"], ["U", "u"], ["EZ", "ez"], ["KiKr", "kk"], ["Kr", "kr"],
];
const KIND_BY_COL = { pb: "PB", ho: "HO", dr: "DR", ft: "FT", u: "U", ez: "EZ", kk: "KiKr", kr: "Kr" };

function renderAuswertung() {
  const totalWeeks = isoWeeksInYear(state.year);
  const totals = { nights: 0, amount: 0, pb: 0, ho: 0, home: 0, allow: 0 };
  const rows = [];
  for (let cw = 1; cw <= totalWeeks; cw++) {
    const w = state.weeks.find((w) => w.cw === cw);
    if (!w || isWeekEmpty(w)) { rows.push(`<tr class="empty"><td>${cw}</td><td></td><td class="l"></td><td></td><td></td>${COUNT_COLS.map(() => "<td></td>").join("")}<td></td><td></td><td></td></tr>`); continue; }
    const counts = Object.fromEntries(COUNT_COLS.map(([, key]) => [key, weekCount(w, KIND_BY_COL[key])]));
    const allow = weekAllowance(state.settings, w);
    totals.nights += weekNights(w); totals.amount += weekAmount(w);
    totals.pb += counts.pb; totals.ho += counts.ho; totals.home += w.homeTrips; totals.allow += allow;
    rows.push(`<tr>
      <td>${cw}</td>
      <td>${weekIsComplete(w) ? '<span class="status-dot ok"></span>' : '<span class="status-dot warn"></span>'}</td>
      <td class="l">${esc(hotelLabel(w))}</td>
      <td>${weekNights(w) || ""}</td>
      <td>${weekAmount(w) ? germanNumber(weekAmount(w)) : ""}</td>
      ${COUNT_COLS.map(([, key]) => `<td class="${key}">${counts[key] || ""}</td>`).join("")}
      <td>${w.homeTrips || ""}</td>
      <td>${commuteDays(w) || ""}</td>
      <td>${allow ? germanNumber(allow) : ""}</td>
    </tr>`);
  }
  return `
    <h1>Auswertung ${state.year}</h1>
    <p class="sub">Ordner: ${esc(state.folderName)}</p>
    <div class="tiles">
      <div class="tile"><b>${totals.nights}</b><span>Nächte</span></div>
      <div class="tile"><b>${germanNumber(totals.amount)}</b><span>Hotel €</span></div>
      <div class="tile"><b>${germanNumber(totals.allow)}</b><span>Pauschale €</span></div>
      <div class="tile"><b>${totals.home}</b><span>Heimfahrten</span></div>
    </div>
    <div class="card">
      <h2>Jahrestabelle <span class="right"><button class="small" id="btn-export-csv">CSV exportieren</button></span></h2>
      <div class="scroll"><table class="data">
        <thead><tr>
          <th>CW</th><th>✓</th><th class="l">Hotel</th><th>Nächte</th><th>Summe</th>
          ${COUNT_COLS.map(([label]) => `<th>${label}</th>`).join("")}
          <th>Heim</th><th>Tage</th><th>€</th>
        </tr></thead>
        <tbody>${rows.join("")}
          <tr class="total"><td>Σ</td><td></td><td class="l"></td><td>${totals.nights}</td><td>${germanNumber(totals.amount)}</td>
            ${COUNT_COLS.map(([, key]) => `<td>${totals[key] || 0}</td>`).join("")}
            <td>${totals.home}</td><td></td><td>${germanNumber(totals.allow)}</td>
          </tr>
        </tbody>
      </table></div>
    </div>
  `;
}
function wireAuswertung() {
  on("btn-export-csv", "click", exportSummaryCSV);
}
function exportSummaryCSV() {
  const header = ["CW", "Hotel", "Nächte", "Summe", "PB Tage", "HO Tage", "Dienstreise", "FT", "U", "EZ", "Kind_Krank", "Krank", "Heimfahrten", "Fahrtage", "km einfach", "Pauschale", "Tage erfasst"];
  const lines = [header.join(";")];
  const totalWeeks = isoWeeksInYear(state.year);
  for (let cw = 1; cw <= totalWeeks; cw++) {
    const w = state.weeks.find((w) => w.cw === cw);
    if (!w || isWeekEmpty(w)) { lines.push(`${cw};;;;;;;;;;;;;;;`); continue; }
    const check = weekIsComplete(w) ? "5/5" : `${weekdaysFilled(w)}/5 !`;
    lines.push([cw, hotelLabel(w), weekNights(w), germanNumber(weekAmount(w)), weekCount(w, "PB"), weekCount(w, "HO"), weekCount(w, "DR"), weekCount(w, "FT"), weekCount(w, "U"), weekCount(w, "EZ"), weekCount(w, "KiKr"), weekCount(w, "Kr"), w.homeTrips, commuteDays(w), germanNumber(commuteKm(state.settings, w)), germanNumber(weekAllowance(state.settings, w)), check].join(";"));
  }
  downloadText(`Berichtsheft_${state.year}.csv`, "﻿" + lines.join("\r\n") + "\r\n");
}
function downloadText(name, text) {
  const blob = new Blob([text], { type: "text/csv;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}

// --- Tab: Steuer --------------------------------------------------------------

function renderSteuer() {
  const s = taxSummary(state.weeks, state.settings);
  const set = state.settings;
  return `
    <h1>Steuer ${state.year}</h1>
    <p class="sub">Annahme: Paderborn ist erste Tätigkeitsstätte, Hotelkosten laufen über die doppelte Haushaltsführung. Ohne Gewähr — bitte steuerlich prüfen lassen.</p>

    <div class="card">
      <h2>Zusammenfassung</h2>
      <table class="data" style="width:100%;">
        <tr><td class="l">Übernachtung Zweitunterkunft</td><td class="l" style="color:var(--mut);font-size:11.5px;">${s.nights} Nächte</td><td>${germanNumber(s.lodging)} €</td></tr>
        <tr><td class="l">Familienheimfahrten</td><td class="l" style="color:var(--mut);font-size:11.5px;">${s.homeTrips} × ${germanNumber(set.kmHomeToWork)} km</td><td>${germanNumber(s.homeAllowance)} €</td></tr>
        <tr><td class="l">Unterkunft → Arbeit</td><td class="l" style="color:var(--mut);font-size:11.5px;">${s.commuteDays} Tage</td><td>${germanNumber(s.commuteAllowance)} €</td></tr>
        <tr class="total"><td class="l">Entfernungspauschale gesamt</td><td></td><td>${germanNumber(s.totalAllowance)} €</td></tr>
      </table>
      ${s.hotelsWithoutRoute.length ? `<div class="hint warn">⚠ Ohne Strecke: ${s.hotelsWithoutRoute.map(esc).join(", ")} — unten eintragen, sonst fehlen diese Fahrten in der Pauschale.</div>` : ""}
    </div>

    <div class="card">
      <h2>Familienheimfahrt</h2>
      <div class="row wrap">
        <label class="field grow"><span class="lbl">Von</span><input type="text" id="set-home-address" value="${esc(set.homeAddress)}"></label>
        <label class="field grow"><span class="lbl">Nach</span><input type="text" id="set-work-address" value="${esc(set.workAddress)}"></label>
        <label class="field" style="width:120px;"><span class="lbl">km einfach</span><input type="number" id="set-km-home" value="${set.kmHomeToWork}" step="0.1" min="0"></label>
      </div>
      <div class="hint">Eine Heimfahrt pro Woche ist bei doppelter Haushaltsführung ansetzbar — gerechnet wird die einfache Strecke.</div>
    </div>

    <div class="card">
      <h2>Hotel → Arbeit <span class="right"><button class="small" id="btn-add-route">+ Hotel</button></span></h2>
      <div class="hint" style="margin-bottom:10px;">Tagesstrecke je Unterkunft. Die App nimmt für jede Woche das Hotel der ersten Buchung.</div>
      <div id="routes-list">${set.hotelRoutes.map((r, i) => renderRouteRow(r, i)).join("") || `<p class="hint" style="margin:0;">Noch keine Hotels hinterlegt.</p>`}</div>
    </div>

    <div class="card">
      <h2>Entfernungspauschale (Sätze)</h2>
      <div class="row wrap">
        <label class="field" style="width:110px;"><span class="lbl">bis km</span><input type="number" id="set-threshold" value="${set.thresholdKm}" step="1" min="0"></label>
        <label class="field" style="width:110px;"><span class="lbl">€/km bis dahin</span><input type="number" id="set-rate-first" value="${set.rateFirst}" step="0.01" min="0"></label>
        <label class="field" style="width:110px;"><span class="lbl">€/km danach</span><input type="number" id="set-rate-above" value="${set.rateAbove}" step="0.01" min="0"></label>
      </div>
      <div class="hint">Voreingestellt 0,30 € bis 20 km, 0,38 € darüber — bitte fürs jeweilige Jahr gegenprüfen.</div>
    </div>

    <div class="card">
      <div class="hint" style="margin:0;">Diese App rechnet nach den oben genannten Annahmen. Ob und ab wann doppelte Haushaltsführung bei dir greift, gehört von einem Steuerberater oder Lohnsteuerhilfeverein bestätigt — das hier ist keine Steuerberatung.</div>
    </div>
  `;
}
function renderRouteRow(r, i) {
  return `<div class="row wrap" data-route="${i}" style="padding:7px 0;border-top:${i > 0 ? "1px solid var(--line)" : "0"};">
    <input type="text" class="route-hotel" data-route="${i}" style="width:150px;" placeholder="Hotel" value="${esc(r.hotel)}">
    <input type="text" class="grow route-address" data-route="${i}" placeholder="Adresse" value="${esc(r.address)}">
    <input type="number" class="route-km" data-route="${i}" style="width:80px;" placeholder="km" value="${r.km}" step="0.1" min="0">
    <span class="hint" style="margin:0;">km</span>
    <button class="small danger ghost" data-remove-route="${i}">✕</button>
  </div>`;
}
function wireSteuer() {
  on("set-home-address", "input", (e) => { state.settings.homeAddress = e.target.value; scheduleSave(); });
  on("set-work-address", "input", (e) => { state.settings.workAddress = e.target.value; scheduleSave(); });
  on("set-km-home", "input", (e) => { state.settings.kmHomeToWork = Number(e.target.value) || 0; scheduleSave(); patchTaxSummary(); });
  on("set-threshold", "input", (e) => { state.settings.thresholdKm = Number(e.target.value) || 0; scheduleSave(); patchTaxSummary(); });
  on("set-rate-first", "input", (e) => { state.settings.rateFirst = Number(e.target.value) || 0; scheduleSave(); patchTaxSummary(); });
  on("set-rate-above", "input", (e) => { state.settings.rateAbove = Number(e.target.value) || 0; scheduleSave(); patchTaxSummary(); });

  on("btn-add-route", "click", () => { state.settings.hotelRoutes.push({ hotel: "", address: "", km: 0 }); scheduleSave(); renderMain(); });
  document.querySelectorAll("[data-remove-route]").forEach((btn) => {
    btn.addEventListener("click", () => { state.settings.hotelRoutes.splice(Number(btn.dataset.removeRoute), 1); scheduleSave(); renderMain(); });
  });
  document.querySelectorAll(".route-hotel").forEach((inp) => inp.addEventListener("input", (e) => { state.settings.hotelRoutes[Number(e.target.dataset.route)].hotel = e.target.value; scheduleSave(); patchTaxSummary(); }));
  document.querySelectorAll(".route-address").forEach((inp) => inp.addEventListener("input", (e) => { state.settings.hotelRoutes[Number(e.target.dataset.route)].address = e.target.value; scheduleSave(); }));
  document.querySelectorAll(".route-km").forEach((inp) => inp.addEventListener("input", (e) => { state.settings.hotelRoutes[Number(e.target.dataset.route)].km = Number(e.target.value) || 0; scheduleSave(); patchTaxSummary(); }));
}
function patchTaxSummary() {
  if (state.tab !== "steuer") return;
  document.getElementById("main").innerHTML = renderSteuer();
  wireSteuer();
}

// --- Tab: Belege ----------------------------------------------------------------

function renderBelege() {
  const rows = computeReceiptChecks();
  const ok = rows.filter((r) => r.status === "ok").length;
  return `
    <h1>Belege ${state.year}</h1>
    <p class="sub">Ordner: ${esc(state.folderName)} <button class="small" id="btn-refresh-folder" style="margin-left:8px;">Ordner aktualisieren</button></p>
    <div class="tiles">
      <div class="tile"><b>${ok}/${rows.length}</b><span>Belege gefunden</span></div>
      <div class="tile"><b>${state.folderFiles.filter((f) => f.toLowerCase().endsWith(".pdf")).length}</b><span>PDFs im Ordner</span></div>
    </div>
    <div class="card">
      <h2>Buchungen vs. Belege</h2>
      <div class="scroll"><table class="data">
        <thead><tr><th class="l"></th><th class="l">CW</th><th class="l">Hotel</th><th class="l">Erwarteter Dateiname</th><th class="l">Gefunden als</th></tr></thead>
        <tbody>
          ${rows.map((r) => `<tr>
            <td><span class="status-dot ${r.status}"></span></td>
            <td class="l">${r.cw}</td>
            <td class="l">${esc(r.hotel)}</td>
            <td class="l" style="font-family:var(--mono);font-size:11.5px;">${esc(r.expected)}</td>
            <td class="l" style="font-family:var(--mono);font-size:11.5px;color:${r.status === "ok" ? "var(--grn)" : r.status === "warn" ? "var(--warn)" : "var(--mut2)"};">${r.foundAs ? esc(r.foundAs) : r.status === "missing" ? "— fehlt —" : "✓"}</td>
          </tr>`).join("") || `<tr><td colspan="5" class="l hint">Noch keine Buchungen erfasst.</td></tr>`}
        </tbody>
      </table></div>
    </div>
    <div class="card">
      <h2>Alle Dateien im Ordner</h2>
      <div class="scroll"><table class="data"><tbody>
        ${state.folderFiles.slice().sort().map((f) => `<tr><td class="l" style="font-family:var(--mono);font-size:11.5px;">${esc(f)}</td></tr>`).join("") || `<tr><td class="l hint">Ordner ist leer.</td></tr>`}
      </tbody></table></div>
    </div>
  `;
}
function wireBelege() {
  on("btn-refresh-folder", "click", async () => { await refreshFolderListing(); renderMain(); });
}

// --- Start -----------------------------------------------------------------

async function init() {
  render();
  const hadHandle = await tryAutoReconnect();
  render();
  if (hadHandle) {
    // Berechtigung ohne Klick pruefen (funktioniert, wenn schon einmal in
    // dieser Sitzung/diesem Origin bestaetigt) — sonst zeigt render() den
    // "Verbinden"-Button.
    try {
      const perm = await state.dirHandle.queryPermission({ mode: "readwrite" });
      if (perm === "granted") await loadFromFolder();
    } catch (e) { /* Handle ungueltig geworden — Nutzer waehlt neu */ }
  }
}

window.addEventListener("DOMContentLoaded", init);
