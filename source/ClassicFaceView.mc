import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// "Classic" — an engineer's-watch style analogue face:
// woven grid-textured dial, steel batons
// with lume inlays, day-date window at 3, plus digital time, weather,
// heart rate and steps.
class ClassicFaceView extends WatchUi.WatchFace {

    // ---- dial themes --------------------------------------------------------
    // [unused, shadow, flange, text, muted text, hand/marker steel, window]
    const THEMES = [
        [0x000000, 0x050506, 0x1A1C1F, 0xE8EAEC, 0x8C9096, 0xC9CDD2, 0x111214], // black
        [0x000000, 0x04080F, 0x173659, 0xEEF1F4, 0x9DB3CC, 0xC9CDD2, 0x0F2C52], // blue
        [0x000000, 0x030B0A, 0x1E4E4A, 0xEEF2F1, 0xA9C9C6, 0xD3D7DB, 0x123A37], // aqua
        [0x000000, 0x5E6368, 0xB9BCC0, 0x16181B, 0x33363B, 0x41454A, 0xE4E6E8]  // silver
    ];
    // texture: [groove, bar dark, bar light, edge-highlight dark, edge-highlight light]
    const TEXTURES = [
        [0x060607, 0x17191C, 0x45494F, 0x3C4045, 0x9AA0A6],
        [0x04070D, 0x0B3A68, 0x4C88BA, 0x4A7FAE, 0xB8D4EC],
        [0x040C0B, 0x0F3A37, 0x3E8A84, 0x2F6D68, 0xA6DAD4],
        [0x9A9EA3, 0xC0C3C7, 0xE2E4E6, 0xD4D7DA, 0xF8F9FA]
    ];
    // dial shadow: 1.0 = no shadow, lower = darker dial
    const DIAL_SHADE = 0.70;
    // extra darkening towards the rim (0 = none, 1 = black at the edge)
    const RIM_SHADOW = 0.45;
    const LUME      = 0xE6EEDF;
    const STEEL_HI  = 0xE3E6E9;
    const STEEL_MID = 0xAEB2B8;
    const STEEL_LO  = 0x5A5E64;

    // icon font glyphs
    const IC_HEART = "A";
    const IC_STEPS = "B";
    const IC_SUN = "C";
    const IC_PARTLY = "D";
    const IC_CLOUD = "E";
    const IC_RAIN = "F";
    const IC_THUNDER = "G";
    const IC_SNOW = "H";
    const IC_FOG = "I";

    // weather condition groups (Toybox.Weather.CONDITION_* values)
    const WX_SUN     = [0, 23, 40];
    const WX_PARTLY  = [1, 22, 52];
    const WX_RAIN    = [3, 11, 13, 14, 15, 24, 25, 26, 27, 31, 45, 49];
    const WX_THUNDER = [6, 12, 28, 32, 41, 42];
    const WX_SNOW    = [4, 7, 10, 16, 17, 18, 19, 21, 34, 43, 44, 46, 47, 48, 50, 51];
    const WX_FOG     = [8, 9, 29, 30, 33, 35, 37, 38, 39];

    var _w = 0;
    var _h = 0;
    var _cx = 0;
    var _cy = 0;
    var _r = 0;
    var _isAwake = true;
    var _burnIn = false;
    var _theme = 1;
    var _showSeconds = true;
    var _icons = null;
    var _iconsSmall = null;
    var _winFont = Graphics.FONT_XTINY;
    var _rowFont = Graphics.FONT_TINY;
    // window geometry (fixed, so the frames can live in the static layer)
    var _winH = 0;
    var _dateX = 0;
    var _dateW = 0;
    var _wxX = 0;
    var _wxW = 0;
    var _bgRef = null;   // cached static layer (dial, markers)
    var _bg = null;

    function initialize() {
        WatchFace.initialize();
        var ds = System.getDeviceSettings();
        if (ds has :requiresBurnInProtection) {
            _burnIn = ds.requiresBurnInProtection;
        }
        loadSettings();
    }

