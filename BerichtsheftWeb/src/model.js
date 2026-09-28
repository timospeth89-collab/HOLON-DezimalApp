// Datenmodell + Kalenderwochen-/Steuerlogik — 1:1 Portierung der Swift-Regeln
// aus BerichtsheftApp/Berichtsheft/Models.swift und Store.swift.
// Getestet gegen die echten Referenzdaten der iPhone-App (siehe roundtrip-test.js).

const DAY_KINDS = [
  { id: "PB", label: "PB (vor Ort)" },
  { id: "HO", label: "Home Office" },
  { id: "DR", label: "Dienstreise" },
  { id: "FT", label: "Feiertag" },
  { id: "U", label: "Urlaub" },
  { id: "EZ", label: "Elternzeit" },
  { id: "KiKr", label: "Kind krank" },
  { id: "Kr", label: "Krank" },
  { id: "frei", label: "frei" },
];
const DAY_KIND_LABEL = Object.fromEntries(DAY_KINDS.map((k) => [k.id, k.label]));
const DAY_NAMES = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
// Reihenfolge, in der die alte Aggregat-Excel (nur Zähler pro Woche, keine
// Tage-Zuordnung) beim Import auf Mo-Fr verteilt wird — siehe importLegacyAggregate.
const LEGACY_FILL_ORDER = ["PB", "HO", "FT", "U", "EZ", "KiKr", "Kr"];

function round2(v) {
  return Math.round((v + Number.EPSILON) * 100) / 100;
}

