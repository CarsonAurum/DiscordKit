import ActivityHostSupport

/// Build-only portable Activity consumer. A Discord-owned iframe and qualified browser binding are required at runtime.
@main struct ActivityHost {
    /// Describes injection requirements without opening a browser, creating tasks or using credentials.
    static func main() {
        print("Inject an authenticated ActivityTransport into ActivityClient, start explicitly, then use ActivityHostSession.")
    }
}
