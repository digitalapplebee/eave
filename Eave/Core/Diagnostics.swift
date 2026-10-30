import OSLog

enum Diagnostics {
    static let rendering = Logger(subsystem: "com.eaveapp.Eave", category: "Rendering")
    static let wallpaper = Logger(subsystem: "com.eaveapp.Eave", category: "Wallpaper")
}