    function onLayout(dc) {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        // Layout is in units of _r. The minute-track flange ends at 0.885 _r,
        // so scale it to touch the screen edge (no bezel ring).
        _r = ((_cx < _cy) ? _cx : _cy) / 0.885;
        _icons = WatchUi.loadResource(Rez.Fonts.Icons);
        _iconsSmall = WatchUi.loadResource(Rez.Fonts.IconsSmall);
        // small condensed face for the windows; falls back to the system font
        if (Graphics has :getVectorFont) {
            var vf = Graphics.getVectorFont({
                :face => ["RobotoCondensedBold", "RobotoCondensedRegular", "RobotoRegular"],
                :size => (_r * 0.085).toNumber()
            });
            if (vf != null) { _winFont = vf; }
            var rf = Graphics.getVectorFont({
                :face => ["RobotoCondensedRegular", "RobotoCondensedBold", "RobotoRegular"],
                :size => (_r * 0.105).toNumber()
            });
            if (rf != null) { _rowFont = rf; }
        }

        _winH = Math.round(_r * 0.13).toNumber();
        var pad = _r * 0.035;
        var dw = 0;
        var samples = ["WED 28", "MON 28", "THU 28", "SAT 28"];
        for (var i = 0; i < samples.size(); i++) {
            var tw = dc.getTextWidthInPixels(samples[i], _winFont);
            if (tw > dw) { dw = tw; }
        }
        _dateW = Math.round(dw + pad * 2).toNumber();
        _wxW = Math.round(pad * 2 + dc.getTextWidthInPixels("E", _iconsSmall) + _r * 0.018
                          + dc.getTextWidthInPixels("-88°", _winFont)).toNumber();
        _dateX = Math.round(_cx + _r * 0.63 - _dateW).toNumber();
        _wxX = Math.round(_cx - _r * 0.63).toNumber();
    }

    function onShow() {
        loadSettings();
    }

