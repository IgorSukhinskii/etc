import LocalAuthentication
import Foundation

let reason = CommandLine.arguments.dropFirst().first ?? "Authenticate"
let context = LAContext()
var canError: NSError?

guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &canError) else {
    fputs("Touch ID not available: \(canError?.localizedDescription ?? "unknown")\n", stderr)
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 1

context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
    exitCode = success ? 0 : 1
    if let error = error {
        fputs("Touch ID: \(error.localizedDescription)\n", stderr)
    }
    semaphore.signal()
}

semaphore.wait()
exit(exitCode)
