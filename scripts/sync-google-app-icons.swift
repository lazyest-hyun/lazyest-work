import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AppSprite {
    let resourceName: String
    let yOffset: Int
}

struct LauncherIcon {
    let resourceName: String
    let pid: Int
}

struct StandaloneIcon {
    let resourceName: String
    let url: URL
}

let acceptedFlag = "--accept-google-brand-terms"
let noInstallFlag = "--no-install"
let noOpenFlag = "--no-open"
let args = Set(CommandLine.arguments.dropFirst())
guard args.contains(acceptedFlag) else {
    fputs("""
    This script downloads Google product icon assets for local/internal use only,
    then installs GWS Menu into /Applications.

    The public repository intentionally does not ship third-party brand assets.
    Before running this, review Google's brand/trademark rules and make sure your
    use is permitted:

      https://about.google/brand-resource-center/products-and-services/
      https://opensource.google/documentation/reference/using/trademarks

    To install with local, git-ignored Google app icons:

      swift scripts/sync-google-app-icons.swift \(acceptedFlag)

    To sync icons without installing:

      swift scripts/sync-google-app-icons.swift \(acceptedFlag) \(noInstallFlag)

    """, stderr)
    exit(64)
}

let launcherWidgetURL = URL(string: "https://ogs.google.com/widget/app/so?eom=1&awwd=1&em=2&origin=https%3A%2F%2Fwww.google.com&cn=app&pid=1&spid=1&hl=en")!
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    .standardizedFileURL
let rootDirectory = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = rootDirectory
    .appendingPathComponent("macos/GWSMenuBar/Sources/GWSMenuBar/Resources/WorkspaceIcons", isDirectory: true)
let scale = 2
let iconSize = 53 * scale

let launcherIcons: [LauncherIcon] = [
    LauncherIcon(resourceName: "account", pid: 192),
    LauncherIcon(resourceName: "search", pid: 1),
    LauncherIcon(resourceName: "maps", pid: 8),
    LauncherIcon(resourceName: "youtube", pid: 36),
    LauncherIcon(resourceName: "news", pid: 426),
    LauncherIcon(resourceName: "gmail", pid: 23),
    LauncherIcon(resourceName: "meet", pid: 411),
    LauncherIcon(resourceName: "chat", pid: 385),
    LauncherIcon(resourceName: "contacts", pid: 53),
    LauncherIcon(resourceName: "drive", pid: 49),
    LauncherIcon(resourceName: "calendar", pid: 24),
    LauncherIcon(resourceName: "translate", pid: 51),
    LauncherIcon(resourceName: "photos", pid: 31),
    LauncherIcon(resourceName: "finance", pid: 27),
    LauncherIcon(resourceName: "docs", pid: 25),
    LauncherIcon(resourceName: "sheets", pid: 283),
    LauncherIcon(resourceName: "slides", pid: 281),
    LauncherIcon(resourceName: "keep", pid: 136),
    LauncherIcon(resourceName: "ads", pid: 304),
    LauncherIcon(resourceName: "forms", pid: 330),
    LauncherIcon(resourceName: "analytics", pid: 44)
]

