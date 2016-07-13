/*
 This source file is part of the Swift.org open source project

 Copyright 2015 - 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if os(Linux)
import Glibc
#else
import Darwin.C
#endif

/// The description for a complete package.
public final class Package {
    /// The description for a package dependency.
    public class Dependency {
        public let versionRange: Range<Version>
        public let url: String

        init(_ url: String, _ versionRange: Range<Version>) {
            self.url = url
            self.versionRange = versionRange
        }

        convenience init(_ url: String, _ versionRange: ClosedRange<Version>) {
            self.init(url, versionRange.lowerBound..<versionRange.upperBound.successor())
        }

        public class func Package(url: String, versions: Range<Version>) -> Dependency {
            return Dependency(url, versions)
        }
        public class func Package(url: String, versions: ClosedRange<Version>) -> Dependency {
            return Package(url: url, versions: versions.lowerBound..<versions.upperBound.successor())
        }
        public class func Package(url: String, majorVersion: Int) -> Dependency {
            return Dependency(url, Version(majorVersion, 0, 0)..<Version(majorVersion, .max, .max))
        }
        public class func Package(url: String, majorVersion: Int, minor: Int) -> Dependency {
            return Dependency(url, Version(majorVersion, minor, 0)..<Version(majorVersion, minor, .max))
        }
        public class func Package(url: String, _ version: Version) -> Dependency {
            return Dependency(url, version...version)
        }
    }
    
    /// The name of the package.
    public let name: String
  
    /// pkgconfig name to use for C Modules. If present, swiftpm will try to search for
    /// <name>.pc file to get the additional flags needed for the system module.
    public let pkgConfig: String?
    
    /// Providers array for System module
    public let providers: [SystemPackageProvider]?
  
    /// The list of targets.
    public var targets: [Target]

    /// The list of dependencies.
    public var dependencies: [Dependency]

    /// The list of test dependencies. They aren't exposed to a parent Package
    public var testDependencies: [Dependency]

    /// The list of folders to exclude.
    public var exclude: [String]

    /// Construct a package.
    public init(name: String, pkgConfig: String? = nil, providers: [SystemPackageProvider]? = nil, targets: [Target] = [], dependencies: [Dependency] = [], testDependencies: [Dependency] = [], exclude: [String] = []) {
        self.name = name
        self.pkgConfig = pkgConfig
        self.providers = providers
        self.targets = targets
        self.dependencies = dependencies
        self.testDependencies = testDependencies
        self.exclude = exclude

        // Add custom exit handler to cause package to be dumped at exit, if requested.
        //
        // FIXME: This doesn't belong here, but for now is the mechanism we use
        // to get the interpreter to dump the package when attempting to load a
        // manifest.

        // FIXME: Additional hackery here to avoid accessing 'arguments' in a
        // process whose 'main' isn't generated by Swift.
        // See https://bugs.swift.org/browse/SR-1119.
        if Process.argc > 0 {
            if let fileNoOptIndex = Process.arguments.index(of: "-fileno"),
                   let fileNo = Int32(Process.arguments[fileNoOptIndex + 1]) {
                dumpPackageAtExit(self, fileNo: fileNo)
            }
        }
    }
}

public enum SystemPackageProvider {
    case Brew(String)
    case Apt(String)
}

extension SystemPackageProvider {
    public var nameValue: (String, String) {
        switch self {
        case .Brew(let name):
            return ("Brew", name)
        case .Apt(let name):
            return ("Apt", name)
        }
    }
}

// MARK: TOMLConvertible

extension SystemPackageProvider: TOMLConvertible {
    
    public func toTOML() -> String {
        let (name, value) = nameValue
        var str = ""
        str += "name = \(name)\n"
        str += "value = \"\(value)\"\n"
        return str
    }
}

extension Package.Dependency: TOMLConvertible {
    public func toTOML() -> String {
        return "[\"\(url)\", \"\(versionRange.lowerBound)\", \"\(versionRange.upperBound)\"],"
    }
}

extension Package: TOMLConvertible {
    public func toTOML() -> String {
        var result = ""
        result += "[package]\n"
        result += "name = \"\(name)\"\n"
        if let pkgConfig = self.pkgConfig {
            result += "pkgConfig = \"\(pkgConfig)\"\n"
        }
        result += "dependencies = ["
        for dependency in dependencies {
            result += dependency.toTOML()
        }
        result += "]\n"

        result += "testDependencies = ["
        for dependency in testDependencies {
            result += dependency.toTOML()
        }
        result += "]\n"

        result += "\n" + "exclude = \(exclude)" + "\n"

        for target in targets {
            result += "[[package.targets]]\n"
            result += target.toTOML()
        }
        
        if let providers = self.providers {
            for provider in providers {
                result += "[[package.providers]]\n"
                result += provider.toTOML()
            }
        }
        
        return result
    }
}

// MARK: Equatable
extension Package : Equatable { }
public func ==(lhs: Package, rhs: Package) -> Bool {
    return (lhs.name == rhs.name &&
        lhs.targets == rhs.targets &&
        lhs.dependencies == rhs.dependencies)
}

extension Package.Dependency : Equatable { }
public func ==(lhs: Package.Dependency, rhs: Package.Dependency) -> Bool {
    return lhs.url == rhs.url && lhs.versionRange == rhs.versionRange
}

// MARK: Package Dumping

private var dumpInfo: (package: Package, fileNo: Int32)? = nil
private func dumpPackageAtExit(_ package: Package, fileNo: Int32) {
    func dump() {
        guard let dumpInfo = dumpInfo else { return }
        let fd = fdopen(dumpInfo.fileNo, "w")
        guard fd != nil else { return }
        fputs(dumpInfo.package.toTOML(), fd)
        for product in products {
            fputs("[[products]]", fd)
            fputs("\n", fd)
            fputs(product.toTOML(), fd)
            fputs("\n", fd)
        }
        fclose(fd)
    }
    dumpInfo = (package, fileNo)
    atexit(dump)
}