function uid() {
  return (crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`);
}

// --- ISO-8601-Kalenderwochen ---------------------------------------------

function isoWeekOf(date) {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = (d.getUTCDay() + 6) % 7; // Mo=0 .. So=6
  d.setUTCDate(d.getUTCDate() - dayNum + 3); // naechster Donnerstag
  const firstThursday = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  const fDayNum = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - fDayNum + 3);
  const week = 1 + Math.round((d - firstThursday) / (7 * 86400000));
  return { year: d.getUTCFullYear(), week };
}

function isoWeeksInYear(year) {
  return isoWeekOf(new Date(Date.UTC(year, 11, 28))).week;
}

function isoMonday(year, cw) {
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4DayNum = (jan4.getUTCDay() + 6) % 7;
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - jan4DayNum);
  const monday = new Date(week1Monday);
  monday.setUTCDate(week1Monday.getUTCDate() + (cw - 1) * 7);
  return monday;
}

function dateForDay(year, cw, dayIndex) {
  const mon = isoMonday(year, cw);
  const d = new Date(mon);
  d.setUTCDate(mon.getUTCDate() + dayIndex);
  return d;
}

function formatDateDE(d) {
  const dd = String(d.getUTCDate()).padStart(2, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  return `${dd}.${mm}.${d.getUTCFullYear()}`;
}

function currentYear() {
  return isoWeekOf(new Date()).year;
}
function currentWeek() {
  return isoWeekOf(new Date()).week;
}

// --- Modell: Tag / Buchung / Woche / Einstellungen ------------------------

function newDay() {
  return { kind: "frei", activity: "", location: "" };
}
function isDayEmpty(d) {
  return d.kind === "frei" && !d.activity && !d.location;
}

function newBooking() {
  return { id: uid(), hotel: "", nights: 2, amount: 0, receiptFile: "" };
}

function newWeek(cw) {
  return {
    cw,
    days: Array.from({ length: 7 }, newDay),
    bookings: [],
    note: "",
    homeTrips: 0,
    commuteDaysOverride: null, // null = automatisch aus PB-Tagen
  };
}

function newSettings() {
  return {
    homeAddress: "Weinbergstr. 27, 63936 Schneeberg",
    workAddress: "Elsener Str. 95, 33102 Paderborn",
    kmHomeToWork: 0,
    hotelRoutes: [], // {hotel, address, km}
    rateFirst: 0.3,
    rateAbove: 0.38,
    thresholdKm: 20,
  };
}

function weekNights(w) {
  return w.bookings.reduce((s, b) => s + (Number(b.nights) || 0), 0);
}
function weekAmount(w) {
  return w.bookings.reduce((s, b) => s + (Number(b.amount) || 0), 0);
}
function weekCount(w, kind) {
  return w.days.filter((d) => d.kind === kind).length;
}
function weekdaysFilled(w) {
  return w.days.slice(0, 5).filter((d) => d.kind !== "frei").length;
}
function weekIsComplete(w) {
  return weekdaysFilled(w) === 5;
}
function commuteDays(w) {
  return w.commuteDaysOverride != null ? w.commuteDaysOverride : weekCount(w, "PB");
}
function primaryHotel(w) {
  const b = w.bookings.find((b) => b.hotel);
  return b ? b.hotel : "";
}
function hotelLabel(w) {
  const hotels = [...new Set(w.bookings.map((b) => b.hotel).filter(Boolean))];
  if (hotels.length) return hotels.join(" + ");
  const workdays = w.days.slice(0, 5).map((d) => d.kind).filter((k) => k !== "frei");
  if (!workdays.length) return "";
  const counts = {};
  for (const k of workdays) counts[k] = (counts[k] || 0) + 1;
  const dominant = Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0];
  if (dominant === "U") return "Urlaub";
  if (dominant === "EZ") return "EZ";
  if (dominant === "HO") return "HO";
  return dominant;
}
function isWeekEmpty(w) {
  return (
    w.bookings.length === 0 &&
    !w.note &&
    w.homeTrips === 0 &&
    w.commuteDaysOverride == null &&
    w.days.every(isDayEmpty)
  );
}

// --- Steuerliche Berechnung (Entfernungspauschale) ------------------------
// Annahme: Paderborn ist erste Taetigkeitsstaette, Hotelkosten laufen ueber
// die doppelte Haushaltsfuehrung. Siehe TaxView.swift fuer den Hintergrund.

function allowanceForDistance(settings, km) {
  if (!(km > 0)) return 0;
  const first = Math.min(km, settings.thresholdKm) * settings.rateFirst;
  const above = Math.max(0, km - settings.thresholdKm) * settings.rateAbove;
  return first + above;
}
function kmForHotel(settings, hotel) {
  const r = settings.hotelRoutes.find((r) => r.hotel.toLowerCase() === (hotel || "").toLowerCase());
  return r ? Number(r.km) || 0 : 0;
}
function commuteKm(settings, w) {
  return kmForHotel(settings, primaryHotel(w));
}
function commuteAllowance(settings, w) {
  return commuteDays(w) * allowanceForDistance(settings, commuteKm(settings, w));
}
function homeAllowance(settings, w) {
  return w.homeTrips * allowanceForDistance(settings, settings.kmHomeToWork);
}
function weekAllowance(settings, w) {
  return commuteAllowance(settings, w) + homeAllowance(settings, w);
}

function taxSummary(weeks, settings) {
  const s = {
    nights: 0, lodging: 0, homeTrips: 0, homeAllowance: 0,
    commuteDays: 0, commuteAllowance: 0, hotelsWithoutRoute: [],
  };
  for (const w of weeks) {
    if (isWeekEmpty(w)) continue;
    s.nights += weekNights(w);
    s.lodging += weekAmount(w);
    s.homeTrips += w.homeTrips;
    s.homeAllowance += homeAllowance(settings, w);
    const days = commuteDays(w);
    const km = commuteKm(settings, w);
    s.commuteDays += days;
    s.commuteAllowance += commuteAllowance(settings, w);
    const hotel = primaryHotel(w);
    if (days > 0 && hotel && km === 0 && !s.hotelsWithoutRoute.includes(hotel)) {
      s.hotelsWithoutRoute.push(hotel);
    }
  }
  s.totalAllowance = s.homeAllowance + s.commuteAllowance;
  return s;
}

// --- Beleg-Dateinamen (muss exakt zu Store.swift passen) ------------------

function fileToken(s) {
  const map = { "&": "a", ä: "ae", ö: "oe", ü: "ue", Ä: "Ae", Ö: "Oe", Ü: "Ue", ß: "ss" };
  let t = s || "";
  for (const [k, v] of Object.entries(map)) t = t.split(k).join(v);
  t = t.replace(/[^a-zA-Z0-9]/g, "");
  return t || "Hotel";
}
function receiptName(year, cw, hotel, index) {
  return `${year}-CW${String(cw).padStart(2, "0")}_${fileToken(hotel)}_${String(index).padStart(2, "0")}.pdf`;
}

// --- Deutsche Zahlenformatierung (Komma statt Punkt) ----------------------

function germanNumber(v, decimals = 2) {
  return (Number(v) || 0).toLocaleString("de-DE", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}