let standaloneIcons: [StandaloneIcon] = [
    StandaloneIcon(resourceName: "admin", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/admin_48dp.png")!),
    StandaloneIcon(resourceName: "groups", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/groups_48dp.png")!),
    StandaloneIcon(resourceName: "apps-script", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/apps_script_48dp.png")!),
    StandaloneIcon(resourceName: "cloud-search", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/cloud_search_48dp.png")!),
    StandaloneIcon(resourceName: "vault", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/vault_48dp.png")!),
    StandaloneIcon(resourceName: "cloud-console", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/google_cloud_48dp.png")!),
    StandaloneIcon(resourceName: "gemini", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/gemini_48dp.png")!),
    StandaloneIcon(resourceName: "notebooklm", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/notebooklm_48dp.png")!),
    StandaloneIcon(resourceName: "colab", url: URL(string: "https://colab.research.google.com/img/colab_favicon_256px.png")!),
    StandaloneIcon(resourceName: "search-console", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/search_console_48dp.png")!),
    StandaloneIcon(resourceName: "tag-manager", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/google_tag_manager_48dp.png")!),
    StandaloneIcon(resourceName: "sites", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/sites_48dp.png")!),
    StandaloneIcon(resourceName: "tasks", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/tasks_48dp.png")!),
    StandaloneIcon(resourceName: "voice", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/voice_48dp.png")!),
    StandaloneIcon(resourceName: "classroom", url: URL(string: "https://www.gstatic.com/images/branding/product/2x/classroom_48dp.png")!)
]

func downloadData(from sourceURL: URL) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<Data, Error>!
    var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.setValue("GWSMenuIconSync/1.0", forHTTPHeaderField: "User-Agent")

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if let error {
            result = .failure(error)
            return
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            result = .failure(NSError(
                domain: "GWSMenuIconSync",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Download failed with HTTP \(status) for \(sourceURL.absoluteString)"]
            ))
            return
        }
        guard let data, !data.isEmpty else {
            result = .failure(NSError(
                domain: "GWSMenuIconSync",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded empty response from \(sourceURL.absoluteString)"]
            ))
            return
        }
        result = .success(data)
    }
    task.resume()
    semaphore.wait()
    return try result.get()
}

func downloadString(from sourceURL: URL) throws -> String {
    let data = try downloadData(from: sourceURL)
    guard let string = String(data: data, encoding: .utf8) else {
        throw NSError(
            domain: "GWSMenuIconSync",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Downloaded response is not UTF-8 from \(sourceURL.absoluteString)"]
        )
    }
    return string
}

func firstRegexMatch(in string: String, pattern: String, group: Int = 0) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    guard let match = regex.firstMatch(in: string, range: range),
          let matchRange = Range(match.range(at: group), in: string) else {
        return nil
    }
    return String(string[matchRange])
}

func allRegexMatches(in string: String, pattern: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }
    let range = NSRange(string.startIndex..<string.endIndex, in: string)
    return regex.matches(in: string, range: range).map { match in
        (0..<match.numberOfRanges).compactMap { index in
            guard let matchRange = Range(match.range(at: index), in: string) else {
                return nil
            }
            return String(string[matchRange])
        }
    }
}

func normalizedGoogleAssetURL(_ rawValue: String) -> URL? {
    var value = rawValue
        .replacingOccurrences(of: #"\/"#, with: "/")
        .replacingOccurrences(of: #"\\u003d"#, with: "=")
        .replacingOccurrences(of: #"\\u0026"#, with: "&")
        .replacingOccurrences(of: #"\u003d"#, with: "=")
        .replacingOccurrences(of: #"\u0026"#, with: "&")
    if value.hasPrefix("//") {
        value = "https:" + value
    }
    return URL(string: value)
}

func parseLauncherSpriteURL(from html: String) throws -> URL {
    let patterns = [
        #"https:\\/\\/ssl\.gstatic\.com\\/gb\\/images\\/sprites\\/p_2x_[^"\\]+\.png"#,
        #"https://ssl\.gstatic\.com/gb/images/sprites/p_2x_[^"'<>\s]+\.png"#,
        #"//ssl\.gstatic\.com/gb/images/sprites/p_2x_[^"'<>\s]+\.png"#
    ]
    for pattern in patterns {
        if let rawValue = firstRegexMatch(in: html, pattern: pattern),
           let url = normalizedGoogleAssetURL(rawValue) {
            return url
        }
    }
    throw NSError(
        domain: "GWSMenuIconSync",
        code: 8,
        userInfo: [NSLocalizedDescriptionKey: "Could not find the current Google app launcher sprite URL"]
    )
}

func parseLauncherIconOffsets(from html: String) throws -> [Int: Int] {
    let pattern = #"\[(\d+),"(?:[^"\\]|\\.)*","0 (-?\d+)px""#
    var offsets: [Int: Int] = [:]
    for match in allRegexMatches(in: html, pattern: pattern) where match.count == 3 {
        guard let pid = Int(match[1]), let yOffset = Int(match[2]) else {
            continue
        }
        offsets[pid] = yOffset
    }
    if offsets.isEmpty {
        throw NSError(
            domain: "GWSMenuIconSync",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Could not find Google app launcher icon offsets"]
        )
    }
    return offsets
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "GWSMenuIconSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination for \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "GWSMenuIconSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG to \(url.path)"])
    }
}

func writeDownloadedPNG(from sourceURL: URL, to destinationURL: URL) throws {
    let data = try downloadData(from: sourceURL)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "GWSMenuIconSync", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not decode \(sourceURL.absoluteString)"])
    }
    try writePNG(image, to: destinationURL)
}

let launcherHTML = try downloadString(from: launcherWidgetURL)
let spriteURL = try parseLauncherSpriteURL(from: launcherHTML)
let offsetsByPID = try parseLauncherIconOffsets(from: launcherHTML)
let apps = try launcherIcons.map { icon in
    guard let yOffset = offsetsByPID[icon.pid] else {
        throw NSError(
            domain: "GWSMenuIconSync",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "Could not find Google app launcher offset for \(icon.resourceName)"]
        )
    }
    return AppSprite(resourceName: icon.resourceName, yOffset: yOffset)
}

let data = try downloadData(from: spriteURL)
guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let sprite = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    throw NSError(domain: "GWSMenuIconSync", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not decode Google app sprite"])
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for app in apps {
    let crop = CGRect(x: 0, y: abs(app.yOffset) * scale, width: iconSize, height: iconSize)
    guard let icon = sprite.cropping(to: crop) else {
        throw NSError(domain: "GWSMenuIconSync", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not crop \(app.resourceName) from sprite"])
    }
    try writePNG(icon, to: outputDirectory.appendingPathComponent("\(app.resourceName).png"))
}

for icon in standaloneIcons {
    try writeDownloadedPNG(from: icon.url, to: outputDirectory.appendingPathComponent("\(icon.resourceName).png"))
}

print("Synced \(apps.count) Google app launcher icons from \(spriteURL.lastPathComponent) and \(standaloneIcons.count) standalone Google service icons into git-ignored local resources.")

if !args.contains(noInstallFlag) {
    let installScript = rootDirectory.appendingPathComponent("scripts/install-macos-app.sh")
    let process = Process()
    process.executableURL = installScript
    process.arguments = args.contains(noOpenFlag) ? ["--no-open"] : []
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        throw NSError(
            domain: "GWSMenuIconSync",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "Install failed with exit code \(process.terminationStatus)"]
        )
    }
}
