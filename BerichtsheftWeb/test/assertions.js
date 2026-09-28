// Wird von model.test.js per vm.runInContext() NACH model.js/xlsx-io.js
// im selben Context ausgefuehrt — DAY_NAMES, buildWorkbook & Co. sind hier
// also normale, direkt nutzbare Bezeichner (siehe Kommentar in model.test.js).
// "var failed" statt "const", damit der Zaehler als echte Sandbox-Eigenschaft
// nach aussen sichtbar bleibt.
function assertEq(label, actual, expected) {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a === e) { console.log(`OK   ${label}`); return; }
  console.log(`FAIL ${label}\n  erwartet: ${e}\n  erhalten: ${a}`);
  failed++;
}

// --- ISO-Kalenderwochen, gegen echte Werte aus der iPhone-App geprueft ---
assertEq("CW17 2026 Montag", formatDateDE(isoMonday(2026, 17)), "20.04.2026");
assertEq("CW17 2026 Sonntag", formatDateDE(dateForDay(2026, 17, 6)), "26.04.2026");
assertEq("CW34 2026 Montag", formatDateDE(isoMonday(2026, 34)), "17.08.2026");
assertEq("Wochen in 2020 (bekannt: 53)", isoWeeksInYear(2020), 53);
assertEq("Wochen in 2025", isoWeeksInYear(2025), 52);
assertEq("Wochen in 2026", isoWeeksInYear(2026), 53);

// --- Beleg-Dateinamen — muss exakt zu Store.swift passen ---
assertEq("fileToken B&B", fileToken("B&B"), "BaB");
assertEq("receiptName mit Nullpadding CW", receiptName(2026, 7, "B&B", 1), "2026-CW07_BaB_01.pdf");
assertEq("receiptName Umlaut", receiptName(2026, 17, "SleepInn", 1), "2026-CW17_SleepInn_01.pdf");

// --- Steuerliche Berechnung ---
{
  const settings = newSettings();
  settings.kmHomeToWork = 245.3;
  settings.hotelRoutes.push({ hotel: "B&B", address: "", km: 1.8 });
  const w = newWeek(17);
  w.days[2] = { kind: "PB", activity: "", location: "" };
  w.bookings.push({ id: "t1", hotel: "B&B", nights: 2, amount: 139.73, receiptFile: "" });
  w.homeTrips = 1;
  // 20*0.30 + 225.3*0.38 (Heimfahrt) + 1.8*0.30 (Pendeln) = 92.154
  assertEq("Entfernungspauschale (Heimfahrt gestaffelt + Pendeln)", round2(weekAllowance(settings, w)), 92.15);
}

