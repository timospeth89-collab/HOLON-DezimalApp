// Laedt die fertige berichtsheft.html in echtem Chromium (Playwright) und
// prueft Laden, Bedienung und den Import-Weg fuer die alte Excel-Tabelle.
// Nicht Teil der automatischen CI (Playwright-Browser-Download waere dort
// ein spuerbarer Mehraufwand) -- vor jedem Release manuell laufen lassen:
//
//   npm install -g playwright   (einmalig, falls noch nicht vorhanden)
//   npx playwright install chromium
//   node test/browser.test.js
//
// Voraussetzung: berichtsheft.html wurde vorher gebaut (python3 build.py).
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const HTML_PATH = path.join(__dirname, "../berichtsheft.html");
const LEGACY_SAMPLE_PATH = path.join(__dirname, "legacy-sample.xlsx");

let failed = 0;
function check(label, cond) {
  console.log((cond ? "OK   " : "FAIL ") + label);
  if (!cond) failed++;
}

async function main() {
  if (!fs.existsSync(HTML_PATH)) {
    console.error(`${HTML_PATH} fehlt — vorher "python3 build.py" ausfuehren.`);
    process.exit(1);
  }

  const browser = await chromium.launch();
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (err) => errors.push(err.message));
  page.on("console", (msg) => { if (msg.type() === "error") errors.push("[console] " + msg.text()); });

  // --- 1) Laden: leerer Zustand, keine Fehler ---------------------------
  await page.goto("file://" + HTML_PATH);
  await page.waitForTimeout(300);
  check("Ordner-wählen-Button sichtbar", (await page.$("#btn-pick")) !== null);

  // --- 2) Kernfunktionen im echten Browser-JS -----------------------------
  const core = await page.evaluate(() => ({
    cw17monday: formatDateDE(isoMonday(2026, 17)),
    weeksIn2026: isoWeeksInYear(2026),
    fileToken: fileToken("B&B"),
  }));
  check("CW17 2026 Montag = 20.04.2026", core.cw17monday === "20.04.2026");
  check("2026 hat 53 ISO-Wochen", core.weeksIn2026 === 53);
  check("fileToken('B&B') = BaB", core.fileToken === "BaB");

  // --- 3) Bedienung: Ordner "verbunden" simulieren, Tag+Buchung anlegen ---
  await page.evaluate(() => {
    state.dirHandle = { name: "SteuerHotelFahrtkosten-Test" };
    state.folderName = state.dirHandle.name;
    state.fileFound = true;
    state.weeks = [];
    state.settings = newSettings();
    render();
  });
  await page.selectOption(".day-kind[data-day='2']", "PB");
  await page.fill(".day-activity[data-day='2']", "Test-Tätigkeit äöü");
  await page.click("#btn-add-booking");
  await page.fill(".booking-hotel[data-booking='0']", "B&B");
  await page.fill(".booking-amount[data-booking='0']", "139.73");
  const bookingSummary = await page.textContent("#booking-summary");
  check("Buchungs-Summe zeigt Betrag", bookingSummary.includes("139,73"));

  for (const tab of ["auswertung", "steuer", "belege"]) {
    await page.click(`[data-tab='${tab}']`);
    await page.waitForTimeout(100);
    check(`Tab "${tab}" rendert ohne Fehler`, (await page.$("h1")) !== null);
  }

  // --- 4) Import der alten Excel-Tabelle ueber echten Datei-Dialog --------
  await page.evaluate(() => {
    state.dirHandle = { name: "SteuerHotelFahrtkosten" };
    state.folderName = "SteuerHotelFahrtkosten";
    state.fileFound = false;
    state.weeks = [];
    state.year = 2026;
    render();
  });
  await page.setInputFiles("#legacy-input", LEGACY_SAMPLE_PATH);
  await page.waitForTimeout(300);
  const cw14 = await page.evaluate(() => {
    const w = state.weeks.find((w) => w.cw === 14);
    return w ? { kinds: w.days.map((d) => d.kind), hotel: w.bookings[0]?.hotel } : null;
  });
  check("Legacy-Import: CW14 PB/PB/FT rekonstruiert", cw14 && cw14.kinds.slice(0, 3).join(",") === "PB,PB,FT");
  check("Legacy-Import: CW14 Buchung B&B übernommen", cw14 && cw14.hotel === "B&B");

  check("Keine JS-Fehler während des gesamten Durchlaufs", errors.length === 0);
  if (errors.length) console.log(errors.join("\n"));

  await browser.close();
  console.log(failed === 0 ? "\n=== ALLE BROWSER-TESTS BESTANDEN ===" : `\n=== ${failed} FEHLER ===`);
  process.exit(failed === 0 ? 0 : 1);
}

main();
