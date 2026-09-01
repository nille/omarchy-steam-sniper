import QtQuick
import QtTest
import "../../Model.js" as Model

Item {
  function row(id, title, extraAttrs) {
    return '<a href="https://store.steampowered.com/app/' + id + '/Example/?snr=1_7_7_2300_150_1" '
      + 'data-ds-appid="' + id + '" ' + String(extraAttrs || "")
      + ' class="search_result_row ds_collapse_flag">'
      + '<span class="title">' + title + '</span>'
      + '<div class="discount_final_price free">Free</div></a>'
  }

  function payload(rows, total) {
    return JSON.stringify({
      success: 1,
      results_html: "<!-- List Items -->" + rows + "<!-- End List Items -->",
      total_count: total === undefined ? 1 : total
    })
  }

  TestCase {
    name: "SteamSniperModel"

    function test_urls_keep_the_free_specials_filters() {
      verify(Model.SEARCH_URL.indexOf("maxprice=free") >= 0)
      verify(Model.SEARCH_URL.indexOf("specials=1") >= 0)
      verify(Model.SEARCH_URL.indexOf("category1=998") >= 0)
      verify(Model.RESULTS_URL.indexOf("maxprice=free") >= 0)
      compare(Model.resultsUrl(""), Model.RESULTS_URL)
      compare(Model.searchUrl("us"), Model.SEARCH_URL + "&cc=US")
      compare(Model.normalizeCountry("de"), "DE")
      compare(Model.normalizeCountry("Germany"), "")
    }

    function test_fetch_args_are_safe_argv() {
      var args = Model.fetchArgs("https://store.steampowered.com/search/results/")
      compare(args[0], "curl")
      compare(args[args.length - 1], "https://store.steampowered.com/search/results/")
      verify(args.indexOf("-A") >= 0)
    }

    function test_refresh_minutes_are_clamped() {
      compare(Model.normalizeRefreshMinutes(15), 15)
      compare(Model.normalizeRefreshMinutes(1), 5)
      compare(Model.normalizeRefreshMinutes(999), 180)
      compare(Model.normalizeRefreshMinutes("nope"), 15)
    }

    function test_empty_json_results_are_valid() {
      var parsed = Model.parseSearchPayload(JSON.stringify({
        success: 1,
        results_html: "\n<!-- List Items -->\n<!-- End List Items -->\n",
        total_count: 0,
        start: -1
      }))
      verify(parsed)
      compare(parsed.length, 0)
    }

    function test_invalid_payload_is_not_an_empty_store() {
      compare(Model.parseSearchPayload(""), null)
      compare(Model.parseSearchPayload("{"), null)
      compare(Model.parseSearchPayload("[]"), null)
      compare(Model.parseSearchPayload("<a class=\"search_result_row\"></a>"), null)
    }

    function test_parses_app_title_and_strips_tracking() {
      var parsed = Model.parseSearchPayload(payload(
        row(108600, "Project Zomboid")))
      compare(parsed.length, 1)
      compare(parsed[0].id, "108600")
      compare(parsed[0].title, "Project Zomboid")
      compare(parsed[0].url, "https://store.steampowered.com/app/108600/Example/")
    }

    function test_decodes_entities_and_deduplicates() {
      var parsed = Model.parseSearchPayload(payload(
        row(1, "Hades &amp; II") + row(1, "Hades &amp; II") + row(2, "Celeste"), 2))
      compare(parsed.length, 2)
      compare(parsed[0].title, "Hades & II")
      compare(parsed[1].id, "2")
    }

    function test_parses_bundle_and_package_ids() {
      var parsed = Model.parseSearchPayload(payload(
        '<a href="https://store.steampowered.com/bundle/12/Pack/?snr=x" '
        + 'data-ds-bundleid="12" class="search_result_row">'
        + '<span class="title">Bundle</span></a>'
        + '<a href="https://store.steampowered.com/sub/99/Sub/?snr=x" '
        + 'data-ds-packageid="99" class="search_result_row">'
        + '<span class="title">Package</span></a>', 2))
      compare(parsed[0].id, "12")
      compare(parsed[0].url, "https://store.steampowered.com/bundle/12/Pack/")
      compare(parsed[1].id, "99")
    }

    function test_first_snapshot_never_notifies() {
      var games = Model.parseSearchPayload(payload(row(1, "Hades")))
      var first = Model.transitionAlerts(Model.emptyWatchState(), games, true)
      compare(first.alerts.length, 0)
      verify(first.state.primed)
      verify(first.state.ids["1"])
    }

    function test_new_games_notify_and_gone_games_can_return() {
      var hades = Model.parseSearchPayload(payload(row(1, "Hades")))
      var both = Model.parseSearchPayload(payload(row(1, "Hades") + row(2, "Celeste"), 2))
      var primed = Model.transitionAlerts(Model.emptyWatchState(), hades, true).state

      var appeared = Model.transitionAlerts(primed, both, true)
      compare(appeared.alerts.length, 1)
      compare(appeared.alerts[0].title, "Celeste")

      var empty = Model.transitionAlerts(appeared.state, [], true)
      compare(empty.alerts.length, 0)
      compare(Object.keys(empty.state.ids).length, 0)

      var returned = Model.transitionAlerts(empty.state, hades, true)
      compare(returned.alerts.length, 1)
      compare(returned.alerts[0].id, "1")
    }

    function test_notifications_can_be_disabled() {
      var next = Model.parseSearchPayload(payload(row(2, "Celeste")))
      var primed = { primed: true, ids: {} }
      compare(Model.transitionAlerts(primed, next, false).alerts.length, 0)
    }

    function test_notification_copy_and_click_target() {
      var one = Model.notificationFor([{ title: "Hades", url: "https://store.steampowered.com/app/1/" }])
      compare(one.title, "Hades is free on Steam")
      compare(one.url, "https://store.steampowered.com/app/1/")

      var many = Model.notificationFor([
        { title: "A" }, { title: "B" }, { title: "C" }
      ], "us")
      compare(many.title, "3 free games on Steam")
      compare(many.body, "A, B, C")
      compare(many.url, Model.searchUrl("us"))

      var args = Model.notificationArgs(one)
      compare(args[0], "omarchy-notification-send")
      compare(args[args.length - 2], "omarchy-launch-browser")
      compare(args[args.length - 1], one.url)
    }

    function test_seen_round_trip() {
      var raw = Model.serializeSeen({ primed: true, ids: { "2": true, "1": true } })
      var parsed = Model.parseSeen(raw)
      verify(parsed.primed)
      verify(parsed.ids["1"])
      verify(parsed.ids["2"])
      compare(Model.parseSeen("").primed, false)
      compare(Model.parseSeen("nope").ids["1"], undefined)
    }

    function test_status_and_tooltip() {
      compare(Model.statusTitle([], true, ""), "Checking Steam")
      compare(Model.statusTitle([], false, "timeout"), "Could not reach Steam")
      compare(Model.statusTitle([], false, ""), "No free games")
      compare(Model.statusTitle([{ id: "1" }], false, ""), "1 free game")
      compare(Model.statusTitle([{ id: "1" }, { id: "2" }], false, ""), "2 free games")
      verify(Model.tooltipText([{ id: "1" }], false, "", "Updated just now").indexOf("1 free game") === 0)
    }
  }
}
