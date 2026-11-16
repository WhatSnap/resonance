import Testing
@testable import ResonanceCore

/// Stands in for `SMAppService.mainApp`. Tests never call the real service.
final class FakeLoginItem: LoginItem {
    var isRegistered = false
    var registerCalls = 0
    var unregisterCalls = 0
    var failNext: Error?

    func register() throws {
        registerCalls += 1
        if let error = failNext { failNext = nil; throw error }
        isRegistered = true
    }

    func unregister() throws {
        unregisterCalls += 1
        if let error = failNext { failNext = nil; throw error }
        isRegistered = false
    }
}

struct LoginFailure: Error {}

@Suite("OpenAtLogin")
struct OpenAtLoginTests {
    @Test("Off on a fresh install, and creating it registers nothing")
    func offByDefault() {
        let item = FakeLoginItem()
        let toggle = OpenAtLogin(item: item)
        #expect(toggle.isOn == false)
        #expect(item.registerCalls == 0)
        #expect(item.unregisterCalls == 0)
    }

    @Test("Turning it on registers the app")
    func onRegisters() throws {
        let item = FakeLoginItem()
        let toggle = OpenAtLogin(item: item)
        try toggle.set(true)
        #expect(item.registerCalls == 1)
        #expect(toggle.isOn == true)
    }

    @Test("Turning it off unregisters the app")
    func offUnregisters() throws {
        let item = FakeLoginItem()
        let toggle = OpenAtLogin(item: item)
        try toggle.set(true)
        try toggle.set(false)
        #expect(item.unregisterCalls == 1)
        #expect(toggle.isOn == false)
    }

    @Test("Setting the state it already has does nothing")
    func idempotent() throws {
        let item = FakeLoginItem()
        let toggle = OpenAtLogin(item: item)
        try toggle.set(false)
        #expect(item.unregisterCalls == 0)
        try toggle.set(true)
        try toggle.set(true)
        #expect(item.registerCalls == 1)
    }

    @Test("The state reflects the system, so a removal in System Settings shows as off")
    func followsSystem() throws {
        let item = FakeLoginItem()
        let toggle = OpenAtLogin(item: item)
        try toggle.set(true)
        item.isRegistered = false
        #expect(toggle.isOn == false)
    }

    @Test("A failed register throws and leaves it off")
    func failureLeavesOff() {
        let item = FakeLoginItem()
        item.failNext = LoginFailure()
        let toggle = OpenAtLogin(item: item)
        #expect(throws: LoginFailure.self) { try toggle.set(true) }
        #expect(toggle.isOn == false)
    }
}
