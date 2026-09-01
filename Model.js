.pragma library

var FILTERS = "sort_by=_ASC&hwtype=0&maxprice=free&category1=998&supportedlang=english&specials=1"
var SEARCH_URL = "https://store.steampowered.com/search/?" + FILTERS
var RESULTS_URL = "https://store.steampowered.com/search/results/?" + FILTERS + "&query=&start=0&count=50&infinite=1&l=english"
var USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
var STALE_AFTER_MS = 45 * 60 * 1000
var BAR_ICON = "\u{F1B6}"

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
    "curl", "-fsS", "--compressed", "--max-time", "20",
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
  if (!text) return null
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

  while (true) {
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
  var match = String(value || "").match(/\d+/)
  return match ? match[0] : ""
}

function matchAttr(text, name) {
  var match = String(text || "").match(
    new RegExp(name + '\\s*=\\s*["\']([^"\']*)["\']', "i"))
  return match ? match[1] : ""
}

function matchTitle(text) {
  var match = String(text || "").match(/<span[^>]*class="[^"]*\btitle\b[^"]*"[^>]*>([\s\S]*?)<\/span>/i)
  if (!match) return ""
  return decodeHtml(match[1].replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim()
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

function cleanStoreUrl(href) {
  var url = String(href || "").trim()
  if (!url) return ""
  var query = url.indexOf("?")
  if (query >= 0) url = url.slice(0, query)
  return url
}

function parseSeen(raw) {
  var text = String(raw || "").trim()
  if (!text) return emptyWatchState()
  try {
    var data = JSON.parse(text)
    if (!data || typeof data !== "object" || Array.isArray(data))
      return emptyWatchState()
    var ids = {}
    var list = Array.isArray(data.ids) ? data.ids : []
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i] || "")
      if (id) ids[id] = true
    }
    return {
      primed: data.primed === true || list.length > 0,
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
    if (source[id]) ids.push(String(id))
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

function notificationArgs(alert) {
  if (!alert) return null
  return [
    "omarchy-notification-send",
    "--app-name", "Steam Sniper",
    "-g", BAR_ICON,
    "-u", "normal",
    "-t", "12000",
    String(alert.title || "Free game on Steam"),
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
