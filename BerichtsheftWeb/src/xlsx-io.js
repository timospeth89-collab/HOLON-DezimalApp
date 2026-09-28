// Excel-Lesen/-Schreiben. Vier Blaetter in einer Arbeitsmappe:
//   "<Jahr>"      Aggregat-Uebersicht (menschenlesbar, wie die urspruengliche
//                 Berichtsheft-Tabelle) — wird bei jedem Speichern neu erzeugt,
//                 NIE zurueckgelesen. Nur eine Anzeige, keine Datenquelle.
//   "Tage"        Ein Eintrag je ausgefuelltem Tag — Quelle fuer die Tagesart.
//   "Buchungen"   Ein Eintrag je Hotelbuchung — Quelle fuer Naechte/Betrag/Beleg.
//   "Einstellungen"  Adressen, km, Saetze, Hotel-Strecken.
//
// Beim Laden zaehlen NUR "Tage"/"Buchungen"/"Einstellungen". Fehlen diese drei
// komplett (z. B. beim allerersten Import einer alten, einfachen Excel-Tabelle
// mit nur CW/Hotel/Naechte/Summe/PB Tage/HO Tage/...), wird aus dem
// Aggregat-Blatt eine Naeherung rekonstruiert — siehe importLegacyAggregate.

const SUMMARY_HEADER = [
  "CW", "Hotel", "Nächte", "Summe", "PB Tage", "HO Tage", "Dienstreise", "FT",
  "U", "EZ", "Kind_Krank", "Krank", "Heimfahrten", "Fahrtage", "km einfach",
  "Pauschale", "Tage erfasst",
];

function buildWorkbook(year, weeks, settings) {
  const wb = XLSX.utils.book_new();

  // Blatt 1: Aggregat-Uebersicht, exakt wie die urspruengliche Excel + Erweiterungen.
  const rows = [SUMMARY_HEADER];
  const totalWeeks = isoWeeksInYear(year);
  const tot = { nights: 0, amount: 0, pb: 0, ho: 0, dr: 0, ft: 0, u: 0, ez: 0, kk: 0, kr: 0, home: 0, days: 0, allow: 0 };
  for (let cw = 1; cw <= totalWeeks; cw++) {
    const w = weeks.find((w) => w.cw === cw);
    if (!w || isWeekEmpty(w)) {
      rows.push([cw, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]);
      continue;
    }
    const pb = weekCount(w, "PB"), ho = weekCount(w, "HO"), dr = weekCount(w, "DR"), ft = weekCount(w, "FT");
    const u = weekCount(w, "U"), ez = weekCount(w, "EZ"), kk = weekCount(w, "KiKr"), kr = weekCount(w, "Kr");
    const allow = weekAllowance(settings, w);
    const check = weekIsComplete(w) ? "5/5" : `${weekdaysFilled(w)}/5 !`;
    rows.push([
      cw, hotelLabel(w), weekNights(w), round2(weekAmount(w)), pb, ho, dr, ft, u, ez, kk, kr,
      w.homeTrips, commuteDays(w), round2(commuteKm(settings, w)), round2(allow), check,
    ]);
    tot.nights += weekNights(w); tot.amount += weekAmount(w);
    tot.pb += pb; tot.ho += ho; tot.dr += dr; tot.ft += ft; tot.u += u; tot.ez += ez; tot.kk += kk; tot.kr += kr;
    tot.home += w.homeTrips; tot.days += commuteDays(w); tot.allow += allow;
  }
  rows.push([
    "Summe", "", tot.nights, round2(tot.amount), tot.pb, tot.ho, tot.dr, tot.ft, tot.u, tot.ez, tot.kk, tot.kr,
    tot.home, tot.days, "", round2(tot.allow), "",
  ]);
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(rows), String(year));

  // Blatt 2: Tage.
  const dayRows = [["CW", "Datum", "Tag", "Art", "Tätigkeit", "Ort"]];
  for (const w of weeks) {
    if (isWeekEmpty(w)) continue;
    w.days.forEach((d, i) => {
      if (isDayEmpty(d)) return;
      dayRows.push([w.cw, formatDateDE(dateForDay(year, w.cw, i)), DAY_NAMES[i], d.kind, d.activity, d.location]);
    });
  }
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(dayRows), "Tage");

  // Blatt 3: Buchungen.
  const bookingRows = [["CW", "Index", "Hotel", "Nächte", "Betrag", "Beleg-Datei"]];
  for (const w of weeks) {
    w.bookings.forEach((b, i) => {
      bookingRows.push([w.cw, i + 1, b.hotel, b.nights, round2(b.amount), b.receiptFile]);
    });
  }
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(bookingRows), "Buchungen");

  // Blatt 4: Einstellungen.
  const setRows = [
    ["Schlüssel", "Wert"],
    ["homeAddress", settings.homeAddress],
    ["workAddress", settings.workAddress],
    ["kmHomeToWork", settings.kmHomeToWork],
    ["rateFirst", settings.rateFirst],
    ["rateAbove", settings.rateAbove],
    ["thresholdKm", settings.thresholdKm],
    [],
    ["Hotel-Strecken", ""],
    ["Hotel", "Adresse", "km"],
  ];
  settings.hotelRoutes.forEach((r) => setRows.push([r.hotel, r.address, r.km]));
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(setRows), "Einstellungen");

  return wb;
}

function sheetToRows(wb, name) {
  const sheet = wb.Sheets[name];
  if (!sheet) return null;
  return XLSX.utils.sheet_to_json(sheet, { header: 1, defval: "" });
}

