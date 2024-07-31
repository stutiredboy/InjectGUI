//
//  InjectConfiguration.swift
//  InjectGUI
//
//  Created by wibus on 2024/7/19.
//

import Foundation
import Combine


// MARK: - InjectConfiguration
class InjectConfiguration: ObservableObject {
    static let shared = InjectConfiguration()
    
    @Published var remoteConf = nil as InjectConfigurationModel?
    
    private init() {
        updateRemoteConf()
    }
    
    private func downloadConfig(data: Data?) {
        let decoder = JSONDecoder()
        let conf = try! decoder.decode(InjectConfigurationModel.self, from: data!)
        remoteConf = conf
        print("[I] Downloaded config.json")
    }
    
    /// 更新远程配置
    func updateRemoteConf() {
        print("[*] Downloading config.json...")
        let url = configuration.remoteGit
        if url.isEmpty {
            configuration.remoteGit = "https://github.com/QiuChenly/InjectLib"
            updateRemoteConf()
            return
        }
        let commit = configuration.remoteGitCommit
        let branch = configuration.remoteGitBranch
        let branchOrCommit = !commit.isEmpty ? commit : !branch.isEmpty ? branch : "main"
        // <url>/raw/<branch or commit>/config.json
        let _url = "\(url)/raw/\(branchOrCommit)/config.json"
        let dataUrl = URL(string: _url)!
        
        let task = URLSession.shared.dataTask(with: dataUrl) { data, response, error in
            if let error = error {
                print("[W] Failed to download config.json: \(error.localizedDescription)")
                return
            }
            self.downloadConfig(data: data)
        }
        task.resume()
    }
    
    /// 设置远程配置来源
    func customRemoteConf(url: String, commit: String, branch: String) {
        configuration.remoteGit = url
        if branch.isEmpty {
            configuration.remoteGitBranch = "main"
        }
        configuration.remoteGitBranch = branch
        configuration.remoteGitCommit = commit
        updateRemoteConf()
    }

    /// 获取当前配置支持的 Package
    func getSupportedPackages() -> [Package] {
        guard let conf = remoteConf else {
            return []
        }

        var packages = [Package]()
        for app in conf.appList {
            for name in app.packageName.allStrings {
                if !packages.contains(where: { $0.name == name }) {
                    packages.append(Package(id: name, name: name))
                }
            }
        }
        
        return packages
    }

    // MARK: - Inject Tools

    /// 通用型 Func：生成注入工具下载地址
    func generateInjectToolDownloadURL(name: String) -> URL? {
        let url = configuration.remoteGit
        let branch = configuration.remoteGitBranch
        let commit = configuration.remoteGitCommit
        let branchOrCommit = !commit.isEmpty ? commit : !branch.isEmpty ? branch : "main"
        // <url>/raw/<branch or commit>/config.json
        let _url = "\(url)/raw/\(branchOrCommit)/tool/\(name)"
        let dataUrl = URL(string: _url)!
        return dataUrl
    }

    /// 通用型 Func：获取应用程序支持目录
    func downloadInjectTool(name: String) {
        print("[*] Downloading \(name)...")

        if isInjectToolExist(name: name) {
            print("[I] \(name) already exists")
            return
        }

        guard let url = generateInjectToolDownloadURL(name: name) else {
            print("[E] Failed to generate download URL for \(name)")
            return
        }
        let dataUrl = url
        let task = URLSession.shared.dataTask(with: dataUrl) { [self] data, response, error in
            guard let data = data else {
                print("[E] Failed to download \(name): \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let path = getApplicationSupportDirectory().path
                let _url = URL(fileURLWithPath: path).appendingPathComponent(name)
                try data.write(to: _url)

                print("[I] Downloaded \(name), save to \(path)")

                let _ = writeVersionMetadataIntoInjectTools(name: name, url: _url, version: "WIP")
            } catch {
                print("[E] Failed to download \(name): \(error.localizedDescription)")
            }
        }

        task.resume()
    }

    func isInjectToolExist(name: String) -> Bool {
        let path = getApplicationSupportDirectory().path
        let _url = URL(fileURLWithPath: path).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: _url.path)
    }

    func updateInjectTool(name: String) {
        print("[*] Updating \(name)...")
        if isInjectToolExist(name: name) {
            do {
                let path = getApplicationSupportDirectory().path
                let _url = URL(fileURLWithPath: path).appendingPathComponent(name)
                // let commit = getRemoteGitCommit()
                // let fileCommit = getInjectToolVersion(name: name)
                // if fileCommit != commit {
                    try FileManager.default.removeItem(at: _url)
                    print("[*] Removed \(name)")

                    // downloadInjectTool(name: name)
                // } else {
                    // print("[*] Same version.")
                    // return
                // }
            } catch {
                print("[E] Failed to remove \(name): \(error.localizedDescription)")
            }
        }
        // } else {
            // print("[*] Non exist. Download.")
            downloadInjectTool(name: name)
        // }
    }



    private func writeVersionMetadataIntoInjectTools(name: String, url: URL, version: String) -> Int {
        print("[*] Writing version metadata into  \(name)...")
        let attributeName = "org.91QiuChenly.InjectLib.Tool.version"
        let attributeValue = version.data(using: .utf8)
        let res = setxattr(url.path, attributeName, (attributeValue! as NSData).bytes.bindMemory(to: CChar.self, capacity: attributeValue!.count), attributeValue!.count, 0, 0)
        if res != 0 {
            print("[E] Failed to write version metadata into  \(name): \(String(cString: strerror(errno)))")
            return 0
        }
        print("[I] Wrote version metadata into  \(name)")
        return 1
    }


