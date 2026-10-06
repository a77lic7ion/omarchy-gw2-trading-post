// GW2 Trading Post Model - parsing and formatting helpers

// Currency ID 1 is Gold in GW2
const GOLD_CURRENCY_ID = 1;
const COPPER_PER_SILVER = 100;
const SILVER_PER_GOLD = 100;
const COPPER_PER_GOLD = COPPER_PER_SILVER * SILVER_PER_GOLD;

function parseWallet(raw) {
  try {
    var data = JSON.parse(String(raw || "[]"));
    var gold = 0;
    for (var i = 0; i < data.length; i++) {
      if (data[i].id === GOLD_CURRENCY_ID) {
        gold = data[i].value;
        break;
      }
    }
    return gold;
  } catch (e) {
    return 0;
  }
}

function formatGold(copper) {
  if (copper === undefined || copper === null) return "0g";
  var c = parseInt(copper, 10);
  if (!isFinite(c) || c < 0) return "0g";

  var g = Math.floor(c / COPPER_PER_GOLD);
  var s = Math.floor((c % COPPER_PER_GOLD) / COPPER_PER_SILVER);
  var c_rem = c % COPPER_PER_SILVER;

  if (g > 0) {
    if (s > 0) return g + "g " + s + "s";
    return g + "g";
  }
  if (s > 0) return s + "s " + c_rem + "c";
  return c_rem + "c";
}

function formatGoldCompact(copper) {
  if (copper === undefined || copper === null) return "0g";
  var c = parseInt(copper, 10);
  if (!isFinite(c) || c < 0) return "0g";

  var g = Math.floor(c / COPPER_PER_GOLD);
  var s = Math.floor((c % COPPER_PER_GOLD) / COPPER_PER_SILVER);

  if (g >= 1000) return (g / 1000).toFixed(1) + "kg";
  if (g > 0) return g + "g";
  if (s > 0) return s + "s";
  return (c % COPPER_PER_SILVER) + "c";
}

function parseWizardVaultDailies(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"));
    var objectives = data.objectives || [];
    var pveObjectives = [];
    for (var i = 0; i < objectives.length; i++) {
      var obj = objectives[i];
      if (obj.track === "PvE") {
        var done = obj.claimed === true || (obj.progress_current >= obj.progress_complete);
        pveObjectives.push({
          id: obj.id,
          title: obj.title,
          acclaim: obj.acclaim,
          progressCurrent: obj.progress_current,
          progressComplete: obj.progress_complete,
          claimed: obj.claimed,
          done: done
        });
      }
    }
    return {
      metaProgressCurrent: data.meta_progress_current || 0,
      metaProgressComplete: data.meta_progress_complete || 10,
      objectives: pveObjectives
    };
  } catch (e) {
    return { metaProgressCurrent: 0, metaProgressComplete: 10, objectives: [] };
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseWallet: parseWallet,
    formatGold: formatGold,
    formatGoldCompact: formatGoldCompact,
    parseWizardVaultDailies: parseWizardVaultDailies,
    GOLD_CURRENCY_ID: GOLD_CURRENCY_ID,
    COPPER_PER_GOLD: COPPER_PER_GOLD
  };
}