    function onEnterSleep() {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    function loadSettings() {
        var old = _theme;
        try {
            var idx = Application.Properties.getValue("DialColor");
            if (idx != null && idx >= 0 && idx < THEMES.size()) {
                _theme = idx;
            }
            var sec = Application.Properties.getValue("ShowSeconds");
            if (sec != null) {
                _showSeconds = sec;
            }
        } catch (e) {
            // keep defaults
        }
        var demoDial = demoTheme();
        if (demoDial != null) { _theme = demoDial; }
        if (old != _theme) {
            _bg = null;
            _bgRef = null;
        }
    }

    function c(i) {
        return THEMES[_theme][i];
    }

    // ========================================================================
    function onUpdate(dc) {
        var clock = demoClock(System.getClockTime());

        if (!_isAwake && _burnIn) {
            if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
            drawAlwaysOn(dc, clock);
            return;
        }

        var bg = getStaticLayer();
        if (bg != null) {
            dc.drawBitmap(0, 0, bg);
        } else {
            if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
            drawStatic(dc);
        }
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        drawDigital(dc, clock);
        drawDateWindow(dc);
        drawWeather(dc);
        drawHealthRow(dc, _cy + _r * 0.40);
        drawHands(dc, clock, _isAwake && _showSeconds);
    }

    // Render the dial into an off-screen bitmap once; redraws only need a blit.
    function getStaticLayer() {
        if (_bg != null) { return _bg; }
        try {
            var opts = { :width => _w, :height => _h };
            if (Graphics has :createBufferedBitmap) {
                _bgRef = Graphics.createBufferedBitmap(opts);
                _bg = _bgRef.get();
            } else {
                _bg = new Graphics.BufferedBitmap(opts);
            }
        } catch (e) {
            _bg = null;
        }
        if (_bg != null) {
            var bdc = _bg.getDc();
            if (bdc has :setAntiAlias) { bdc.setAntiAlias(true); }
            drawStatic(bdc);
        }
        return _bg;
    }

    // ---- static layer ------------------------------------------------------
    function drawStatic(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var R = _r * 0.78;
        drawTexture(dc, R);
        drawFlange(dc, R);
        drawMarkers(dc);
        drawWindowStatic(dc, _dateX, _dateW);
        drawWindowStatic(dc, _wxX, _wxW);
    }

    // Woven "checkerboard" dial: square cells of 4 raised bar-rows; in one
    // cell type each row is a single long bar, in the other it is broken into
    // 3 small squares. Cells alternate like a basket weave. Bars catch the
    // light from the left (bright top edge, darker lower edge).
    //
    // Colours are precomputed into small lookup tables (light level x rim
    // shadow level) so the ~700 bars stay well inside the watchdog limit.
    const NL = 10;   // light levels
    const NE = 4;    // rim-shadow levels

    function drawTexture(dc, R) {
        var tex = TEXTURES[_theme];
        var groove = tex[0];
        dc.setColor(groove, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, _r * 0.885);

        var bodyTab = new [NL * NE];
        var hiTab = new [NL * NE];
        var loTab = new [NE];
        for (var j = 0; j < NE; j++) {
            var e = j / (NE - 1.0);
            var k = DIAL_SHADE * (1.0 - RIM_SHADOW * e * e);
            loTab[j] = lerpColor(groove, tex[1], 0.5 * k);
            for (var i = 0; i < NL; i++) {
                var t = i / (NL - 1.0);
                bodyTab[i * NE + j] = lerpColor(groove, lerpColor(tex[1], tex[2], t), k);
                hiTab[i * NE + j] = lerpColor(groove, lerpColor(tex[3], tex[4], t), k);
            }
        }

        var u = Math.round(R / 40.6).toNumber();   // one lattice unit
        if (u < 2) { u = 2; }
        var bh = u + u / 4;                          // bar height (~60% of pitch)
        var rows = (R / (2 * u)).toNumber() + 1;
        var periods = (R / (16 * u)).toNumber() + 2;
        var starts = [0, 10 * u, 12 * u, 14 * u];   // within a 16u period
        var widths = [9 * u, u, u, u];
        var invR = 1.0 / R;
        var cxl = _cx;

        for (var k = -rows; k <= rows; k++) {
            var y = _cy + k * 2 * u - bh / 2;
            var dy = (y + bh / 2.0 - _cy) * invR;
            if (dy * dy >= 1.0) { continue; }
            var half = Math.sqrt(1.0 - dy * dy) * R;
            var xMin = cxl - half;
            var xMax = cxl + half;
            var off = (((k + 1000) / 4) % 2 == 0) ? 0 : 8 * u;
            var tRow = 0.5 - 0.20 * dy;
            var dy2 = dy * dy;
            for (var m = -periods; m <= periods; m++) {
                var base = cxl + m * 16 * u + off - 4 * u;
                if (base + 16 * u < xMin || base > xMax) { continue; }
                for (var el = 0; el < 4; el++) {
                    var x = base + starts[el];
                    var w = widths[el];
                    if (x + w < xMin || x > xMax) { continue; }
                    var dx = (x + w / 2 - cxl) * invR;
                    var d2 = dx * dx + dy2;
                    var t = (tRow - 0.42 * dx) * (1.0 - 0.30 * d2);
                    var li = (t * (NL - 1) + 0.5).toNumber();
                    if (li < 0) { li = 0; } else if (li >= NL) { li = NL - 1; }
                    var ej = ((d2 - 0.55) * (NE - 1) / 0.45 + 0.5).toNumber();
                    if (ej < 0) { ej = 0; } else if (ej >= NE) { ej = NE - 1; }
                    var idx = li * NE + ej;

                    dc.setColor(bodyTab[idx], -1);
                    dc.fillRectangle(x, y, w, bh);
                    dc.setColor(hiTab[idx], -1);
                    dc.fillRectangle(x, y, w, 1);
                    if (bh >= 3) {
                        dc.setColor(loTab[ej], -1);
                        dc.fillRectangle(x, y + bh - 1, w, 1);
                    }
                }
            }
        }
    }

    function lerpColor(a, b, t) {
        var r = ((a >> 16) & 0xFF) + ((((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t);
        var g = ((a >> 8) & 0xFF) + ((((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t);
        var bl = (a & 0xFF) + (((b & 0xFF) - (a & 0xFF)) * t);
        return (r.toNumber() << 16) | (g.toNumber() << 8) | bl.toNumber();
    }

    // Rehaut ring with the minute track, covering the texture's outer edge
    function drawFlange(dc, R) {
        var outer = _r * 0.885;
        dc.setColor(c(2), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((outer - R).toNumber() + 2);
        dc.drawCircle(_cx, _cy, (outer + R) / 2);
        dc.setPenWidth(2);
        dc.setColor(TEXTURES[_theme][0], Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, R);

        for (var i = 0; i < 60; i++) {
            var a = i * Math.PI / 30.0;
            var major = (i % 5 == 0);
            dc.setColor(major ? c(3) : c(4), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(major ? (_r > 180 ? 3 : 2) : 1);
            var p1 = pt(a, _r * (major ? 0.80 : 0.82), 0);
            var p2 = pt(a, _r * 0.865, 0);
            dc.drawLine(p1[0], p1[1], p2[0], p2[1]);
        }
    }

    // Applied steel batons with lume, double baton at 12, none at 3/9 (windows)
    function drawMarkers(dc) {
        var hw = _r * 0.026;
        for (var h = 1; h < 12; h++) {
            if (h == 3 || h == 9) { continue; }   // windows sit here
            appliedBaton(dc, h * Math.PI / 6.0, _r * 0.60, _r * 0.75, hw, 0);
        }
        appliedBaton(dc, 0, _r * 0.58, _r * 0.75, hw * 0.85, -hw * 1.35);
        appliedBaton(dc, 0, _r * 0.58, _r * 0.75, hw * 0.85, hw * 1.35);
        // short markers just outboard of the windows at 3 and 9
        appliedBaton(dc, Math.PI / 2.0, _r * 0.675, _r * 0.765, hw, 0);
        appliedBaton(dc, 3.0 * Math.PI / 2.0, _r * 0.675, _r * 0.765, hw, 0);
    }

    // Applied marker: faceted steel with a pointed inner end and a lume strip
    function appliedBaton(dc, a, r1, r2, hw, off) {
        var tip = hw * 1.3;
        var outline = [pt(a, r1, off), pt(a, r1 + tip, off - hw), pt(a, r2, off - hw),
                       pt(a, r2, off + hw), pt(a, r1 + tip, off + hw)];
        dc.setColor(c(1), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(shifted(outline, _r * 0.008));

        var lit = 0.6 * Math.cos(a) + 0.8 * Math.sin(a);
        dc.setColor(lerpColor(STEEL_DK, STEEL_HI, 0.5 + 0.5 * lit), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(a, r1, off), pt(a, r1 + tip, off - hw), pt(a, r2, off - hw), pt(a, r2, off)]);
        dc.setColor(lerpColor(STEEL_DK, STEEL_HI, 0.5 - 0.5 * lit), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(a, r1, off), pt(a, r2, off), pt(a, r2, off + hw), pt(a, r1 + tip, off + hw)]);

        var lw = hw * 0.45;
        var cw = hw * 0.62;
        dc.setColor(LUME_CHAN, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(a, r1 + tip * 0.55, off), pt(a, r1 + tip + hw * 0.1, off - cw),
                        pt(a, r2 - hw * 0.25, off - cw), pt(a, r2 - hw * 0.25, off + cw),
                        pt(a, r1 + tip + hw * 0.1, off + cw)]);
        dc.setColor(LUME, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pt(a, r1 + tip * 0.85, off), pt(a, r1 + tip + hw * 0.3, off - lw),
                        pt(a, r2 - hw * 0.4, off - lw), pt(a, r2 - hw * 0.4, off + lw),
                        pt(a, r1 + tip + hw * 0.3, off + lw)]);
    }

    // ---- digital time ------------------------------------------------------
    function drawDigital(dc, clock) {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var time = hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(c(3), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - _r * 0.36, Graphics.FONT_SMALL, time,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Day-date window at 3 o'clock with a steel frame
    function drawDateWindow(dc) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var text = info.day_of_week.toUpper() + " " + info.day.format("%d");
        dc.setColor(c(3), Graphics.COLOR_TRANSPARENT);
        dc.drawText(_dateX + _dateW / 2, _cy, _winFont, text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Weather in the window at 9 o'clock
    function drawWeather(dc) {
        var text = "--";
        var glyph = IC_CLOUD;
        var cc = null;
        if (Toybox has :Weather) {
            cc = Weather.getCurrentConditions();
        }
        if (cc != null) {
            glyph = weatherGlyph(cc.condition);
            var t = cc.temperature;
            if (t != null) {
                if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                    t = t * 9.0 / 5.0 + 32;
                }
                text = Math.round(t).toNumber().format("%d") + "°";
            }
        }
        var demo = demoData();
        if (demo != null) {
            glyph = weatherGlyph(demo[2]);
            text = demo[3].format("%d") + "°";
        }
        var iw = dc.getTextWidthInPixels(glyph, _iconsSmall);
        var gap = _r * 0.018;
        var x0 = _wxX + (_wxW - (iw + gap + dc.getTextWidthInPixels(text, _winFont))) / 2;
        dc.setColor(c(4), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, _cy, _iconsSmall, glyph, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(c(3), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + iw + gap, _cy, _winFont, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Recessed window with an applied, polished steel frame (static layer):
    //   dark cut-out in the dial around the frame (frame looks raised),
    //   bright polished frame face with a darker bevel sloping inwards,
    //   recessed disc with an inner shadow along the top and left edges.
    function drawWindowStatic(dc, x, w) {
        var h = _winH;
        var y = Math.round(_cy - h / 2.0).toNumber();
        var f = Math.round(_r * 0.022).toNumber();
        if (f < 3) { f = 3; }
        var m = Math.round(_r * 0.012).toNumber();
        if (m < 2) { m = 2; }
        var rad = f + 1;

        // cut-out in the dial + cast shadow towards lower right
        dc.setColor(TEXTURES[_theme][0], Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - f - m, y - f - m, w + 2 * (f + m), h + 2 * (f + m), rad + m);
        dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - f + 1, y - f + 2, w + 2 * f + 1, h + 2 * f + 1, rad);

        // polished frame: dark rim, bright face, inner bevel
        dc.setColor(0x6E7278, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - f, y - f, w + 2 * f, h + 2 * f, rad);
        dc.setColor(0xEEF0F2, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - f + 1, y - f + 1, w + 2 * f - 2, h + 2 * f - 2, rad - 1);
        var b = f / 2;
        if (b < 1) { b = 1; }
        dc.setColor(0xB4B8BE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - b, y - b, w + 2 * b, h + 2 * b, b);
        dc.setColor(0x9A9EA4, Graphics.COLOR_TRANSPARENT);   // bevel in shade (top)
        dc.fillRectangle(x - b + 1, y - b, w + 2 * b - 2, b);

        // aperture edge + recessed disc
        dc.setColor(0x15181C, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 1, y - 1, w + 2, h + 2);
        var disc = c(6);
        dc.setColor(disc, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y, w, h);

        // inner shadow: left edge, then the deeper top edge
        var sl = Math.round(h * 0.14).toNumber();
        if (sl < 1) { sl = 1; }
        for (var i = 0; i < sl; i++) {
            var t = (i + 1.0) / (sl + 1);
            dc.setColor(lerpColor(0x000000, disc, 0.30 + 0.70 * t), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + i, y, 1, h);
        }
        var st = Math.round(h * 0.30).toNumber();
        if (st < 2) { st = 2; }
        for (var j = 0; j < st; j++) {
            var u = (j + 1.0) / (st + 1);
            dc.setColor(lerpColor(0x000000, disc, 0.15 + 0.85 * u * u), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, y + j, w, 1);
        }
        // faint light catching the lower lip
        dc.setColor(lerpColor(disc, 0xFFFFFF, 0.10), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y + h - 1, w, 1);
    }

    // ---- complications -----------------------------------------------------
    function drawHealthRow(dc, y) {
        var hr = null;
        var act = Activity.getActivityInfo();
        if (act != null && act.currentHeartRate != null) {
            hr = act.currentHeartRate;
        } else if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            var s = (it != null) ? it.next() : null;
            if (s != null && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = s.heartRate;
            }
        }
        var steps = null;
        var info = ActivityMonitor.getInfo();
        if (info != null) { steps = info.steps; }
        var demo = demoData();
        if (demo != null) {
            hr = demo[0];
            steps = demo[1];
        }

        drawIconValue(dc, _cx - _r * 0.25, y, IC_HEART, hr == null ? "--" : hr.format("%d"));
        drawIconValue(dc, _cx + _r * 0.25, y, IC_STEPS, steps == null ? "--" : groupThousands(steps));
    }

    // icon + value, centred as a group on (cx, y)
    function drawIconValue(dc, cx, y, glyph, text) {
        var font = _rowFont;
        var iw = dc.getTextWidthInPixels(glyph, _icons);
        var tw = dc.getTextWidthInPixels(text, font);
        var gap = _r * 0.045;
        var x0 = cx - (iw + gap + tw) / 2;
        dc.setColor(c(4), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, y, _icons, glyph, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(c(3), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + iw + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function weatherGlyph(cond) {
        if (cond == null) { return IC_CLOUD; }
        if (contains(WX_SUN, cond)) { return IC_SUN; }
        if (contains(WX_PARTLY, cond)) { return IC_PARTLY; }
        if (contains(WX_RAIN, cond)) { return IC_RAIN; }
        if (contains(WX_THUNDER, cond)) { return IC_THUNDER; }
        if (contains(WX_SNOW, cond)) { return IC_SNOW; }
        if (contains(WX_FOG, cond)) { return IC_FOG; }
        return IC_CLOUD;
    }

    // ---- hands -------------------------------------------------------------
    // Hand geometry in units of _r:
    //   [length, half-width, neck half-width, shoulder start, shoulder end, tip length]
    const HOUR_HAND   = [0.50, 0.040, 0.012, 0.10, 0.15, 0.065];
    const MINUTE_HAND = [0.78, 0.032, 0.010, 0.10, 0.15, 0.058];
    const STEEL_DK    = 0x7C8086;
    const LUME_CHAN   = 0x464A50;

    function drawHands(dc, clock, withSeconds) {
        var hourA = ((clock.hour % 12) * 60 + clock.min) * Math.PI / 360.0;
        var minA  = (clock.min * 60 + clock.sec) * Math.PI / 1800.0;

        // soft drop shadows first, so neither hand shadows the other's body
        var sh = c(1);
        dc.setColor(sh, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(shifted(handOutline(hourA, HOUR_HAND), _r * 0.012));
        dc.fillPolygon(shifted(handOutline(minA, MINUTE_HAND), _r * 0.016));

        steelHand(dc, hourA, HOUR_HAND);
        steelHand(dc, minA, MINUTE_HAND);

        // hub: shadow ring, polished collar, domed cap
        dc.setColor(sh, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx + 1, _cy + 2, _r * 0.058);
        dc.setColor(STEEL_DK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, _r * 0.056);
        dc.setColor(STEEL_MID, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, _r * 0.050);
        dc.setColor(STEEL_HI, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx - _r * 0.006, _cy - _r * 0.008, _r * 0.036);

        if (withSeconds) {
            var secA = clock.sec * Math.PI / 30.0;
            var w = _r * 0.0075;
            if (w < 1.2) { w = 1.2; }
            var needle = [pt(secA, -_r * 0.17, -w), pt(secA, _r * 0.86, -w * 0.45),
                          pt(secA, _r * 0.86, w * 0.45), pt(secA, -_r * 0.17, w)];
            dc.setColor(sh, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(shifted(needle, _r * 0.018));
            dc.setColor(c(5), Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(needle);
            dc.fillCircle(_cx, _cy, _r * 0.026);
        }
        dc.setColor(STEEL_LO, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, _r * 0.010);
    }

    // Half of a hand (sgn = -1 left, +1 right of the axis)
    function handHalf(a, h, sgn) {
        var L = h[0] * _r;
        var W = h[1] * _r * sgn;
        var N = h[2] * _r * sgn;
        return [pt(a, -_r * 0.02, 0), pt(a, -_r * 0.02, N), pt(a, h[3] * _r, N),
                pt(a, h[4] * _r, W), pt(a, L - h[5] * _r, W), pt(a, L, 0)];
    }

    function handOutline(a, h) {
        var l = handHalf(a, h, -1);
        var r = handHalf(a, h, 1);
        return [l[1], l[2], l[3], l[4], l[5], r[4], r[3], r[2], r[1]];
    }

    // Faceted polished steel with a lume strip set in a dark channel.
    // The bright facet follows a light source at the upper left.
    function steelHand(dc, a, h) {
        var lit = 0.6 * Math.cos(a) + 0.8 * Math.sin(a);   // left facet vs light
        dc.setColor(lerpColor(STEEL_DK, STEEL_HI, 0.5 + 0.5 * lit), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(handHalf(a, h, -1));
        dc.setColor(lerpColor(STEEL_DK, STEEL_HI, 0.5 - 0.5 * lit), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(handHalf(a, h, 1));

        var L = h[0] * _r;
        var W = h[1] * _r;
        var tip = h[5] * _r;
        var s1 = h[4] * _r;
        var ins = W * 0.5;
        dc.setColor(LUME_CHAN, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(lumeShape(a, s1 + ins * 0.6, L - tip, L - ins * 1.3, W - ins * 0.6));
        dc.setColor(LUME, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(lumeShape(a, s1 + ins, L - tip - ins * 0.2, L - ins * 2.0, W - ins));
    }

    function lumeShape(a, start, shoulder, point, hw) {
        return [pt(a, start, -hw), pt(a, shoulder, -hw), pt(a, point, 0),
                pt(a, shoulder, hw), pt(a, start, hw)];
    }

    function shifted(pts, d) {
        var out = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            out[i] = [pts[i][0] + d * 0.6, pts[i][1] + d];
        }
        return out;
    }

    // ---- always-on (AMOLED low power) -------------------------------------
    function drawAlwaysOn(dc, clock) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var cx0 = _cx;
        var cy0 = _cy;
        _cx += (clock.min % 3 - 1) * 3;
        _cy += ((clock.min / 3) % 3 - 1) * 3;

        dc.setColor(0x6A6E74, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var h = 0; h < 12; h++) {
            var a = h * Math.PI / 6.0;
            if (h == 0) {
                for (var s = -1; s <= 1; s += 2) {
                    var q1 = pt(a, _r * 0.62, s * _r * 0.035);
                    var q2 = pt(a, _r * 0.74, s * _r * 0.035);
                    dc.drawLine(q1[0], q1[1], q2[0], q2[1]);
                }
            } else {
                var p1 = pt(a, _r * 0.64, 0);
                var p2 = pt(a, _r * 0.74, 0);
                dc.drawLine(p1[0], p1[1], p2[0], p2[1]);
            }
        }

        var hourA = ((clock.hour % 12) * 60 + clock.min) * Math.PI / 360.0;
        var minA  = clock.min * Math.PI / 30.0;
        dc.setColor(0xA6AAB0, Graphics.COLOR_TRANSPARENT);
        outlinePoly(dc, handOutline(hourA, HOUR_HAND));
        outlinePoly(dc, handOutline(minA, MINUTE_HAND));
        dc.drawCircle(_cx, _cy, _r * 0.045);

        _cx = cx0;
        _cy = cy0;
    }

    function outlinePoly(dc, pts) {
        for (var i = 0; i < pts.size(); i++) {
            var p = pts[i];
            var q = pts[(i + 1) % pts.size()];
            dc.drawLine(p[0], p[1], q[0], q[1]);
        }
    }

    // ---- screenshot demo mode ---------------------------------------------
    // Normal builds exclude the (:demo) versions (see monkey.jungle). The
    // screenshot build (tools/screenshots.sh) swaps them in for a fixed
    // 10:09 time, sample data and a chosen dial colour.
    (:nodemo) function demoClock(clock) { return clock; }
    (:nodemo) function demoTheme() { return null; }
    (:nodemo) function demoData() { return null; }

    (:demo) function demoClock(clock) {
        clock.hour = 10;
        clock.min = 9;
        clock.sec = 36;
        return clock;
    }
    (:demo) function demoTheme() { return DemoConfig.DIAL; }
    // [heart rate, steps, weather condition, temperature]
    (:demo) function demoData() { return [62, 8432, 1, 12]; }

    // ---- geometry helpers --------------------------------------------------
    // Point at distance `along` from centre in direction `a` (0 = 12 o'clock,
    // clockwise), offset sideways by `perp`.
    function pt(a, along, perp) {
        var s = Math.sin(a);
        var co = Math.cos(a);
        return [round(_cx + along * s + perp * co), round(_cy - along * co + perp * s)];
    }

    function barOffset(a, r1, r2, hw, off) {
        return [pt(a, r1, off - hw), pt(a, r2, off - hw), pt(a, r2, off + hw), pt(a, r1, off + hw)];
    }

    function round(v) {
        return Math.floor(v + 0.5).toNumber();
    }

    function contains(arr, v) {
        for (var i = 0; i < arr.size(); i++) {
            if (arr[i] == v) { return true; }
        }
        return false;
    }

    function groupThousands(n) {
        if (n < 1000) { return n.format("%d"); }
        return (n / 1000).format("%d") + "," + (n % 1000).format("%03d");
    }
}
