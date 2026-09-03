.pragma library

var FILTERS = "sort_by=_ASC&hwtype=0&maxprice=free&category1=998&supportedlang=english&specials=1"
var SEARCH_URL = "https://store.steampowered.com/search/?" + FILTERS
var RESULTS_URL = "https://store.steampowered.com/search/results/?" + FILTERS + "&query=&start=0&count=50&infinite=1&l=english"
var USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
var STALE_AFTER_MS = 45 * 60 * 1000
var BAR_ICON = "\u{F1B6}"
var MAX_BYTES = 4000000
var MAX_ROWS = 200
var MAX_TITLE = 120
var MAX_BLOCK = 20000
var MAX_SEEN_BYTES = 8192
var MAX_SEEN_IDS = 200
var SEEN_ID_RE = /^\d{1,10}$/
// Everything parsed out of the response is attacker-controlled if Steam is
// ever wrong: game.url reaches omarchy-launch-browser and the notification
// --exec, so nothing but a canonical Steam store URL may leave here.
var STORE_URL_RE = /^https:\/\/store\.steampowered\.com(\/[\w%.~/-]*)?$/i

function normalizeCountry(value) {
  var cc = String(value || "").trim().toUpperCase()
  return /^[A-Z]{2}$/.test(cc) ? cc : ""
}

function normalizeRefreshMinutes(value) {
  var minutes = Math.round(Number(value))
  if (!isFinite(minutes)) minutes = 15
  return Math.max(5, Math.min(180, minutes))
}

function withCountry(url, country) {
  var cc = normalizeCountry(country)
  return cc ? String(url) + "&cc=" + encodeURIComponent(cc) : String(url)
}

function searchUrl(country) {
  return withCountry(SEARCH_URL, country)
}

function resultsUrl(country) {
  return withCountry(RESULTS_URL, country)
}

function fetchArgs(url) {
  return [
    // No --compressed: --max-filesize is ignored without Content-Length,
    // so Panel wraps this in capped-run to bound what the collector keeps.
    "curl", "-fsS", "--max-time", "20",
    "--max-filesize", String(MAX_BYTES),
    "-A", USER_AGENT,
    "-H", "Accept: application/json,text/html;q=0.9",
    "-H", "X-Requested-With: XMLHttpRequest",
    String(url)
  ]
}

function emptyWatchState() {
  return { primed: false, ids: {} }
}

// Steam's infinite-scroll endpoint always answers with JSON carrying an
// results_html blob. Anything else means we did not reach Steam.
function parseSearchPayload(raw) {
  var text = String(raw || "").trim()
  if (!text || text.length > MAX_BYTES) return null
  try {
    var data = JSON.parse(text)
    if (!data || typeof data !== "object" || Array.isArray(data)) return null
    return parseSearchRows(String(data.results_html || ""))
  } catch (e) {
    return null
  }
}

function parseSearchRows(html) {
  var games = []
  var seen = {}
  var text = String(html || "")
  var index = 0

  while (games.length < MAX_ROWS) {
    var start = text.indexOf("<a", index)
    if (start < 0) break
    var tagEnd = text.indexOf(">", start)
    if (tagEnd < 0) break
    var openTag = text.slice(start, tagEnd + 1)
    if (openTag.indexOf("search_result_row") < 0) {
      index = start + 2
      continue
    }
    var close = text.indexOf("</a>", tagEnd)
    if (close < 0) break
    var game = parseSearchRow(text.slice(start, close))
    index = close + 4
    if (!game || seen[game.id]) continue
    seen[game.id] = true
    games.push(game)
  }

  return games
}

function parseSearchRow(block) {
  var id = firstId(matchAttr(block, "data-ds-appid"))
    || firstId(matchAttr(block, "data-ds-bundleid"))
    || firstId(matchAttr(block, "data-ds-packageid"))
  if (!id) return null

  return {
    id: id,
    title: matchTitle(block) || "Steam " + id,
    url: cleanStoreUrl(decodeHtml(matchAttr(block, "href"))) || SEARCH_URL
  }
}

function firstId(value) {
  var match = String(value || "").match(/\d{1,10}/)
  return match ? match[0] : ""
}

function matchAttr(text, name) {
  var match = String(text || "").match(
    new RegExp(name + '\\s*=\\s*["\']([^"\']*)["\']', "i"))
  return match ? match[1] : ""
}

// The notification server advertises body-markup and body-hyperlinks, and
// decodeHtml turns "&lt;b&gt;" back into a live tag, so angle brackets and
// control characters are stripped here — the one place every sink reads from.
function matchTitle(text) {
  var block = String(text || "").slice(0, MAX_BLOCK)
  var match = block.match(/<span[^>]*class="[^"]*\btitle\b[^"]*"[^>]*>([\s\S]*?)<\/span>/i)
  if (!match) return ""
  return decodeHtml(match[1].replace(/<[^>]+>/g, ""))
    .replace(/[<>]/g, "")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, " ")
    .replace(/\s+/g, " ").trim().slice(0, MAX_TITLE)
}

