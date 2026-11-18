import Foundation

let args = CommandLine.arguments.dropFirst()
if let i = args.firstIndex(of: "--only"), args.index(after: i) < args.endIndex {
    Runner.filter = args[args.index(after: i)]
}

settingsChecks()
habitatChecks()
worldChecks()
sharedWorldChecks()
sceneChecks()
policyChecks()
packerChecks()
wallpaperChecks()
renderChecks()
sharedRenderChecks()

print("\(Runner.passed) passed, \(Runner.failed) failed")
exit(Runner.failed == 0 ? 0 : 1)