function parseWorkbook(wb, year) {
  const weeksMap = new Map();
  const getWeek = (cw) => {
    if (!weeksMap.has(cw)) weeksMap.set(cw, newWeek(cw));
    return weeksMap.get(cw);
  };

  const tage = sheetToRows(wb, "Tage");
  const buchungen = sheetToRows(wb, "Buchungen");

  if (tage) {
    for (let i = 1; i < tage.length; i++) {
      const [cw, , tag, art, akt, ort] = tage[i];
      if (!cw) continue;
      const w = getWeek(Number(cw));
      const idx = DAY_NAMES.indexOf(tag);
      if (idx >= 0) w.days[idx] = { kind: art || "frei", activity: akt || "", location: ort || "" };
    }
  }
  if (buchungen) {
    for (let i = 1; i < buchungen.length; i++) {
      const [cw, , hotel, nights, amount, receipt] = buchungen[i];
      if (!cw) continue;
      const w = getWeek(Number(cw));
      w.bookings.push({ id: uid(), hotel: hotel || "", nights: Number(nights) || 0, amount: Number(amount) || 0, receiptFile: receipt || "" });
    }
  }

  const settings = newSettings();
  settings.hotelRoutes = [];
  const einst = sheetToRows(wb, "Einstellungen");
  if (einst) {
    let inRoutes = false;
    for (const row of einst) {
      const [a, b, c] = row;
      if (a === "Hotel-Strecken") { inRoutes = false; continue; }
      if (a === "Hotel" && b === "Adresse") { inRoutes = true; continue; }
      if (inRoutes) { if (a) settings.hotelRoutes.push({ hotel: a, address: b || "", km: Number(c) || 0 }); continue; }
      if (a === "homeAddress") settings.homeAddress = b || settings.homeAddress;
      else if (a === "workAddress") settings.workAddress = b || settings.workAddress;
      else if (a === "kmHomeToWork") settings.kmHomeToWork = Number(b) || 0;
      else if (a === "rateFirst") settings.rateFirst = Number(b) || 0.3;
      else if (a === "rateAbove") settings.rateAbove = Number(b) || 0.38;
      else if (a === "thresholdKm") settings.thresholdKm = Number(b) || 20;
    }
  }

  let legacyImportCount = 0;
  if (!tage && !buchungen) {
    legacyImportCount = importLegacyAggregate(wb, year, weeksMap);
  }

  const weeks = Array.from(weeksMap.values()).sort((a, b) => a.cw - b.cw);
  return { weeks, settings, legacyImportCount };
}

// Rekonstruiert aus einer alten Aggregat-Excel (nur Zaehler pro Woche, keine
// Tage-Zuordnung) ein plausibles Wochenmodell: die Tagesarten werden in
// fester Reihenfolge (PB, HO, FT, U, EZ, KiKr, Kr) auf Mo-Fr verteilt, eine
// Buchung pro Woche aus Hotel/Naechte/Summe. Das ist eine Naeherung — welcher
// Wochentag genau PB oder HO war, steht im alten Format nicht drin. Gibt die
// Anzahl importierter Wochen zurueck, damit die UI einen Hinweis zeigen kann.
function importLegacyAggregate(wb, year, weeksMap) {
  const sheetName = wb.SheetNames.includes(String(year)) ? String(year) : wb.SheetNames[0];
  const rows = sheetToRows(wb, sheetName);
  if (!rows || rows.length < 2) return 0;

  // Header-Zeile robust erkennen: erste Zeile, deren erste Zelle "CW" enthaelt.
  let headerIdx = rows.findIndex((r) => String(r[0]).trim().toUpperCase() === "CW");
  if (headerIdx < 0) headerIdx = 0;
  const header = rows[headerIdx].map((h) => String(h).trim());
  const col = (name) => header.indexOf(name);
  const iCW = col("CW"), iHotel = col("Hotel"), iNaechte = col("Nächte"), iSumme = col("Summe");
  const iPB = col("PB Tage"), iHO = col("HO Tage"), iFT = col("FT"), iU = col("U"), iEZ = col("EZ");
  const iKK = col("Kind_Krank"), iKr = col("Krank");
  if (iCW < 0) return 0;

  let count = 0;
  for (let i = headerIdx + 1; i < rows.length; i++) {
    const row = rows[i];
    const cw = Number(row[iCW]);
    if (!cw || String(row[iCW]).trim() === "Summe") continue;
    const num = (idx) => (idx >= 0 ? Number(row[idx]) || 0 : 0);
    const hotel = iHotel >= 0 ? String(row[iHotel] || "").trim() : "";
    const naechte = num(iNaechte), summe = num(iSumme);
    const counts = [["PB", num(iPB)], ["HO", num(iHO)], ["FT", num(iFT)], ["U", num(iU)], ["EZ", num(iEZ)], ["KiKr", num(iKK)], ["Kr", num(iKr)]];
    const anyCount = counts.some(([, n]) => n > 0);
    if (!hotel && naechte === 0 && !anyCount) continue; // leere Woche

    const w = newWeek(cw);
    let slot = 0;
    for (const [kind, n] of counts) {
      for (let k = 0; k < n && slot < 5; k++, slot++) w.days[slot] = { kind, activity: "", location: "" };
    }
    if (hotel && naechte > 0) {
      w.bookings.push({ id: uid(), hotel, nights: naechte, amount: summe, receiptFile: "" });
    }
    weeksMap.set(cw, w);
    count++;
  }
  return count;
}
