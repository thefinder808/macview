/// The process entry point. MacView re-runs its own executable as a short-lived
/// child to try drawing vector images safely (`VectorProbe`), and that must be
/// handled before SwiftUI starts — a probe launch never becomes an app.
@main
enum Main {
    static func main() {
        VectorProbe.runChildIfRequested()
        MacViewApp.main()
    }
}