function decodeHtml(value) {
  return String(value || "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, "\"")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, function(_, code) {
      return String.fromCharCode(Number(code))
    })
}

// Returns "" for anything that is not a canonical https Steam store URL, so
// callers fall back to SEARCH_URL rather than launching what Steam sent.
function cleanStoreUrl(href) {
  var url = String(href || "").trim().split("?")[0].split("#")[0]
  return STORE_URL_RE.test(url) ? url : ""
}

function parseSeen(raw) {
  var text = String(raw || "").trim()
  if (!text || text.length > MAX_SEEN_BYTES) return emptyWatchState()
  try {
    var data = JSON.parse(text)
    if (!data || typeof data !== "object" || Array.isArray(data))
      return emptyWatchState()
    var ids = {}
    var n = 0
    var list = Array.isArray(data.ids) ? data.ids : []
    for (var i = 0; i < list.length && n < MAX_SEEN_IDS; i++) {
      var id = String(list[i] || "")
      if (!SEEN_ID_RE.test(id) || ids[id]) continue
      ids[id] = true
      n++
    }
    return {
      primed: data.primed === true || n > 0,
      ids: ids
    }
  } catch (e) {
    return emptyWatchState()
  }
}

function serializeSeen(state) {
  var ids = []
  var source = state && state.ids ? state.ids : {}
  for (var id in source) {
    if (!source[id] || !SEEN_ID_RE.test(id)) continue
    ids.push(id)
    if (ids.length >= MAX_SEEN_IDS) break
  }
  ids.sort()
  return JSON.stringify({ primed: !!(state && state.primed), ids: ids })
}

function transitionAlerts(state, games, notifyEnabled) {
  var current = state && typeof state === "object" ? state : emptyWatchState()
  var nextIds = {}
  var list = Array.isArray(games) ? games : []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id) nextIds[String(list[i].id)] = true
  }

  var alerts = []
  if (current.primed && notifyEnabled) {
    for (var j = 0; j < list.length; j++) {
      var game = list[j]
      if (game && game.id && !current.ids[String(game.id)])
        alerts.push(game)
    }
  }

  return {
    state: { primed: true, ids: nextIds },
    alerts: alerts
  }
}

function notificationFor(alerts, country) {
  if (!alerts || alerts.length === 0) return null
  if (alerts.length === 1) {
    return {
      title: alerts[0].title + " is free on Steam",
      body: "Open the store page to claim it",
      url: alerts[0].url || searchUrl(country)
    }
  }

  var names = []
  for (var i = 0; i < alerts.length && i < 4; i++)
    names.push(alerts[i].title)
  var extra = alerts.length - names.length
  var body = names.join(", ")
  if (extra > 0) body += " and " + extra + " more"
  return {
    title: alerts.length + " free games on Steam",
    body: body,
    url: searchUrl(country)
  }
}

// The headline sits in omarchy-notification-send's option position, which is
// parsed before the positional is captured, so a title that is exactly a known
// flag would be eaten as one. Leading dashes never survive into that slot.
function notificationArgs(alert) {
  if (!alert) return null
  var headline = String(alert.title || "").replace(/^-+/, "").trim()
  return [
    "omarchy-notification-send",
    "--app-name", "Steam Sniper",
    "-g", BAR_ICON,
    "-u", "normal",
    "-t", "12000",
    headline || "Free game on Steam",
    String(alert.body || ""),
    "--exec", "omarchy-launch-browser", String(alert.url || SEARCH_URL)
  ]
}

function statusTitle(games, busy, error) {
  if (busy && (!games || games.length === 0)) return "Checking Steam"
  if (error && (!games || games.length === 0)) return "Could not reach Steam"
  var count = games ? games.length : 0
  if (count === 0) return "No free games"
  if (count === 1) return "1 free game"
  return count + " free games"
}

function statusDetail(games, busy, error, freshness) {
  if (busy && (!games || games.length === 0)) return "Looking for 100% off Steam games"
  if (error && (!games || games.length === 0)) return String(error)
  if (!games || games.length === 0) return "I will notify you when a game is free"
  return freshness || ""
}

function tooltipText(games, busy, error, freshness) {
  var title = statusTitle(games, busy, error)
  if (error && games && games.length > 0) return title + "\n" + error
  if (freshness) return title + "\n" + freshness
  return title
}

function freshnessLabel(lastSuccessAt, nowMs, loading, error) {
  if (!lastSuccessAt)
    return loading ? "Checking Steam" : (error ? "Unavailable" : "Not checked yet")
  var age = Math.max(0, Number(nowMs) - lastSuccessAt)
  if (!isFinite(age)) age = 0
  if (age >= STALE_AFTER_MS) return "Stale · " + ageLabel(age)
  if (age < 15000) return "Updated just now"
  return "Updated " + ageLabel(age) + " ago"
}

function ageLabel(ms) {
  var seconds = Math.max(0, Math.floor(Number(ms) / 1000))
  if (seconds < 60) return seconds + "s"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  return Math.floor(hours / 24) + "d"
}
