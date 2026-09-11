import Foundation
import MousCore

@main
struct MousCoreCheck {
    static func main() async {
        parserChecks()
        dashboardChecks()
        accountChecks()
        loopbackChecks()
        civilDateChecks()
        spendRankChecks()
        await storeChecks()
        await apiClientChecks()
        if Check.failures > 0 {
            fputs("\(Check.failures) failure(s)\n", stderr)
            exit(1)
        }
        print("all checks passed")
    }
}