// --- Excel-Rundlauf: Umlaute, Sonderzeichen, Mehrfachbuchungen, Dezimalwerte ---
{
  const weeks = [
    {
      cw: 14,
      days: [
        newDay(), newDay(),
        { kind: "PB", activity: "Barker Introduction", location: "Paderborn" },
        { kind: "PB", activity: "Setup Tools/Laptop/Phone", location: "Paderborn" },
        { kind: "FT", activity: "Karfreitag", location: "" },
        newDay(), newDay(),
      ],
      bookings: [{ id: "b1", hotel: "B&B", nights: 2, amount: 139.73, receiptFile: "" }],
      note: "", homeTrips: 2, commuteDaysOverride: null,
    },
    {
      cw: 30,
      days: [
        { kind: "PB", activity: "", location: "Paderborn" }, { kind: "PB", activity: "", location: "Paderborn" },
        { kind: "PB", activity: "", location: "Paderborn" }, { kind: "PB", activity: "", location: "Paderborn" },
        { kind: "HO", activity: "", location: "" }, newDay(), newDay(),
      ],
      bookings: [
        { id: "b2", hotel: "InterCity", nights: 2, amount: 121.6, receiptFile: "2026-CW30_InterCity_01.pdf" },
        { id: "b3", hotel: "InterCity", nights: 1, amount: 60.8, receiptFile: "2026-CW30_InterCity_02.pdf" },
      ],
      note: "2 Buchungen", homeTrips: 1, commuteDaysOverride: null,
    },
  ];
  const settings = newSettings();
  settings.homeAddress = "Weinbergstr. 27, 63936 Schneeberg";
  settings.kmHomeToWork = 245.3;
  settings.hotelRoutes = [{ hotel: "B&B", address: "Bahnhofstraße 31, 33102 Paderborn", km: 1.8 }];

  const wb = buildWorkbook(2026, weeks, settings);
  const buf = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });
  const wb2 = XLSX.read(buf, { type: "buffer" });
  const parsed = parseWorkbook(wb2, 2026);
  const weeks2 = parsed.weeks, settings2 = parsed.settings, legacyImportCount = parsed.legacyImportCount;

  assertEq("Rundlauf: kein Legacy-Import ausgelöst (Tage/Buchungen-Blätter vorhanden)", legacyImportCount, 0);
  assertEq("Rundlauf: Anzahl Wochen", weeks2.length, 2);
  const w14 = weeks2.find((w) => w.cw === 14);
  assertEq("Rundlauf: Tätigkeit mit Sonderzeichen", w14.days[2].activity, "Barker Introduction");
  assertEq("Rundlauf: Feiertag-Text (Umlaut)", w14.days[4].activity, "Karfreitag");
  assertEq("Rundlauf: Hotel mit Sonderzeichen (&)", w14.bookings[0].hotel, "B&B");
  const w30 = weeks2.find((w) => w.cw === 30);
  assertEq("Rundlauf: zwei Buchungen erhalten", w30.bookings.length, 2);
  assertEq("Rundlauf: Beleg-Dateiname Buchung 2", w30.bookings[1].receiptFile, "2026-CW30_InterCity_02.pdf");
  assertEq("Rundlauf: Adresse mit ß (Straße)", settings2.hotelRoutes[0].address, "Bahnhofstraße 31, 33102 Paderborn");
  assertEq("Rundlauf: km-Dezimalwert", settings2.hotelRoutes[0].km, 1.8);
}

// --- Import einer alten Aggregat-Excel (ohne Tage-/Buchungen-Blaetter) ---
{
  const header = ["CW", "Hotel", "Nächte", "Summe", "PB Tage", "HO Tage", "FT", "U", "EZ", "Kind_Krank", "Krank"];
  const rows = [header, [14, "B&B", 2, 139.73, 2, 0, 1, 0, 0, 0, 0], [25, "EZ", 0, 0, 0, 0, 0, 0, 5, 0, 0]];
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(rows), "2026");
  const buf = XLSX.write(wb, { type: "buffer", bookType: "xlsx" });
  const wb2 = XLSX.read(buf, { type: "buffer" });
  const parsed = parseWorkbook(wb2, 2026);
  const weeks = parsed.weeks, legacyImportCount = parsed.legacyImportCount;

  assertEq("Legacy-Import: erkannte Wochen", legacyImportCount, 2);
  const w14 = weeks.find((w) => w.cw === 14);
  assertEq("Legacy-Import: PB-Tage rekonstruiert (Mo, Di)", w14.days.slice(0, 2).map((d) => d.kind), ["PB", "PB"]);
  assertEq("Legacy-Import: FT-Tag rekonstruiert (Mi)", w14.days[2].kind, "FT");
  assertEq("Legacy-Import: Buchung aus Hotel/Nächte/Summe", w14.bookings[0], { id: w14.bookings[0].id, hotel: "B&B", nights: 2, amount: 139.73, receiptFile: "" });
  const w25 = weeks.find((w) => w.cw === 25);
  assertEq("Legacy-Import: EZ-Woche ohne Buchung", w25.bookings.length, 0);
  assertEq("Legacy-Import: EZ an 5 Tagen", w25.days.slice(0, 5).every((d) => d.kind === "EZ"), true);
}
