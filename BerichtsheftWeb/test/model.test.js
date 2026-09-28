// Regressionstest fuer model.js + xlsx-io.js — laeuft in Node (keine
// Browser-DOM-Abhaengigkeit in diesen beiden Dateien) und in CI ohne Xcode.
// Aufruf: node test/model.test.js
//
// model.js, xlsx-io.js und assertions.js laufen alle im selben
// vm.createContext() nacheinander — das bildet exakt nach, wie die drei
// echten <script>-Tags in berichtsheft.html eine gemeinsame globale
// Lexical Environment teilen (Browser-Verhalten, kein Modul-System). Ein
// simples eval() bildet das NICHT nach: dessen top-level "const" verschwindet
// nach jedem Aufruf wieder, was hier faelschlich wie ein App-Fehler aussehen
// wuerde, obwohl der ausgelieferte Code (dreifach in echtem Chromium
// getestet) korrekt ist.
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const sandbox = { console, failed: 0, crypto };
sandbox.XLSX = require(path.join(__dirname, "../src/vendor/xlsx.full.min.js"));
const ctx = vm.createContext(sandbox);

function load(rel) {
  const code = fs.readFileSync(path.join(__dirname, rel), "utf8");
  vm.runInContext(code, ctx, { filename: rel });
}

load("../src/model.js");
load("../src/xlsx-io.js");
load("assertions.js");

console.log(sandbox.failed === 0 ? "\n=== ALLE TESTS BESTANDEN ===" : `\n=== ${sandbox.failed} FEHLER ===`);
process.exit(sandbox.failed === 0 ? 0 : 1);