    func getInjectToolVersion(name: String) -> String? {
        let attributeName = "org.91QiuChenly.version"
        let path = getApplicationSupportDirectory().path
        let _url = URL(fileURLWithPath: path).appendingPathComponent(name)
        
        if FileManager.default.fileExists(atPath: _url.path) {
            // Prepare the buffer to receive the attribute value
            let bufferLength = getxattr(_url.path, attributeName, nil, 0, 0, 0)
            if bufferLength == -1 {
                print("[E] Failed to get the size of version metadata from \(name): \(String(cString: strerror(errno)))")
                return nil
            }

            var buffer = [CChar](repeating: 0, count: bufferLength + 1)  // +1 for the null terminator
            let result = getxattr(_url.path, attributeName, &buffer, bufferLength, 0, 0)
            if result == -1 {
                print("[E] Failed to get version metadata from  \(name): \(String(cString: strerror(errno)))")
                return "Unknown Version"
            }

            buffer[bufferLength] = 0  // Ensure null termination
            let version = String(cString: buffer)
            return version
        } else {
            print("[E]  \(name) does not exist at path: \(_url.path)")
        }
        
        return nil
    }

    // MARK: - General Functions

    func updateInjectTools() {
        updateInjectTool(name: "91QiuChenly.dylib")
        updateInjectTool(name: "GenShineImpactStarter")
    }


    func downloadAllInjectTools() {
        downloadInjectTool(name: "91QiuChenly.dylib")
        downloadInjectTool(name: "GenShineImpactStarter")
    }
    
    
    func update() {
        updateRemoteConf()
        updateInjectTools()
    }

    // MARK: - Inject Infos

    /// 获取注入 package 的详细信息
    func injectDetail(package: String) -> AppList? {
        guard let conf = remoteConf else {
            return nil
        }
        let app = conf.appList.first { $0.packageName.allStrings.contains(package) }
        guard let app = app else {
            return nil
        }
        return app
    }

    /// 检查此 package 是否被支持
    func checkPackageIsSupported(package: String) -> Bool {
        // print("[*] Checking if \(package) is supported...")
        guard let conf = remoteConf else {
            return false
        }
        let package = conf.appList.first { $0.packageName.allStrings.contains(package) }
        guard package != nil else {
            return false
        }
        return true
    }

}


struct Package: Identifiable {
    let id: String
    let name: String
}

// MARK: - InjectConfigurationModel
struct InjectConfigurationModel: Codable, Equatable {
    static func == (lhs: InjectConfigurationModel, rhs: InjectConfigurationModel) -> Bool {
        return lhs.project == rhs.project
            && lhs.author == rhs.author
            && lhs.version == rhs.version
    }
    
    let project, author: String
    let version: Double
    let basePublicConfig: BasePublicConfig
    let appList: [AppList]
    
    

    enum CodingKeys: String, CodingKey {
        case project
        case author = "Author"
        case version = "Version"
        case basePublicConfig
        case appList = "AppList"
    }
}

// MARK: - AppList
struct AppList: Codable {
    let packageName: PackageName
    let appBaseLocate, bridgeFile, injectFile: String?
    let needCopyToAppDir, noSignTarget, autoHandleHelper: Bool?
    let helperFile: HelperFile?
    let tccutil: Tccutil?
    let forQiuChenly, onlysh: Bool?
    let extraShell, smExtra: String?
    let componentApp: [String]?
    let deepSignApp, noDeep: Bool?
    let entitlements: String?
    let useOptool, autoHandleSetapp: Bool?
    let keygen: Bool?

    enum CodingKeys: String, CodingKey {
        case packageName, appBaseLocate, bridgeFile, injectFile, needCopyToAppDir, noSignTarget, autoHandleHelper, helperFile, tccutil, forQiuChenly, onlysh, extraShell
        case smExtra = "SMExtra"
        case componentApp, deepSignApp, noDeep, entitlements, useOptool, autoHandleSetapp, keygen
    }
}

enum HelperFile: Codable {
    case string(String)
    case stringArray([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode([String].self) {
            self = .stringArray(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(HelperFile.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for HelperFile"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x):
            try container.encode(x)
        case .stringArray(let x):
            try container.encode(x)
        }
    }
}

enum PackageName: Codable {
    case string(String)
    case stringArray([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode([String].self) {
            self = .stringArray(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(PackageName.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for PackageName"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x):
            try container.encode(x)
        case .stringArray(let x):
            try container.encode(x)
        }
    }
    
    
    var allStrings: [String] {
        switch self {
        case .string(let x):
            return [x]
        case .stringArray(let x):
            return x
        }
    }
}

enum Tccutil: Codable {
    case bool(Bool)
    case stringArray([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) {
            self = .bool(x)
            return
        }
        if let x = try? container.decode([String].self) {
            self = .stringArray(x)
            return
        }
        throw DecodingError.typeMismatch(Tccutil.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Tccutil"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let x):
            try container.encode(x)
        case .stringArray(let x):
            try container.encode(x)
        }
    }

    var allStrings: [String] {
        switch self {
        case .stringArray(let x):
            return x
        default:
            return []
        }
    }
}

// MARK: - BasePublicConfig
struct BasePublicConfig: Codable {
    let bridgeFile: String
}

// MARK: - GitCommit
struct GitCommit: Codable {
    let sha: String
}
