import Foundation

let args = CommandLine.arguments.dropFirst()
if let i = args.firstIndex(of: "--only"), args.index(after: i) < args.endIndex {
    Runner.filter = args[args.index(after: i)]
}

settingsChecks()
appChecks()
reportChecks()
handoverChecks()
habitatChecks()
worldChecks()
sharedWorldChecks()
sceneChecks()
policyChecks()
packerChecks()
wallpaperChecks()
// CI runners have no GPU: OCEAN_SKIP_GPU=1 skips the Metal checks.
if ProcessInfo.processInfo.environment["OCEAN_SKIP_GPU"] == nil {
    renderChecks()
    sharedRenderChecks()
} else {
    print("SKIP GPU checks (OCEAN_SKIP_GPU)")
}

print("\(Runner.passed) passed, \(Runner.failed) failed")
exit(Runner.failed == 0 ? 0 : 1)
