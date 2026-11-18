import CoreGraphics
import Foundation
import OceanKit

func policyChecks() {
    check("policyDefaultLive60") { try expect(PowerPolicy.mode(PowerInputs()) == .live(fps: 60), "\(PowerPolicy.mode(PowerInputs()))") }
    check("policyBattery30") {
        var i = PowerInputs(); i.onBattery = true
        try expect(PowerPolicy.mode(i) == .live(fps: 30), "\(PowerPolicy.mode(i))")
    }
    check("policyBatteryRespects30Setting") {
        var i = PowerInputs(); i.fpsSetting = 30
        try expect(PowerPolicy.mode(i) == .live(fps: 30), "\(PowerPolicy.mode(i))")
    }
    check("policyLowPowerStill") {
        var i = PowerInputs(); i.lowPowerMode = true
        try expect(PowerPolicy.mode(i) == .still, "\(PowerPolicy.mode(i))")
    }
    check("policyHiddenBeatsEverything") {
        var i = PowerInputs(); i.screenLocked = true; i.userPaused = true; i.reduceMotion = true
        try expect(PowerPolicy.mode(i) == .paused, "\(PowerPolicy.mode(i))")
        for flip in [\PowerInputs.displaysAsleep, \PowerInputs.screensaverRunning] {
            var j = PowerInputs(); j[keyPath: flip] = true
            try expect(PowerPolicy.mode(j) == .paused, "flag did not pause")
        }
        var k = PowerInputs(); k.anyWindowVisible = false
        try expect(PowerPolicy.mode(k) == .paused, "occluded not paused")
        var s = PowerInputs(); s.sessionActive = false
        try expect(PowerPolicy.mode(s) == .paused, "inactive session not paused")
    }
    check("wakeResumes") {
        var i = PowerInputs(); i.screenLocked = true
        try expect(PowerPolicy.mode(i) == .paused, "locked not paused")
        i.screenLocked = false
        try expect(PowerPolicy.mode(i) == .live(fps: 60), "unlock did not resume")
    }
    check("userPauseSurvivesUnlock") {
        var i = PowerInputs(); i.userPaused = true; i.screenLocked = true
        i.screenLocked = false
        try expect(PowerPolicy.mode(i) == .paused, "user pause lost")
    }
    check("policyThermalSerious30") {
        var i = PowerInputs(); i.thermal = .serious
        try expect(PowerPolicy.mode(i) == .live(fps: 30), "\(PowerPolicy.mode(i))")
    }
    check("policyThermalCriticalStill") {
        var i = PowerInputs(); i.thermal = .critical
        try expect(PowerPolicy.mode(i) == .still, "\(PowerPolicy.mode(i))")
    }
    check("policyReduceMotionStill") {
        var i = PowerInputs(); i.reduceMotion = true
        try expect(PowerPolicy.mode(i) == .still, "\(PowerPolicy.mode(i))")
    }
    check("reconcileClearsStaleScreensaver") {
        var i = PowerInputs(); i.screensaverRunning = true; i.screenLocked = true
        let r = PowerPolicy.reconcile(i, session: SessionTruth(screenLocked: false, onConsole: true, screensaverEngineRunning: false))
        try expect(!r.screensaverRunning && !r.screenLocked && r.sessionActive, "\(r)")
        try expect(PowerPolicy.mode(r) == .live(fps: 60), "not live after reconcile")
    }
    check("reconcileUnlocks") {
        var i = PowerInputs(); i.screenLocked = true; i.sessionActive = false
        let r = PowerPolicy.reconcile(i, session: SessionTruth(screenLocked: false, onConsole: true, screensaverEngineRunning: false))
        try expect(!r.screenLocked && r.sessionActive, "\(r)")
    }
    check("reconcileKeepsRealLock") {
        let r = PowerPolicy.reconcile(PowerInputs(), session: SessionTruth(screenLocked: true, onConsole: true, screensaverEngineRunning: true))
        try expect(r.screenLocked && r.screensaverRunning, "\(r)")
    }

    let vps = [Viewport(id: 1, rect: CGRect(x: 0, y: 0, width: 1800, height: 1169)),
               Viewport(id: 2, rect: CGRect(x: 1800, y: 0, width: 2560, height: 1440))]
    check("routerBareDesktop") {
        try expect(PointerRouter.route(CGPoint(x: 100, y: 200), occluders: [], viewports: vps) == PointerTarget(viewportID: 1, local: CGPoint(x: 100, y: 200)), "wrong target")
    }
    check("routerOccluded") {
        try expect(PointerRouter.route(CGPoint(x: 100, y: 200), occluders: [CGRect(x: 50, y: 50, width: 300, height: 300)], viewports: vps) == nil, "occluded point routed")
    }
    check("routerSecondScreen") {
        try expect(PointerRouter.route(CGPoint(x: 1900, y: 30), occluders: [], viewports: vps) == PointerTarget(viewportID: 2, local: CGPoint(x: 100, y: 30)), "wrong local point")
    }
    check("routerGap") {
        try expect(PointerRouter.route(CGPoint(x: 100, y: 1300), occluders: [], viewports: vps) == nil, "gap routed")
    }

    check("clockFirstCallZero") {
        var c = OceanClock()
        try expect(c.advance(to: 100, speed: 1) == 0, "first call stepped")
    }
    check("clockSixtyHz") {
        var c = OceanClock(); _ = c.advance(to: 0, speed: 1)
        var total = 0
        for f in 1...60 { total += c.advance(to: Double(f) / 60, speed: 1) }
        try expect(total == 60, "60 frames gave \(total) steps")
    }
    check("clockThirtyHzTwoSteps") {
        var c = OceanClock(); _ = c.advance(to: 0, speed: 1)
        var total = 0
        for f in 1...30 { total += c.advance(to: Double(f) / 30, speed: 1) }
        try expect(total == 60, "30 frames gave \(total) steps")
    }
    check("clockClampsAfterSleep") {
        var c = OceanClock(); _ = c.advance(to: 0, speed: 1)
        try expect(c.advance(to: 3600, speed: 1) == 4, "sleep jump not clamped to 4")
        try expect(c.advance(to: 3600 + 1.0 / 60, speed: 1) == 1, "not steady after sleep")
    }
    check("clockSpeedHalf") {
        var c = OceanClock(); _ = c.advance(to: 0, speed: 0.5)
        var total = 0
        for f in 1...60 { total += c.advance(to: Double(f) / 60, speed: 0.5) }
        try expect(abs(total - 30) <= 1, "half speed gave \(total)")
    }
    check("flipRoundTrips") {
        let r = CGRect(x: 10, y: 20, width: 300, height: 100)
        let f = ScreenGeometry.flip(r, primaryHeight: 1169)
        try expect(f == CGRect(x: 10, y: 1049, width: 300, height: 100), "flip \(f)")
        try expect(ScreenGeometry.flip(f, primaryHeight: 1169) == r, "not a round trip")
        try expect(ScreenGeometry.flip(CGPoint(x: 5, y: 0), primaryHeight: 1169) == CGPoint(x: 5, y: 1169), "point flip")
    }
}
