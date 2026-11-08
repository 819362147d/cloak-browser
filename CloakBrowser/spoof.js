// CloakBrowser injection — runs at document start, before any page script.
// Profile: UK (user's choice, 2026-11-08). NOTE: the exit IP is still the
// FR VPS, so IP geolocation and this profile disagree — fine for the
// ip.cx score, weaker against consistency checks. See README.
//   timeZone : Europe/London
//   language : en-GB (languages: en-GB, en)
//   locale   : en-GB
// Targets the signals shown on the ip.cx "Claude detection" page:
//   1. Intl.DateTimeFormat resolved timeZone   (+24)
//   2. navigator.language / languages          (+18)
//   3. Installed Chinese fonts via canvas      (+12)
//   4. Intl locale                             (+4)
//   5. Date.getTimezoneOffset == UTC+8         (+2)
//   6. WebRTC IP leak                          (+10 if leaked; Safari is
//      already clean, this is a belt-and-braces block)
// NOT covered (cannot be faked convincingly from JS): Date.toString()'s
// zone name, DOM layout-based font probing (offsetWidth on real text),
// server-side signals (IP ASN, account history). See README.
(function () {
  'use strict';
  var TZ = 'Europe/London';
  var LANG = 'en-GB';
  var LANGS = ['en-GB', 'en'];

  // ---- fonts to pretend are NOT installed ----
  var BLOCKED_FONTS = [
    'pingfang sc', 'pingfang tc', 'pingfang hk', 'pingfang mo',
    'microsoft yahei', 'microsoft jhenghei', 'simsun', 'simhei',
    'nsimsun', 'fangsong', 'kaiti', 'source han sans', 'source han serif',
    'noto sans cjk', 'noto serif cjk', 'misans', 'harmonyos sans',
    'oppo sans', 'vivo sans', 'honor sans', 'wps'
  ];
  function fontIsBlocked(fontStr) {
    var f = ('' + fontStr).toLowerCase();
    for (var i = 0; i < BLOCKED_FONTS.length; i++) {
      if (f.indexOf(BLOCKED_FONTS[i]) !== -1) return true;
    }
    return false;
  }
  // Strip blocked families out of a CSS font string, keep size/style prefix
  // and generic fallbacks. e.g. '72px "PingFang SC", monospace' -> '72px monospace'
  function stripBlocked(fontStr) {
    var m = ('' + fontStr).match(/^([^a-zA-Z"']*)(.*)$/);
    var prefix = m ? m[1] : '';
    var rest = m ? m[2] : '' + fontStr;
    var parts = rest.split(',');
    var kept = [];
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].trim().replace(/^["']|["']$/g, '');
      if (p && !fontIsBlocked(p)) kept.push(p);
    }
    if (!kept.length) kept.push('sans-serif');
    return prefix + kept.join(', ');
  }

  // ---- 2. navigator.language / languages ----
  try {
    Object.defineProperty(Navigator.prototype, 'language', {
      get: function () { return LANG; }, configurable: true
    });
    Object.defineProperty(Navigator.prototype, 'languages', {
      get: function () { return Object.freeze(LANGS.slice()); }, configurable: true
    });
  } catch (e) {}

  // ---- helpers: real London offset for a given instant ----
  var OrigDTF = Intl.DateTimeFormat;
  function londonOffsetMinutes(date) {
    try {
      var dtf = new OrigDTF('en-US', {
        timeZone: TZ, hourCycle: 'h23',
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit'
      });
      var parts = {};
      dtf.formatToParts(date).forEach(function (p) { parts[p.type] = p.value; });
      var asUTC = Date.UTC(+parts.year, +parts.month - 1, +parts.day,
        +parts.hour, +parts.minute, +parts.second);
      // getTimezoneOffset() sign convention: UTC+1 (London summer, BST) -> -60;
      // London winter (GMT) -> 0
      return -Math.round((asUTC - Math.floor(date.getTime() / 1000) * 1000) / 60000);
    } catch (e) { return -60; }
  }

  // ---- 1 & 4. Intl.DateTimeFormat: force timeZone + locale ----
  try {
    var origResolved = OrigDTF.prototype.resolvedOptions;
    OrigDTF.prototype.resolvedOptions = function () {
      var o = origResolved.call(this);
      o.timeZone = TZ;
      o.locale = LANG;
      return o;
    };
    // Also wrap the constructor so `new Intl.DateTimeFormat()` (no explicit
    // zone) actually formats with Paris time, not just reports it.
    var DTFProxy = function (locales, options) {
      var opts = options ? Object.assign({}, options) : {};
      if (!opts.timeZone) opts.timeZone = TZ;
      return new OrigDTF(locales || LANG, opts);
    };
    DTFProxy.prototype = OrigDTF.prototype;
    DTFProxy.supportedLocalesOf = OrigDTF.supportedLocalesOf.bind(OrigDTF);
    Intl.DateTimeFormat = DTFProxy;
  } catch (e) {}

  // ---- 5. Date.getTimezoneOffset ----
  try {
    Date.prototype.getTimezoneOffset = function () {
      return londonOffsetMinutes(this);
    };
  } catch (e) {}

  // ---- 3. Canvas font probing: blocked fonts measure as generic fallback ----
  try {
    var proto = CanvasRenderingContext2D.prototype;
    var origMeasure = proto.measureText;
    proto.measureText = function (text) {
      if (fontIsBlocked(this.font)) {
        var saved = this.font;
        this.font = stripBlocked(saved);
        try { return origMeasure.call(this, text); }
        finally { this.font = saved; }
      }
      return origMeasure.call(this, text);
    };
  } catch (e) {}
  try {
    if (window.OffscreenCanvasRenderingContext2D) {
      var oproto = OffscreenCanvasRenderingContext2D.prototype;
      var oMeasure = oproto.measureText;
      oproto.measureText = function (text) {
        if (fontIsBlocked(this.font)) {
          var saved = this.font;
          this.font = stripBlocked(saved);
          try { return oMeasure.call(this, text); }
          finally { this.font = saved; }
        }
        return oMeasure.call(this, text);
      };
    }
  } catch (e) {}
  try {
    if (document.fonts && document.fonts.check) {
      var origCheck = document.fonts.check.bind(document.fonts);
      document.fonts.check = function (font, text) {
        if (fontIsBlocked(font)) return false;
        return origCheck(font, text);
      };
    }
  } catch (e) {}

  // ---- 6. WebRTC: refuse to gather candidates ----
  try {
    var blockedPC = function () { throw new Error('WebRTC disabled'); };
    window.RTCPeerConnection = blockedPC;
    window.webkitRTCPeerConnection = blockedPC;
  } catch (e) {}
})();
