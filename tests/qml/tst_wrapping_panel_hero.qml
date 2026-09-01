import QtQuick
import QtTest
import "../.." as SteamSniper

Item {
  width: 260
  height: 160

  SteamSniper.WrappingPanelHero {
    id: hero
    width: 240
    title: "No free games"
    meta: "I will notify you when a game is free"

    iconComponent: Component {
      Item {
        implicitWidth: 24
        implicitHeight: 24
      }
    }
  }

  TestCase {
    name: "SteamSniperWrappingPanelHero"
    when: windowShown

    function test_long_meta_wraps_without_truncation() {
      tryVerify(function() { return hero.metaLineCount > 1 })
      compare(hero.metaTruncated, false)
    }
  }
}
