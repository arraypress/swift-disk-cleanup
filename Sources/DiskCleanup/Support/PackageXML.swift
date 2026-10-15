//
//  PackageXML.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  What a flat package says it installs, from the two XML files `xar` can
//  read out of it without touching the payload: `Distribution` (product
//  archives) and `PackageInfo` (each component).
//

import Foundation

enum PackageXML {

    /// Reads a Distribution file and any number of PackageInfo files.
    static func contents(distribution: Data?, packageInfos: [Data]) -> PackageContents {
        var contents = PackageContents()
        if let distribution {
            let reader = Reader()
            reader.read(distribution)
            contents.title = reader.title
            contents.packages += reader.packages
            contents.bundles += reader.bundles
        }
        for info in packageInfos {
            let reader = Reader()
            reader.read(info)
            contents.packages += reader.packages
            contents.bundles += reader.bundles
        }
        // One receipt per id, keeping the first version that named it.
        var seen = Set<String>()
        contents.packages = contents.packages.filter { seen.insert($0.id).inserted }
        var seenBundles = Set<String>()
        contents.bundles = contents.bundles.filter { seenBundles.insert($0.bundleID + "|" + ($0.version ?? "")).inserted }
        return contents
    }

    private final class Reader: NSObject, XMLParserDelegate {
        var packages: [PackageRef] = []
        var bundles: [BundleInfo] = []
        var title: String?
        private var inTitle = false
        private var titleText = ""

        func read(_ data: Data) {
            let parser = XMLParser(data: data)
            parser.delegate = self
            parser.shouldResolveExternalEntities = false
            parser.parse()
        }

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch element {
            case "pkg-ref":
                // A Distribution names each pkg-ref twice: once with the version, once
                // in a choice without it. Only a versioned one is a receipt to compare.
                if let id = attributes["id"], let version = attributes["version"], !version.isEmpty {
                    packages.append(PackageRef(id: id, version: version))
                }
            case "pkg-info":
                if let id = attributes["identifier"] {
                    packages.append(PackageRef(id: id, version: attributes["version"]))
                }
            case "bundle":
                if let id = attributes["id"] ?? attributes["CFBundleIdentifier"] {
                    // Only apps: a pkg also lists its frameworks and plug-ins as bundles.
                    // The bare `<bundle id=…/>` lines inside bundle-version and
                    // upgrade-bundle only point back at these, without versions.
                    let path = attributes["path"] ?? ""
                    if path.hasSuffix(".app") {
                        bundles.append(BundleInfo(
                            bundleID: id,
                            version: attributes["CFBundleShortVersionString"],
                            build: attributes["CFBundleVersion"],
                            name: PathText.lastComponent(path).replacingOccurrences(of: ".app", with: "")
                        ))
                    }
                }
            case "title":
                inTitle = true
                titleText = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inTitle { titleText += string }
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            if element == "title" {
                inTitle = false
                let text = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                if title == nil, !text.isEmpty { title = text }
            }
        }
    }
}
