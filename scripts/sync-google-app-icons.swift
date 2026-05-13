import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AppSprite {
    let resourceName: String
    let yOffset: Int
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
    then installs GWS Menu into ~/Applications.

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

let spriteURL = URL(string: "https://ssl.gstatic.com/gb/images/sprites/p_2x_d075c781870b.png")!
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    .standardizedFileURL
let rootDirectory = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outputDirectory = rootDirectory
    .appendingPathComponent("macos/GWSMenuBar/Sources/GWSMenuBar/Resources/WorkspaceIcons", isDirectory: true)
let scale = 2
let iconSize = 53 * scale

let apps: [AppSprite] = [
    AppSprite(resourceName: "account", yOffset: -2088),
    AppSprite(resourceName: "search", yOffset: -812),
    AppSprite(resourceName: "maps", yOffset: -2146),
    AppSprite(resourceName: "youtube", yOffset: -1102),
    AppSprite(resourceName: "news", yOffset: -232),
    AppSprite(resourceName: "gmail", yOffset: -522),
    AppSprite(resourceName: "meet", yOffset: -1856),
    AppSprite(resourceName: "chat", yOffset: -2494),
    AppSprite(resourceName: "contacts", yOffset: -464),
    AppSprite(resourceName: "drive", yOffset: -2030),
    AppSprite(resourceName: "calendar", yOffset: -1334),
    AppSprite(resourceName: "translate", yOffset: -986),
    AppSprite(resourceName: "photos", yOffset: -1682),
    AppSprite(resourceName: "finance", yOffset: -580),
    AppSprite(resourceName: "docs", yOffset: -2204),
    AppSprite(resourceName: "sheets", yOffset: -406),
    AppSprite(resourceName: "slides", yOffset: -2262),
    AppSprite(resourceName: "keep", yOffset: -116),
    AppSprite(resourceName: "ads", yOffset: -2610),
    AppSprite(resourceName: "forms", yOffset: -290),
    AppSprite(resourceName: "analytics", yOffset: -2668)
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

print("Synced \(apps.count) Google app launcher icons and \(standaloneIcons.count) standalone Google service icons into git-ignored local resources.")

if !args.contains(noInstallFlag) {
    let installScript = rootDirectory.appendingPathComponent("scripts/install-macos-app.sh")
    let process = Process()
    process.executableURL = installScript
    process.arguments = args.contains(noOpenFlag) ? ["--user", "--no-open"] : ["--user"]
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
